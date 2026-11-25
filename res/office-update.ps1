param([string]$CorePath, [string]$ServiceName, [switch]$LibraryOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:reportedAcceptedPoll = $false

function Write-UpdateState($Path, $Value) {
    $temporary = "$Path.new"
    Assert-UpdatePath (Split-Path -Parent $Path)
    if(Test-Path -LiteralPath $Path){Assert-UpdatePath $Path}
    if(Test-Path -LiteralPath $temporary){Assert-UpdatePath $temporary}
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 30 -Compress))
    $stream = [IO.File]::Open($temporary, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
    else { [IO.File]::Move($temporary, $Path) }
}

function Assert-UpdatePath([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse_path' }
        $item = if ($item -is [IO.DirectoryInfo]) { $item.Parent } else { $item.Directory }
    }
}

function Assert-PrivateUpdateDirectory([string]$Root) {
    Assert-UpdatePath $Root
    $acl = Get-Acl -LiteralPath $Root
    $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($owner -notin @('S-1-5-18','S-1-5-32-544')) { throw 'untrusted_update_owner' }
    foreach ($rule in $acl.Access) {
        $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($rule.AccessControlType -eq 'Allow' -and $sid -notin @('S-1-5-18','S-1-5-32-544')) { throw 'untrusted_update_acl' }
    }
}

function Write-UpdateDiagnostic([string]$Code) {
    Assert-PrivateUpdateDirectory $script:root
    $safeCode=if($Code -cmatch '^[a-z_]{1,64}$'){$Code}else{'update_startup_failed'}
    $log=Join-Path $script:root 'update.jsonl'
    if(Test-Path -LiteralPath $log){Assert-UpdatePath $log}
    if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 1048576) {
        $previous="$log.previous"
        if(Test-Path -LiteralPath $previous){Assert-UpdatePath $previous}
        Move-Item -LiteralPath $log -Destination $previous -Force
    }
    [IO.File]::AppendAllText($log,(@{at=[DateTime]::UtcNow.ToString('o');code=$safeCode}|ConvertTo-Json -Compress)+[Environment]::NewLine)
}

