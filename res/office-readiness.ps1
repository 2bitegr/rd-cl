# Shared with the installed worker. Loading this library performs no writes.
function Get-OfficeRebootReasons {
    $reasons = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' -ErrorAction Stop) {
        $reasons.Add('windows_servicing_restart')
    }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction Stop) {
        $reasons.Add('windows_update_restart')
    }
    $session = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop
    # Match the worker's existing presence check, including an empty value.
    if ($null -ne $session.PSObject.Properties['PendingFileRenameOperations']) {
        $reasons.Add('pending_file_operations')
    }
    return $reasons.ToArray()
}

function Assert-OfficeInstalledPath([string]$Path) {
    # Windows servicing may retain TrustedInstaller write access on Program Files.
    # Trust its exact service SID independently of localized account names.
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse_path' }
        $item = if ($item -is [IO.DirectoryInfo]) {$item.Parent} else {$item.Directory}
    }
    $acl=Get-Acl -LiteralPath $Path
    foreach($rule in $acl.Access) {
        if($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band 0xD0156) -ne 0 -and
          ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -eq 0 -and
          $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544',
            'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) {throw 'install_directory_not_protected'}
    }
}

function Get-OfficeServiceSnapshot($Config) {
    $service = Get-CimInstance Win32_Service -Filter "Name='Exantas Support'" -ErrorAction Stop
    if (!$service) { return $null }
    $expected = '"' + $Config.expected_exe + '" --service'
    $data = @($service.Name, $service.PathName, $service.StartName, $service.State, $service.StartMode, $Config.expected_exe)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $fingerprint = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json -Compress))))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return @{ service = $service; exact = ($service.PathName -ieq $expected -and $service.StartName -in @('LocalSystem', 'SYSTEM')); fingerprint = $fingerprint }
}

function Get-OfficeInstallReadiness($Config) {
    $checks = [System.Collections.Generic.List[object]]::new()
    function Add-Readiness($code, $status, $action = $null) {
        $checks.Add(@{code = $code; status = $status; action = $action})
    }
    try {
        $reboots = @(Get-OfficeRebootReasons)
        if ($reboots.Count) {
            foreach ($reason in $reboots) { Add-Readiness $reason 'blocked' 'windows_update' }
        } else { Add-Readiness 'restart_clear' 'ok' }
    } catch { Add-Readiness 'restart_unconfirmed' 'unknown' }
    Add-Readiness 'windows_x64' $(if ([Environment]::Is64BitOperatingSystem -and $env:PROCESSOR_ARCHITECTURE -ne 'ARM64') {'ok'} else {'unsupported'})
    if ($null -eq $Config.msi) { Add-Readiness 'installation_mode_unconfirmed' 'unknown' }
    else { Add-Readiness 'exe_installation' $(if ($Config.msi) {'unsupported'} elseif ($Config.installed) {'ok'} else {'pending'}) }
    try {
        $target = [IO.Path]::GetFullPath($Config.target_dir)
        if ($target.StartsWith('\\')) { throw 'local_volume_required' }
        $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($target))
        # A minimum pre-install headroom check, not a future package-size guarantee.
        Add-Readiness 'minimum_space' $(if ($drive.AvailableFreeSpace -ge 1GB) {'ok'} else {'blocked'})
    } catch { Add-Readiness 'space_unconfirmed' 'unknown' }
    $fingerprint = $null
    if ($Config.installed) {
        $protected = $false
        try {
            Assert-OfficeInstalledPath $Config.expected_exe
            Assert-OfficeInstalledPath (Split-Path -Parent $Config.expected_exe)
            $protected = $true
            Add-Readiness 'installation_protected' 'ok'
        } catch { Add-Readiness 'installation_protection_unconfirmed' 'unknown' }
        $repairProtected = $false
        if ($protected) {
            try { Assert-OfficeProtectedServiceFile $Config.expected_exe; $repairProtected = $true } catch {}
        }
        try {
            $snapshot = Get-OfficeServiceSnapshot $Config
            if (!$snapshot) { Add-Readiness 'service_missing' 'blocked' }
            elseif (!$snapshot.exact) { Add-Readiness 'service_configuration_changed' 'blocked' }
            else {
                if ($repairProtected -and $Config.msi -eq $false) { $fingerprint = $snapshot.fingerprint }
                if ($snapshot.service.State -eq 'Running') { Add-Readiness 'service_running' 'ok' }
                elseif ($snapshot.service.State -eq 'Stopped') { Add-Readiness 'service_stopped' 'blocked' 'start_service' }
                else { Add-Readiness 'service_transitioning' 'pending' }
                if ($snapshot.service.StartMode -eq 'Auto') { Add-Readiness 'service_automatic' 'ok' }
                else { Add-Readiness 'service_not_automatic' 'blocked' 'automatic_service' }
            }
        } catch { Add-Readiness 'service_unconfirmed' 'unknown' }
    } else { Add-Readiness 'service_after_install' 'pending' }
    return @{schema = 1; checked_at = [DateTime]::UtcNow.ToString('o'); checks = $checks.ToArray(); repair_fingerprint = $fingerprint; repair_target = $(if ($fingerprint) {$Config.expected_exe} else {$null})}
}