function Test-SafeRuntimePath([string]$Path) {
    if (!$Path -or $Path.Length -gt 240 -or $Path.Contains('\')) { return $false }
    foreach ($part in $Path.Split('/')) {
        if ($part -notmatch '^[A-Za-z0-9_. -]+$' -or $part -in @('.','..') -or $part -match '[. ]$' -or $part -match '^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)') { return $false }
    }
    return $true
}

function Get-RuntimeInventory([string]$Root) {
    Assert-UpdatePath $Root
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force)
    foreach ($file in $files) {
        Assert-UpdatePath $file.FullName
        $relative = $file.FullName.Substring($Root.TrimEnd('\').Length + 1).Replace('\','/')
        if (!(Test-SafeRuntimePath $relative)) { throw 'unsafe_runtime_path' }
        [pscustomobject]@{path=$relative;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant();size_bytes=$file.Length}
    }
}

function Assert-RuntimeInventory([string]$Root, $Files, [switch]$Exact) {
    $seen = @{}
    foreach ($file in $Files) {
        if (!(Test-SafeRuntimePath $file.path) -or $seen.ContainsKey($file.path.ToLowerInvariant())) { throw 'unsafe_runtime_inventory' }
        $seen[$file.path.ToLowerInvariant()] = $true
        $path = Join-Path $Root $file.path
        Assert-UpdatePath $path
        $item = Get-Item -LiteralPath $path
        if ($item.Length -ne $file.size_bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256) { throw 'runtime_hash_mismatch' }
    }
    if ($Exact -and @(Get-RuntimeInventory $Root).Count -ne $seen.Count) { throw 'extra_runtime_files' }
}

function Copy-VerifiedRuntime([string]$Source, [string]$Destination, $Files) {
    Assert-RuntimeInventory $Source $Files
    foreach ($file in $Files) {
        $to = Join-Path $Destination $file.path
        $parent = Split-Path -Parent $to
        if (!(Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Assert-UpdatePath $parent
        if (Test-Path -LiteralPath $to) { Assert-UpdatePath $to }
        if(!$LibraryOnly -and $Destination -eq $script:installRoot) {
            Assert-ProtectedInstallation $parent
            if(Test-Path -LiteralPath $to){Assert-ProtectedInstallation $to}
        }
        if((Test-Path -LiteralPath $to) -and (Get-Item -LiteralPath $to).Length -eq $file.size_bytes -and
          (Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $file.sha256){continue}
        Copy-UpdateFile (Join-Path $Source $file.path) $to
    }
    Assert-RuntimeInventory $Destination $Files
}

function Copy-UpdateFile([string]$From, [string]$To) {
    if(!('ExantasUpdateAtomicFile' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class ExantasUpdateAtomicFile {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
  static extern bool MoveFileEx(string source,string target,int flags);
  public static void Copy(string source,string target) {
    string temporary=target+".rdcl-"+Guid.NewGuid().ToString("N")+".tmp";
    bool created=false;
    try {
      using(var input=new FileStream(source,FileMode.Open,FileAccess.Read,FileShare.Read))
      using(var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
        created=true; input.CopyTo(output); output.Flush(true);
      }
      if(File.Exists(target)) File.SetAccessControl(temporary,File.GetAccessControl(target));
      // Replace the directory entry; never overwrite data through a hardlink.
      if(!MoveFileEx(temporary,target,0x1|0x8)) throw new Win32Exception(Marshal.GetLastWin32Error());
      created=false;
    } finally {if(created && File.Exists(temporary))File.Delete(temporary);}
  }
}
'@
    }
    [ExantasUpdateAtomicFile]::Copy($From,$To)
}

function Assert-ProtectedInstallation([string]$Path) {
    # Windows servicing may retain TrustedInstaller write access on Program Files.
    # Trust its exact service SID independently of localized account names.
    Assert-UpdatePath $Path
    $acl=Get-Acl -LiteralPath $Path
    foreach($rule in $acl.Access) {
        if($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band 0xD0156) -ne 0 -and
          ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -eq 0 -and
          $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544',
            'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) {throw 'install_directory_not_protected'}
    }
}

function ConvertTo-UpdateCoreArgument([string]$Value) {
    if ($Value.IndexOf([char]0) -ge 0) { throw 'core_argument_invalid' }
    # Quote argv for CreateProcess, never for a shell. Double backslashes before
    # a quote and before the closing quote (including empty/trailing-slash args).
    $quoted = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $quoted = [regex]::Replace($quoted, '(\\+)$', '$1$1')
    return '"' + $quoted + '"'
}

function Invoke-UpdateCore([string]$Operation, [string[]]$Arguments = @()) {
    # This core is a Windows GUI executable. Bind output and exit status to the
    # process we create, not PowerShell's ambient/possibly absent LASTEXITCODE.
    $process = [Diagnostics.Process]::new()
    $started = $false
    $failureCode = 'core_start_failed'
    $knownCodes = @('core_argument_invalid','core_start_failed','core_capture_failed',
      'core_timeout','core_output_invalid','core_check_failed','core_stderr_invalid','core_response_invalid')
    try {
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $script:CorePath
        $start.WorkingDirectory = Split-Path -Parent $script:CorePath
        $start.Arguments = (@(@($Operation) + @($Arguments) | ForEach-Object {
            ConvertTo-UpdateCoreArgument ([string]$_)
        }) -join ' ')
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false, $true)
        $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false, $true)
        $process.StartInfo = $start
        if (!$process.Start()) { throw 'core_start_failed' }
        $started = $true
        $failureCode = 'core_capture_failed'
        $process.StandardInput.Close()
        # Drain both pipes concurrently, with bounded buffers and a shared
        # deadline. A noisy helper must not deadlock or grow memory unboundedly.
        $streams = @(
            @{reader=$process.StandardOutput;buffer=[char[]]::new(4096);text=[Text.StringBuilder]::new();done=$false;pending=$null},
            @{reader=$process.StandardError;buffer=[char[]]::new(4096);text=[Text.StringBuilder]::new();done=$false;pending=$null}
        )
        foreach ($stream in $streams) {
            $stream.pending = $stream.reader.ReadAsync($stream.buffer, 0, $stream.buffer.Length)
        }
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            $progress = $false
            foreach ($stream in $streams) {
                if (!$stream.done -and $stream.pending.IsCompleted) {
                    $count = $stream.pending.GetAwaiter().GetResult()
                    if ($count -eq 0) { $stream.done = $true }
                    else {
                        if ($stream.text.Length + $count -gt 1048576) { throw 'core_output_invalid' }
                        $null = $stream.text.Append($stream.buffer, 0, $count)
                        $stream.pending = $stream.reader.ReadAsync($stream.buffer, 0, $stream.buffer.Length)
                    }
                    $progress = $true
                }
            }
            if ($process.WaitForExit(0) -and $streams[0].done -and $streams[1].done) { break }
            if ($timer.ElapsedMilliseconds -ge 30000) { throw 'core_timeout' }
            if (!$progress) { [Threading.Thread]::Sleep(10) }
        }
        if ($process.ExitCode -ne 0) { throw 'core_check_failed' }
        if ($streams[1].text.Length -ne 0) { throw 'core_stderr_invalid' }
        $failureCode = 'core_response_invalid'
        $json = @($streams[0].text.ToString() -split '\r?\n' | Where-Object { $_ -match '^\{.*\}$' })
        if ($json.Count -ne 1) { throw 'core_response_invalid' }
        return ($json[0] | ConvertFrom-Json)
    } catch {
        # Only fixed codes leave this boundary, never raw stderr/arguments.
        if ($_.Exception.Message -cin $knownCodes) { throw $_.Exception.Message }
        throw $failureCode
    } finally {
        try {
            # Terminate only the helper created above, never an existing service
            # or unrelated process. Keep normal completion and timeout distinct.
            if ($started -and !$process.HasExited) {
                $process.Kill()
                if (!$process.WaitForExit(5000)) { throw 'core_cleanup_failed' }
            }
        } catch { throw 'core_cleanup_failed' }
        finally { $process.Dispose() }
    }
}

function Assert-OfficeUpdatePackage([string]$Installer, $Release) {
    # The embedded native verifier authenticated these exact release bytes first.
    # Policy is signed and explicit: there is no unsigned/hash-only fallback.
    if($Release.verification -cne 'office-ed25519-v1' -or $Release.PSObject.Properties['publisher_thumbprint']) {throw 'release_policy_invalid'}
    Assert-UpdatePath $Installer
    $file=Get-Item -LiteralPath $Installer
    if($file.Length -ne $Release.size_bytes -or (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Release.sha256) {throw 'installer_hash_mismatch'}
}

function Expand-OfficeUpdatePayload([string]$Installer, [string]$Payload, $Release) {
    Assert-OfficeUpdatePackage $Installer $Release
    if(Test-Path -LiteralPath $Payload){return}
    # No elevation, trust-store edits, antivirus exclusions or execution-policy change.
    try {$process=Start-Process -FilePath $Installer -ArgumentList @('--office-update-extract',('"'+$Payload+'"')) -WindowStyle Hidden -PassThru -Wait}
    catch {
        $cause=$_.Exception
        for($depth=0;$cause -and $depth -lt 8;$depth++) {
            if($cause -is [ComponentModel.Win32Exception] -and $cause.NativeErrorCode -in @(577,1260)){throw 'windows_policy_blocked'}
            $cause=$cause.InnerException
        }
        throw 'payload_start_failed'
    }
    $exit=[long]$process.ExitCode -band 4294967295L
    if($exit -in @(577,1260,3221226536L)){throw 'windows_policy_blocked'}
    if($exit -ne 0){throw 'payload_extraction_failed'}
}

function Test-UpdateTolerableCoreProcess([string]$CommandLine) {
    # Background helpers never block an update.
    if ($CommandLine -match '\s--(?:service|server|tray|office-update-probe)(?:\s|$)') { return $true }
    # The main window started without arguments only hides on close and keeps
    # running until logoff. While the protected IPC probe reports no session it
    # is replaced like the tray. Connection, CM and install windows still block.
    return $CommandLine -match '^\s*(?:"[^"]+"|[^\s"]+)\s*$'
}

function Get-UpdateReport {
    $health = Invoke-UpdateCore '--office-update-probe'
    # Fail closed on GUI/connection-manager processes or hidden process metadata.
    # The protected daemon IPC probe also counts incoming/authenticating sessions.
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='$([IO.Path]::GetFileName($script:CorePath))'")
    $idle = $health.idle -eq $true
    $reason=if($idle){'none'}else{'active_sessions'}
    foreach ($process in $processes) {
        if (!$process.ExecutablePath -or !$process.CommandLine) { $idle = $false; $reason='process_visibility_incomplete'; continue }
        if ($process.ExecutablePath -ieq $script:CorePath -and !(Test-UpdateTolerableCoreProcess $process.CommandLine)) { $idle = $false; $reason='rdcl_window_open' }
    }
    $reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
        $null -ne (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)
    if($reboot){$reason='pending_restart'}
    if($health.install_mode -ne 'exe'){$reason='unsupported_install_mode'}
    $service=Get-CimInstance Win32_Service -Filter "Name='$script:ServiceName'"
    $serviceRunning=$service -and $service.State -eq 'Running' -and $service.StartName -in @('LocalSystem','SYSTEM') -and $service.PathName -ieq ('"'+$script:CorePath+'" --service')
    if(!$serviceRunning){$reason='service_configuration_changed'}
    if($health.peer_id -cne $script:machine.peer_id){$reason='identity_changed'}
    return @{protocol=2;platform='windows-x64';install_mode=$health.install_mode;service_running=[bool]$serviceRunning;
        idle=$idle;pending_reboot=[bool]$reboot;version=$health.version;identity_preserved=($health.peer_id -ceq $script:machine.peer_id);inventory_verified=$false;result_code=$reason}
}

function Invoke-OfficeUpdate([string]$Endpoint, $Body) {
    $request = @{}
    if ($Body -is [Collections.IDictionary]) {foreach($key in $Body.Keys) {$request[$key]=$Body[$key]}}
    else {foreach($property in $Body.PSObject.Properties) {$request[$property.Name]=$property.Value}}
    $request.installation_id = $script:machine.installation_id
    $request.peer_id = $script:machine.peer_id
    $sequencePath=Join-Path $script:root 'request-sequence.json'
    $sequence=0L
    if(Test-Path -LiteralPath $sequencePath){$sequence=[long](Get-Content -Raw -LiteralPath $sequencePath|ConvertFrom-Json).value}
    if($sequence -ge 9007199254740990){throw 'update_sequence_exhausted'}
    $sequence++
    Write-UpdateState $sequencePath @{value=$sequence}
    $request.sequence=$sequence
    # Literal pinned HTTPS origin. No customer-supplied server/redirect/proxy URL.
    try {
        Invoke-RestMethod -Uri "https://api-office.exantas.eu/api/v1/rustdesk-devices/updates/$Endpoint" -Method Post -MaximumRedirection 0 -TimeoutSec 20 -ContentType 'application/json' -Headers @{Authorization="Bearer $script:token"} -Body ($request | ConvertTo-Json -Depth 30 -Compress)
    } catch {
        $resynchronized=$false
        try {
            if($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 409) {
                $reader=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
                try{$buffer=New-Object char[] 8192;$count=$reader.Read($buffer,0,$buffer.Length);$errorReply=(-join $buffer[0..($count-1)])|ConvertFrom-Json}finally{$reader.Dispose()}
                if($errorReply.status -eq 'update_stale_request' -and $errorReply.details.minimum_sequence -gt 0 -and $errorReply.details.minimum_sequence -le 9007199254740991) {
                    Write-UpdateState $sequencePath @{value=[Math]::Max($sequence,[long]$errorReply.details.minimum_sequence-1)}
                    $resynchronized=$true
                }
            }
        } catch { }
        if($resynchronized){throw 'update_sequence_resynchronized'}
        throw 'office_update_request_failed'
    }
}

function Receive-VerifiedInstaller($Release, [string]$Path) {
    Add-Type -AssemblyName System.Net.Http
    $handler=New-Object Net.Http.HttpClientHandler; $handler.AllowAutoRedirect=$false
    $client=New-Object Net.Http.HttpClient $handler
    $client.Timeout=[TimeSpan]::FromMinutes(5)
    $cancellation=New-Object Threading.CancellationTokenSource
    $cancellation.CancelAfter([TimeSpan]::FromMinutes(5))
    $response=$null; $inputStream=$null; $outputStream=$null
    try {
        $response=$client.GetAsync($Release.url,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cancellation.Token).GetAwaiter().GetResult()
        if ([int]$response.StatusCode -ne 200 -or ($response.Content.Headers.ContentLength -and $response.Content.Headers.ContentLength -ne $Release.size_bytes)) {throw 'download_http_error'}
        $inputStream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $outputStream=[IO.File]::Open($Path,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=New-Object byte[] 65536; $total=0L; $timer=[Diagnostics.Stopwatch]::StartNew()
        while (($count=$inputStream.ReadAsync($buffer,0,$buffer.Length,$cancellation.Token).GetAwaiter().GetResult()) -gt 0) {
            $total+=$count
            if ($total -gt $Release.size_bytes -or $timer.Elapsed.TotalSeconds -gt 300) {throw 'download_size_or_time_limit'}
            $outputStream.Write($buffer,0,$count)
        }
        if ($total -ne $Release.size_bytes) {throw 'download_incomplete'}
        $outputStream.Flush($true)
    } finally {
        if($outputStream){$outputStream.Dispose()}; if($inputStream){$inputStream.Dispose()}
        if($response){$response.Dispose()}; $client.Dispose(); $handler.Dispose(); $cancellation.Dispose()
    }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Release.sha256) {throw 'installer_hash_mismatch'}
}

function Send-UpdateAction([string]$Action, $Report, [string]$Code = '') {
    # Persist request identity BEFORE sending; a lost reply is reconciled with the
    # same action_id, never an independent installation command.
    if (!$script:journal.pending_action -or $script:journal.pending_action.action -ne $Action) {
        $script:journal.pending_action = @{action=$Action;action_id=[guid]::NewGuid().ToString();job_id=$script:journal.job.id;fence=$script:journal.job.fence;
            report=$Report;sha256=$script:journal.release.sha256;result_code=$Code}
        Write-UpdateState $script:journalPath $script:journal
    }
    $result = Invoke-OfficeUpdate 'action' $script:journal.pending_action
    if (!$result.job) { throw 'action_unconfirmed' }
    $script:journal.job = $result.job
    $script:journal.pending_action = $null
    Write-UpdateState $script:journalPath $script:journal
    $expected=@{download='downloading';ready='ready';permit='installing';verify='verifying';success='succeeded';rollback='rolled_back';defer='cancelled';fail='failed';uncertain='unknown'}
    if($result.job.state -ne $expected[$Action]){throw 'action_superseded'}
    return $result
}

function Stop-UpdateProcesses {
    Stop-Service -Name $script:ServiceName -ErrorAction Stop
    (Get-Service -Name $script:ServiceName).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30))
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='$([IO.Path]::GetFileName($script:CorePath))'")
    foreach ($process in $processes) {
        if (!$process.ExecutablePath) { throw 'process_visibility_incomplete' }
        if ($process.ExecutablePath -ieq $script:CorePath) {
            Stop-Process -Id $process.ProcessId -ErrorAction Stop
            Wait-Process -Id $process.ProcessId -Timeout 30 -ErrorAction SilentlyContinue
            if(Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue){throw 'process_did_not_stop'}
        }
    }
}

function Start-UpdateService {
    Start-Service -Name $script:ServiceName
    (Get-Service -Name $script:ServiceName).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
    for($probe=0;$probe -lt 15;$probe++) {
        try {Invoke-UpdateCore '--office-update-probe' | Out-Null; return} catch {Start-Sleep -Seconds 1}
    }
    throw 'service_probe_timeout'
}

function Get-RollbackFiles {
    return @($script:journal.old_files | Where-Object {$_.path -in @($script:journal.new_files | ForEach-Object path)})
}

function Restore-UpdateBackup {
    # Never touch user/profile/enrollment/config files. Only the exact reviewed
    # install-tree snapshot and this attempt's previously absent payload files.
    Assert-RuntimeInventory $script:journal.backup $script:journal.old_files -Exact
    if($script:journal.recovery_attempts -ge 3){throw 'recovery_attempt_budget_exhausted'}
    $script:journal.recovery_attempts++
    Write-UpdateState $script:journalPath $script:journal
    $oldRuntime=@(Get-RollbackFiles)
    if(!$oldRuntime.Count){throw 'rollback_inventory_missing'}
    foreach($file in $script:journal.new_files) {
        $target=Join-Path $script:installRoot $file.path
        if(Test-Path -LiteralPath $target) {
            Assert-UpdatePath $target
            $hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
            $old=@($oldRuntime | Where-Object path -eq $file.path)
            if($hash -cne $file.sha256 -and (!$old.Count -or $hash -cne $old[0].sha256)){throw 'rollback_unexpected_file'}
        }
    }
    $script:journal.phase='restoring';Write-UpdateState $script:journalPath $script:journal
    Stop-UpdateProcesses
    foreach ($file in $script:journal.new_files) {
        if ($file.path -notin @($script:journal.old_files | ForEach-Object path)) {
            $path = Join-Path $script:installRoot $file.path
            if (Test-Path -LiteralPath $path) {
                Assert-UpdatePath $path
                # Unknown/changed bytes are never removed as rollback housekeeping.
                if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256) { throw 'rollback_file_changed' }
                Remove-Item -LiteralPath $path
            }
        }
    }
    Copy-VerifiedRuntime $script:journal.backup $script:installRoot $oldRuntime
    $script:journal.phase='restored';Write-UpdateState $script:journalPath $script:journal
    Start-UpdateService
    $report = Get-UpdateReport
    if ($report.version -cne $script:journal.job.old_version -or !$report.identity_preserved) { throw 'rollback_postcheck_failed' }
    Invoke-UpdateCore '--office-update-register-version' | Out-Null
    $report.inventory_verified = $true
    $script:journal.phase = 'rolled_back'
    Write-UpdateState $script:journalPath $script:journal
    Send-UpdateAction 'rollback' $report 'restored_previous_runtime' | Out-Null
}

function Seal-UpdateAttempt($Journal) {
    $attempt=Join-Path $script:root $Journal.job.id
    if($Journal.job.id -notmatch '^[a-f0-9-]{36}$'){throw 'invalid_attempt_identity'}
    Assert-UpdatePath $attempt
    return @{job_id=$Journal.job.id;installation_id=$script:machine.installation_id;files=@(Get-RuntimeInventory $attempt);
      directories=@(Get-ChildItem -LiteralPath $attempt -Directory -Recurse -Force | ForEach-Object {$_.FullName.Substring($attempt.Length+1)})}
}

function Retire-PreviousUpdateAttempt {
    $path=Join-Path $script:root 'previous-attempt.json'
    if(!(Test-Path -LiteralPath $path)){return}
    $previous=Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    if($previous.job_id -notmatch '^[a-f0-9-]{36}$' -or $previous.job_id -eq $script:journal.job.id -or $previous.installation_id -cne $script:machine.installation_id){throw 'retention_owner_mismatch'}
    $attempt=Join-Path $script:root $previous.job_id
    Assert-PrivateUpdateDirectory $script:root
    Assert-RuntimeInventory $attempt $previous.files -Exact
    foreach($file in $previous.files) {
        $target=Join-Path $attempt $file.path
        Assert-UpdatePath $target
        if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256){throw 'retention_file_changed'}
        Remove-Item -LiteralPath $target
    }
    foreach($relative in @($previous.directories | Sort-Object Length -Descending)) {
        $directory=Join-Path $attempt $relative; Assert-UpdatePath $directory
        if(@(Get-ChildItem -LiteralPath $directory -Force).Count){throw 'retention_directory_not_empty'}
        [IO.Directory]::Delete($directory)
    }
    if(@(Get-ChildItem -LiteralPath $attempt -Force).Count){throw 'retention_directory_not_empty'}
    [IO.Directory]::Delete($attempt)
    Remove-Item -LiteralPath $path
}

function Complete-UpdateJob([string]$Phase) {
    $script:journal.phase=$Phase
    Write-UpdateState $script:journalPath $script:journal
    $script:barrier.Reset() | Out-Null
    if($Phase -in @('complete','rolled_back') -and $script:journal.tray_was_running) {
        try {Invoke-UpdateCore '--office-update-restore-tray' | Out-Null} catch {
            [IO.File]::WriteAllText((Join-Path $script:root 'tray-restore-pending.txt'),'Normal tray startup needs review; no elevated GUI launched.')
        }
    }
    # Cleanup failure is independent of verified installation success. Retain
    # unexpected files for review; never roll back or repeat the installation.
    try {Retire-PreviousUpdateAttempt} catch {
        [IO.File]::WriteAllText((Join-Path $script:root 'cleanup-pending.txt'),'Owned previous attempt retained for review.')
    }
    if($Phase -eq 'complete') {
        # The recovery task runs Windows PowerShell independently of installed
        # DLLs. Its verified bootstrap runtime is refreshed only after the ACK.
        try {Initialize-IndependentRecovery -Promote; $script:restartWorker=$true} catch {
            [IO.File]::WriteAllText((Join-Path $script:root 'recovery-host-pending.txt'),'Verified previous recovery host retained; promotion needs review.')
        }
    }
}

function Initialize-IndependentRecovery([switch]$Promote) {
    if(!$Promote -and $script:machine.host_path -and (Test-Path -LiteralPath $script:machine.host_path)) {
        $slot=Split-Path -Leaf (Split-Path -Parent $script:machine.host_path)
        if($slot -notin @('host-a','host-b')){throw 'invalid_recovery_slot'}
        $manifest=Get-Content -Raw -LiteralPath (Join-Path $script:root "$slot.json") | ConvertFrom-Json
        Assert-RuntimeInventory (Split-Path -Parent $script:machine.host_path) $manifest.files -Exact
    } else {
        $files=@(Get-RuntimeInventory $script:installRoot)
        $bytes=[long](($files | Measure-Object size_bytes -Sum).Sum)
        $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($script:root))
        if($bytes -gt 1073741824 -or $drive.AvailableFreeSpace -lt $bytes+268435456){throw 'recovery_host_space_insufficient'}
        $current=if($script:machine.host_path){Split-Path -Leaf (Split-Path -Parent $script:machine.host_path)}else{''}
        $slot=if($current -eq 'host-a'){'host-b'}else{'host-a'}
        $target=Join-Path $script:root $slot
        $slotManifest=Join-Path $script:root "$slot.json"
        if(Test-Path -LiteralPath $target) {
            # Exact owned inactive slot only, verified before each unlink.
            $owned=Get-Content -Raw -LiteralPath $slotManifest | ConvertFrom-Json
            if($owned.installation_id -cne $script:machine.installation_id -or $owned.slot -cne $slot){throw 'recovery_host_owner_mismatch'}
            Assert-RuntimeInventory $target $owned.files -Exact
            foreach($file in $owned.files){$p=Join-Path $target $file.path; Assert-UpdatePath $p; if((Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256){throw 'recovery_host_changed'};Remove-Item -LiteralPath $p}
            foreach($directory in @(Get-ChildItem -LiteralPath $target -Directory -Recurse -Force | Sort-Object {$_.FullName.Length} -Descending)) {
                Assert-UpdatePath $directory.FullName
                if(@(Get-ChildItem -LiteralPath $directory.FullName -Force).Count){throw 'recovery_host_not_empty'}
                [IO.Directory]::Delete($directory.FullName)
            }
        } else {New-Item -ItemType Directory -Path $target | Out-Null}
        Copy-VerifiedRuntime $script:installRoot $target $files
        Assert-RuntimeInventory $target $files -Exact
        $manifest=@{installation_id=$script:machine.installation_id;slot=$slot;files=$files}
        Write-UpdateState $slotManifest $manifest
        # Select the verified slot atomically; the previous slot stays recoverable.
        $script:machine.host_path=Join-Path $target ([IO.Path]::GetFileName($script:CorePath))
        Write-UpdateState (Join-Path $script:root 'machine.json') $script:machine
    }
    # An OS-owned startup task can recover a half-replaced installation even
    # when its normal service executable/DLLs cannot start. No UAC/policy change.
    $taskName='Exantas rd-cl update recovery'
    $description='ExantasRdclUpdates/'+$script:machine.installation_id
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments='-NoProfile -NonInteractive -Command "& ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $env:ProgramData ''ExantasRdclUpdates\worker.ps1''))))"'
    $existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if($existing) {
        if($existing.Description -cne $description -or $existing.Principal.UserId -notin @('SYSTEM','S-1-5-18') -or @($existing.Actions).Count -ne 1 -or
          $existing.Actions[0].Execute -ine $ps -or $existing.Actions[0].Arguments -cne $arguments){throw 'recovery_task_owner_mismatch'}
    } else {
        $action=New-ScheduledTaskAction -Execute $ps -Argument $arguments
        $trigger=New-ScheduledTaskTrigger -AtStartup
        $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval ([TimeSpan]::FromMinutes(1))
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $description | Out-Null
    }
}

function Open-UpdateBarrier([string]$EventName='Global\ExantasRdclUpdateBarrier',[string]$OwnerSid='S-1-5-18') {
    if(!$LibraryOnly -and ($EventName -cne 'Global\ExantasRdclUpdateBarrier' -or $OwnerSid -cne 'S-1-5-18')){throw 'invalid_barrier_scope'}
    $security=New-Object Security.AccessControl.EventWaitHandleSecurity
    $system=New-Object Security.Principal.SecurityIdentifier $OwnerSid
    $security.SetOwner($system);$security.SetAccessRuleProtection($true,$false)
    foreach($sid in @('S-1-5-18','S-1-5-32-544',$OwnerSid)) {
        $identity=New-Object Security.Principal.SecurityIdentifier $sid
        $security.AddAccessRule((New-Object Security.AccessControl.EventWaitHandleAccessRule($identity,[Security.AccessControl.EventWaitHandleRights]::FullControl,[Security.AccessControl.AccessControlType]::Allow)))
    }
    $world=New-Object Security.Principal.SecurityIdentifier 'S-1-1-0'
    $security.AddAccessRule((New-Object Security.AccessControl.EventWaitHandleAccessRule($world,[Security.AccessControl.EventWaitHandleRights]::Synchronize,[Security.AccessControl.AccessControlType]::Allow)))
    $pending=$script:journal -and $script:journal.phase -notin @('complete','rolled_back','cancelled','failed')
    $created=$false
    $event=New-Object Threading.EventWaitHandle([bool]$pending,[Threading.EventResetMode]::ManualReset,$EventName,[ref]$created,$security)
    $acl=$event.GetAccessControl()
    if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $OwnerSid){$event.Dispose();throw 'barrier_owner_invalid'}
    foreach($rule in $acl.Access){if($rule.AccessControlType -eq 'Allow' -and ($rule.EventWaitHandleRights -band [Security.AccessControl.EventWaitHandleRights]::Modify) -and $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544',$OwnerSid)){$event.Dispose();throw 'barrier_acl_invalid'}}
    return $event
}

function Invoke-UpdateCycle {
    if($script:journal -and $script:journal.phase -in @('replacing','replaced','restoring')) {
        # Recover locally before executing any potentially half-replaced core.
        Restore-UpdateBackup
        Complete-UpdateJob 'rolled_back'
    }
    $pending=$null
    if($script:journal -and ($script:journal.pending_action -or $script:journal.phase -notin @('complete','rolled_back','cancelled','failed'))) {$pending=$script:journal.job.id}
    $poll = Invoke-OfficeUpdate 'poll' @{report=(Get-UpdateReport);pending_job_id=$pending}
    if (!$script:reportedAcceptedPoll) {
        $script:reportedAcceptedPoll = $true
        try { Write-UpdateDiagnostic 'office_poll_accepted' }
        catch { Write-Verbose 'Could not log the first accepted Office update poll.' }
    }
    if (!$poll.PSObject.Properties['job'] -or !$poll.job) {
        if (!$pending) {$script:barrier.Reset() | Out-Null}
        return
    }
    $job = $poll.job
    if($job.id -notmatch '^[a-f0-9-]{36}$' -or $job.fence -notmatch '^[a-f0-9-]{36}$') {throw 'invalid_job_identity'}
    if($job.state -in @('succeeded','rolled_back','cancelled','failed')) {
        if (!$script:journal -or $script:journal.job.id -ne $job.id) {throw 'unexpected_terminal_job'}
        if($job.state -eq 'succeeded') {Assert-RuntimeInventory $script:installRoot $script:journal.new_files; $script:journal.phase='complete'}
        elseif($job.state -eq 'rolled_back') {Assert-RuntimeInventory $script:installRoot @(Get-RollbackFiles); $script:journal.phase='rolled_back'}
        elseif($script:journal.phase -in @('offered','backed_up','failed')) {$script:journal.phase=if($job.state -eq 'failed'){'failed'}else{'cancelled'}}
        else {throw 'terminal_result_needs_review'}
        $script:journal.pending_action=$null
        Complete-UpdateJob $script:journal.phase
        return
    }
    $attempt = Join-Path $script:root $job.id
    if (!(Test-Path -LiteralPath $attempt)) { New-Item -ItemType Directory -Path $attempt | Out-Null }
    Assert-PrivateUpdateDirectory $script:root
    if ($script:journal -and $script:journal.job.id -ne $job.id -and $script:journal.phase -notin @('complete','rolled_back','cancelled','failed')) { throw 'unreconciled_previous_job' }
    if (!$script:journal -or $script:journal.job.id -ne $job.id) {
        if($script:journal) {
            # Preserve the last verified attempt while the next one is active.
            Retire-PreviousUpdateAttempt
            Write-UpdateState (Join-Path $script:root 'previous-attempt.json') (Seal-UpdateAttempt $script:journal)
        }
        $script:journal = @{job=$job;phase='offered';pending_action=$null;release=$null;backup=(Join-Path $attempt 'previous');old_files=@();new_files=@();tray_was_running=$false;recovery_attempts=0}
        Write-UpdateState $script:journalPath $script:journal
    }
    $script:journal.job=$job
    if($script:journal.pending_action -and $job.state -in @('offered','downloading','ready')) {
        $pendingAction=$script:journal.pending_action
        $lastId=if($job.PSObject.Properties['last_action_id']){$job.last_action_id}else{$null}
        if($pendingAction.action -ne 'permit' -and $lastId -eq $pendingAction.action_id) {
            $script:journal.pending_action=$null
            Write-UpdateState $script:journalPath $script:journal
        } else {
            # Cancel an unconfirmed pre-install attempt under the same DB lock.
            # Any late original request is then rejected by its terminal fence.
            Send-UpdateAction 'defer' (Get-UpdateReport) 'unconfirmed_preinstall_action' | Out-Null
            Complete-UpdateJob 'cancelled'
            return
        }
    }
    if ($job.state -in @('installing','verifying','unknown')) {
        $script:barrier.Set() | Out-Null
        # Recovery never starts a fresh replacement. Inspect the retained bytes.
        if ($script:journal.phase -in @('replacing','replaced','verifying')) {
            try {
                Assert-RuntimeInventory $script:installRoot $script:journal.new_files
                if((Get-Service -Name $script:ServiceName).Status -ne 'Running'){Start-UpdateService}
                $report = Get-UpdateReport
                if ($report.version -cne $script:journal.release.version -or !$report.identity_preserved) { throw 'update_postcheck_failed' }
                $report.inventory_verified = $true
            } catch {
                Restore-UpdateBackup
                Complete-UpdateJob 'rolled_back'
                return
            }
            # A lost result ACK never triggers an independent rollback.
            $script:journal.phase='verifying'; Write-UpdateState $script:journalPath $script:journal
            if ($job.state -eq 'installing') {Send-UpdateAction 'verify' $report | Out-Null}
            Send-UpdateAction 'success' $report | Out-Null
            Complete-UpdateJob 'complete'
        } elseif ($script:journal.phase -eq 'backed_up') {
            # Permit reply was lost BEFORE any replacement. Prove the old runtime
            # and acknowledge a safe rollback without starting an installation.
            Assert-RuntimeInventory $script:installRoot @(Get-RollbackFiles)
            $report=Get-UpdateReport; $report.inventory_verified=$true
            Send-UpdateAction 'rollback' $report 'permit_reply_lost_no_replacement' | Out-Null
            Complete-UpdateJob 'rolled_back'
        } elseif ($script:journal.phase -in @('rolled_back','restored')) {
            if((Get-Service -Name $script:ServiceName).Status -ne 'Running'){Start-UpdateService}
            $report=Get-UpdateReport; Assert-RuntimeInventory $script:installRoot @(Get-RollbackFiles)
            $report.inventory_verified=$true; Send-UpdateAction 'rollback' $report | Out-Null; Complete-UpdateJob 'rolled_back'
        } else { throw 'install_result_unknown' }
        return
    }
    $manifestPath = Join-Path $attempt 'envelope.json'
    Write-UpdateState $manifestPath $poll.envelope
    $releaseText = & $script:machine.host_path '--office-update-verify' $manifestPath
    if($LASTEXITCODE -ne 0){throw 'release_signature_invalid'}
    $releaseLines=@($releaseText | Where-Object {$_ -match '^\{.*\}$'})
    if($releaseLines.Count -ne 1){throw 'release_response_invalid'}
    $release=$releaseLines[0] | ConvertFrom-Json
    $script:journal.release=$release
    if ($poll.PSObject.Properties['paused'] -and $poll.paused -eq $true) { Send-UpdateAction 'defer' (Get-UpdateReport) 'rollout_paused' | Out-Null; return }
    if ($job.state -eq 'offered') { Send-UpdateAction 'download' (Get-UpdateReport) | Out-Null }
    $installer = Join-Path $attempt 'installer.exe'
    if (!(Test-Path -LiteralPath $installer)) {
        $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($script:root))
        $oldSize=[long]((Get-ChildItem -LiteralPath $script:installRoot -File -Recurse -Force | Measure-Object Length -Sum).Sum)
        if($oldSize -gt 1073741824){Send-UpdateAction 'defer' (Get-UpdateReport) 'install_tree_too_large' | Out-Null; return}
        $required = [long]$release.size_bytes + [long](($release.files | Measure-Object size_bytes -Sum).Sum) * 2 + $oldSize + 268435456
        if ($drive.AvailableFreeSpace -lt $required) { Send-UpdateAction 'defer' (Get-UpdateReport) 'insufficient_space' | Out-Null; return }
        # No partial file is ever accepted as a complete download.
        $part="$installer.part"
        Receive-VerifiedInstaller $release $part
        if ((Get-Item $part).Length -ne $release.size_bytes -or (Get-FileHash $part -Algorithm SHA256).Hash.ToLowerInvariant() -cne $release.sha256) { throw 'installer_hash_mismatch' }
        Move-Item -LiteralPath $part -Destination $installer
    }
    $payload=Join-Path $attempt 'payload'
    Expand-OfficeUpdatePayload $installer $payload $release
    Assert-RuntimeInventory $payload $release.files -Exact
    $runtime=Join-Path $attempt 'runtime'
    if(!(Test-Path -LiteralPath $runtime)) {New-Item -ItemType Directory -Path $runtime | Out-Null}
    $mapped=@()
    foreach($file in $release.files) {
        $relative=if($file.path -ieq $release.runtime_exe){[IO.Path]::GetFileName($script:CorePath)}else{$file.path}
        $to=Join-Path $runtime $relative; $parent=Split-Path -Parent $to
        if(!(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force | Out-Null}
        Assert-UpdatePath $parent
        Copy-UpdateFile (Join-Path $payload $file.path) $to
        $mapped+=@{path=$relative;sha256=$file.sha256;size_bytes=$file.size_bytes}
    }
    Assert-RuntimeInventory $runtime $mapped -Exact
    $script:journal.new_files=$mapped
    if ($script:journal.job.state -eq 'downloading') { Send-UpdateAction 'ready' (Get-UpdateReport) | Out-Null }
    if(Test-Path -LiteralPath (Join-Path $script:root 'stop-requested')){Send-UpdateAction 'defer' @{} 'local_uninstall_requested'|Out-Null;Complete-UpdateJob 'cancelled';return}
    # Barrier blocks new incoming/outgoing sessions before the second idle check.
    $script:barrier.Set() | Out-Null
    $script:journal.tray_was_running=@(Get-CimInstance Win32_Process -Filter "Name='$([IO.Path]::GetFileName($script:CorePath))'" | Where-Object {$_.ExecutablePath -ieq $script:CorePath -and $_.CommandLine -match '\s--tray(?:\s|$)'}).Count -gt 0
    $report=Get-UpdateReport
    if (!$report.idle -or $report.pending_reboot) { $script:barrier.Reset() | Out-Null; Send-UpdateAction 'defer' $report 'device_busy' | Out-Null; return }
    if (!(Test-Path -LiteralPath $script:journal.backup)) { New-Item -ItemType Directory -Path $script:journal.backup | Out-Null }
    $script:journal.old_files=@(Get-RuntimeInventory $script:installRoot)
    Copy-VerifiedRuntime $script:installRoot $script:journal.backup $script:journal.old_files
    Assert-RuntimeInventory $script:journal.backup $script:journal.old_files -Exact
    $script:journal.phase='backed_up'; Write-UpdateState $script:journalPath $script:journal
    if(Test-Path -LiteralPath (Join-Path $script:root 'stop-requested')){Send-UpdateAction 'defer' @{} 'local_uninstall_requested'|Out-Null;Complete-UpdateJob 'cancelled';return}
    # A GUI/window may have appeared during the backup. New UI/session admission
    # is fenced in the core, and this final observation must still be idle.
    $report=Get-UpdateReport
    if(!$report.idle -or $report.pending_reboot){$script:barrier.Reset()|Out-Null;Send-UpdateAction 'defer' $report 'device_became_busy'|Out-Null;return}
    $permit=Send-UpdateAction 'permit' $report
    if (!$permit.PSObject.Properties['permit_expires_at'] -or !$permit.permit_expires_at -or [DateTimeOffset]::Parse($permit.permit_expires_at) -le [DateTimeOffset]::UtcNow) { throw 'permit_expired' }
    if (!$permit.PSObject.Properties['server_time'] -or ([DateTimeOffset]::UtcNow-[DateTimeOffset]::Parse($permit.server_time)).Duration().TotalSeconds -gt 120) {throw 'permit_clock_mismatch'}
    $script:journal.phase='replacing'; Write-UpdateState $script:journalPath $script:journal
    Stop-UpdateProcesses
    Copy-VerifiedRuntime $runtime $script:installRoot $script:journal.new_files
    $script:journal.phase='replaced'; Write-UpdateState $script:journalPath $script:journal
    Start-UpdateService
    $report=Get-UpdateReport
    if ($report.version -cne $release.version -or !$report.identity_preserved) { throw 'update_postcheck_failed' }
    Invoke-UpdateCore '--office-update-register-version' | Out-Null
    $report.inventory_verified=$true
    $script:journal.phase='verifying'; Write-UpdateState $script:journalPath $script:journal
    Send-UpdateAction 'verify' $report | Out-Null
    Send-UpdateAction 'success' $report | Out-Null
    Complete-UpdateJob 'complete'
}

function Handle-UpdateCycleFailure([string]$Code) {
    if(!$script:journal){$script:barrier.Reset()|Out-Null;return}
    if($script:journal.phase -in @('replacing','replaced','restoring')) {
        try {Restore-UpdateBackup;Complete-UpdateJob 'rolled_back'} catch {
            try{Send-UpdateAction 'uncertain' @{} 'recovery_needs_review'|Out-Null}catch{}
        }
        return
    }
    if($script:journal.phase -eq 'verifying') {
        # A failed/lost ACK never rolls back a verified replacement.
        try{Send-UpdateAction 'uncertain' @{} 'verification_reply_unknown'|Out-Null}catch{}
        return
    }
    if($script:journal.phase -eq 'restored') {
        try{Send-UpdateAction 'uncertain' @{} 'restored_runtime_needs_identity_check'|Out-Null}catch{}
        return
    }
    $critical=@('release_signature_invalid','release_response_invalid','installer_hash_mismatch','release_policy_invalid','windows_policy_blocked','payload_start_failed',
      'payload_extraction_failed','runtime_hash_mismatch','extra_runtime_files','unsafe_runtime_inventory','unsafe_runtime_path','install_directory_not_protected')
    if($script:journal.phase -in @('offered','backed_up') -and $Code -in $critical) {
        try{Send-UpdateAction 'fail' @{} $Code|Out-Null;Complete-UpdateJob 'failed'}catch{}
    }
    if(!$script:journal.pending_action -or $script:journal.pending_action.action -ne 'permit'){$script:barrier.Reset()|Out-Null}
}

if (!$LibraryOnly) {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') { throw 'system_service_required' }
    $script:root=Join-Path $env:ProgramData 'ExantasRdclUpdates'
    Assert-PrivateUpdateDirectory $script:root
    try {
    if(Test-Path -LiteralPath (Join-Path $script:root 'stop-requested')){exit 0}
    $script:machine=Get-Content -Raw -LiteralPath (Join-Path $script:root 'machine.json') | ConvertFrom-Json
    if (!$script:machine.registered) { exit 0 }
    $script:CorePath=$script:machine.install_exe; $script:ServiceName=$script:machine.service_name
    if(!$script:CorePath -or !$script:ServiceName){throw 'invalid_machine_configuration'}
    $script:installRoot=Split-Path -Parent $script:CorePath
    Assert-ProtectedInstallation $script:installRoot
    if(Test-Path -LiteralPath $script:CorePath){Assert-ProtectedInstallation $script:CorePath}
    Add-Type -AssemblyName System.Security
    $script:token=[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($script:machine.encrypted_token),$null,[Security.Cryptography.DataProtectionScope]::LocalMachine))
    $script:journalPath=Join-Path $script:root 'journal.json'
    $script:journal=$null
    if (Test-Path -LiteralPath $script:journalPath) { $script:journal=Get-Content -Raw -LiteralPath $script:journalPath | ConvertFrom-Json }
    $script:barrier=Open-UpdateBarrier
    $lock=[IO.File]::Open((Join-Path $script:root 'worker.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $script:restartWorker=$false
        # An existing verified host must remain usable during local recovery.
        # Do not copy a partially replaced install tree over that trusted host.
        if(!$script:journal -or $script:journal.phase -in @('complete','rolled_back','cancelled','failed')) {
            try {Initialize-IndependentRecovery} catch {
                try {Write-UpdateDiagnostic $_.Exception.Message} catch {}
                try {Invoke-OfficeUpdate 'poll' @{report=@{protocol=2;platform='windows-x64';version='0.0.0';install_mode='unknown';service_running=$false;idle=$false;pending_reboot=$true;result_code='recovery_setup_failed'}} | Out-Null} catch {}
                throw 'recovery_setup_failed'
            }
        }
        # The child outlives service replacement; another worker cannot overlap.
        while (!$script:restartWorker -and !(Test-Path -LiteralPath (Join-Path $script:root 'stop-requested'))) {
            try { Invoke-UpdateCycle } catch {
                # Sanitized, bounded diagnostics. Never log exceptions/headers/tokens.
                $code=if ($_.Exception.Message -match '^[a-z_]{1,64}$') {$_.Exception.Message} else {'update_cycle_failed'}
                $log=Join-Path $script:root 'update.jsonl'
                if ((Test-Path $log) -and (Get-Item $log).Length -gt 1048576) { Move-Item $log "$log.previous" -Force }
                [IO.File]::AppendAllText($log,(@{at=[DateTime]::UtcNow.ToString('o');code=$code;job_id=$(if($script:journal){$script:journal.job.id}else{$null})}|ConvertTo-Json -Compress)+[Environment]::NewLine)
                Handle-UpdateCycleFailure $code
            }
            for($wait=0;$wait -lt 60 -and !$script:restartWorker -and !(Test-Path -LiteralPath (Join-Path $script:root 'stop-requested'));$wait++){Start-Sleep -Seconds 1}
        }
    } finally { $lock.Dispose(); $script:barrier.Dispose(); $script:token=$null }
    } catch {
        try {Write-UpdateDiagnostic $_.Exception.Message} catch {}
        throw
    }
}