function Test-OfficeRepairAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-OfficeProtectedServiceFile([string]$Executable) {
    # Starting a service must never execute a replaced or user-writable binary.
    $item = Get-Item -LiteralPath $Executable -Force -ErrorAction Stop
    $protectedRoot = [IO.Path]::GetFullPath($env:ProgramFiles)
    $expectedPath = [IO.Path]::GetFullPath($Executable)
    if (!$expectedPath.StartsWith($protectedRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'protected_installation_required' }
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse_path' }
        $acl = Get-Acl -LiteralPath $item.FullName -ErrorAction Stop
        $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($owner -notin @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) { throw 'untrusted_install_owner' }
        foreach ($rule in $acl.Access) {
            $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
            if ($rule.AccessControlType -eq 'Allow' -and $sid -notin @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464') -and
                ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -eq 0 -and
                ([int]$rule.FileSystemRights -band 0xD0156) -ne 0) { throw 'untrusted_install_write_access' }
        }
        if ($item.FullName.TrimEnd('\') -ieq $protectedRoot.TrimEnd('\')) { break }
        $item = if ($item -is [IO.DirectoryInfo]) {$item.Parent} else {$item.Directory}
    }
}

function Repair-OfficeInstallReadiness($Config, [string]$Action, [string]$Fingerprint) {
    if ($Action -notin @('start_service', 'automatic_service') -or $Fingerprint -cnotmatch '^[a-f0-9]{64}$') { throw 'invalid_repair' }
    if (!(Test-OfficeRepairAdministrator)) { throw 'administrator_required' }
    if ($Config.installed -ne $true -or $Config.msi -ne $false) { throw 'installed_exe_required' }
    Assert-OfficeProtectedServiceFile $Config.expected_exe
    $snapshot = Get-OfficeServiceSnapshot $Config
    if (!$snapshot -or !$snapshot.exact -or $snapshot.fingerprint -cne $Fingerprint) { throw 'repair_state_changed' }
    if ($Action -eq 'start_service') {
        if ($snapshot.service.State -ne 'Stopped') { throw 'repair_state_changed' }
        Start-Service -Name 'Exantas Support' -ErrorAction Stop
        (Get-Service -Name 'Exantas Support').WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
    } else {
        Set-Service -Name 'Exantas Support' -StartupType Automatic -ErrorAction Stop
        if ((Get-CimInstance Win32_Service -Filter "Name='Exantas Support'" -ErrorAction Stop).StartMode -ne 'Auto') { throw 'repair_unconfirmed' }
    }
    return @{schema = 1; action = $Action; applied = $true}
}
