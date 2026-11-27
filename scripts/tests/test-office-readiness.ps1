param([string]$Source)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$tokens=$null;$errors=$null
[Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ($errors|Out-String)}
. $Source
$actualInstallGuard=${function:Assert-OfficeInstalledPath}
$script:count=0
function Assert($condition,[string]$message){if(!$condition){throw $message};$script:count++}
# Inject synthetic providers; no real registry/service/network APIs are used.
$script:markers=@{}
$script:rename=$null
function Test-Path {param($LiteralPath,$ErrorAction)
    if($LiteralPath -like '*RebootPending'){return $script:markers.ContainsKey('cbs')}
    if($LiteralPath -like '*RebootRequired'){return $script:markers.ContainsKey('wu')}
    throw 'unexpected_path'
}
function Get-ItemProperty {param($LiteralPath,$ErrorAction)
    if($LiteralPath -notlike '*Session Manager'){throw 'unexpected_registry'}
    if($null -eq $script:rename){return [pscustomobject]@{Other='synthetic'}}
    return [pscustomobject]@{PendingFileRenameOperations=$script:rename}
}
$aclRoot=Join-Path ([IO.Path]::GetTempPath()) ('rdcl-readiness-acl-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $aclRoot
$aclFile=Join-Path $aclRoot 'synthetic.exe'
$null=New-Item -ItemType File -Path $aclFile
function Get-Acl {param($LiteralPath) return [pscustomobject]@{Access=$script:fixtureRules}}
try {
    foreach($case in @(
        @{sid='S-1-5-18';rights=0x1F01FF;allow=$true},
        @{sid='S-1-5-32-544';rights=0x1F01FF;allow=$true},
        @{sid='S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464';rights=0x1F01FF;allow=$true},
        @{sid='S-1-1-0';rights=0x200A9;allow=$true},
        @{sid='S-1-1-0';rights=0x1301BF;allow=$false},
        @{sid='S-1-5-32-545';rights=0x116;allow=$false}
    )) {
        $reference=[pscustomobject]@{Sid=$case.sid}
        $reference|Add-Member ScriptMethod Translate {param($Type) return [pscustomobject]@{Value=$this.Sid}}
        $script:fixtureRules=@([pscustomobject]@{IdentityReference=$reference;AccessControlType='Allow';FileSystemRights=$case.rights;PropagationFlags=0})
        $accepted=$true
        try{& $actualInstallGuard $aclFile}catch{$accepted=$false}
        Assert ($accepted -eq $case.allow) ('shared worker ACL decision '+$case.sid+'/'+$case.rights)
    }
} finally {
    Remove-Item -LiteralPath $aclFile -Force
    Remove-Item -LiteralPath $aclRoot
}
$config=[pscustomobject]@{expected_exe='C:\Program Files\Exantas Support\Exantas Support.exe';target_dir=[IO.Path]::GetTempPath();installed=$true;msi=$false}
$script:service=[pscustomobject]@{Name='Exantas Support';PathName='"C:\Program Files\Exantas Support\Exantas Support.exe" --service';StartName='LocalSystem';State='Running';StartMode='Auto'}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction)
    if($ClassName -ne 'Win32_Service' -or $Filter -ne "Name='Exantas Support'"){throw 'unexpected_service'}
    return $script:service
}
function Start-Service {throw 'read_only_test_wrote_service'}
function Set-Service {throw 'read_only_test_wrote_service'}
function Remove-ItemProperty {throw 'read_only_test_wrote_registry'}
function Set-ItemProperty {throw 'read_only_test_wrote_registry'}
function Assert-OfficeInstalledPath($Path) {}
function Assert-OfficeProtectedServiceFile($Executable) {if($Executable -cne $config.expected_exe){throw 'unexpected_file'}}

Assert (@(Get-OfficeRebootReasons).Count -eq 0) 'clean restart'
$script:markers.cbs=$true
Assert (@(Get-OfficeRebootReasons) -contains 'windows_servicing_restart') 'CBS cause'
$script:markers.Clear();$script:markers.wu=$true
Assert (@(Get-OfficeRebootReasons) -contains 'windows_update_restart') 'WU cause'
$script:markers.Clear();$script:rename=[string[]]@('')
Assert (@(Get-OfficeRebootReasons) -contains 'pending_file_operations') 'empty value must match installed worker presence check'
$script:rename=@('*1\??\C:\Windows\System32\gamingservicesproxy_17.dll.0','')
Assert (@(Get-OfficeRebootReasons) -contains 'pending_file_operations') 'Maria regression'
$report=Get-OfficeInstallReadiness $config
Assert ($report.schema -eq 1) 'report schema'
Assert (@($report.checks|Where-Object code -eq 'pending_file_operations')[0].status -eq 'blocked') 'pending files block'
Assert (@($report.checks|Where-Object code -eq 'service_running')[0].status -eq 'ok') 'service running'
Assert ($report.repair_fingerprint -cmatch '^[a-f0-9]{64}$') 'snapshot fingerprint'
Assert (($report|ConvertTo-Json -Depth 8) -notmatch 'gamingservicesproxy|encrypted_token|token_hash') 'no private details in diagnostic report'
$before=$report.repair_fingerprint
$script:service.State='Stopped'
$report=Get-OfficeInstallReadiness $config
Assert ($report.repair_fingerprint -cne $before) 'changed service invalidates confirmation'
Assert (@($report.checks|Where-Object code -eq 'service_stopped')[0].action -eq 'start_service') 'fixed start action'
$script:service.StartMode='Manual'
$report=Get-OfficeInstallReadiness $config
Assert (@($report.checks|Where-Object code -eq 'service_not_automatic')[0].action -eq 'automatic_service') 'fixed automatic action'
$script:service.PathName='"C:\Users\public\foreign.exe" --service'
$report=Get-OfficeInstallReadiness $config
Assert (@($report.checks|Where-Object code -eq 'service_configuration_changed')[0].status -eq 'blocked') 'foreign executable blocked'
Assert ($null -eq $report.repair_fingerprint) 'foreign executable has no repair plan'
$script:service=$null
$report=Get-OfficeInstallReadiness $config
Assert (@($report.checks|Where-Object code -eq 'service_missing')[0].status -eq 'blocked') 'missing service'
$config.installed=$false
$report=Get-OfficeInstallReadiness $config
Assert (@($report.checks|Where-Object code -eq 'service_after_install')[0].status -eq 'pending') 'fresh install is not a failed service'
$config.msi=$true
$report=Get-OfficeInstallReadiness $config
Assert (@($report.checks|Where-Object code -eq 'exe_installation')[0].status -eq 'unsupported') 'MSI ownership preserved'
foreach($action in @('delete_registry','reboot','stop_service','powershell','start_service;evil')) {
    $rejected=$false
    try{Repair-OfficeInstallReadiness $config $action ('a'*64)|Out-Null}catch{$rejected=$_.Exception.Message -eq 'invalid_repair'}
    Assert $rejected ('reject arbitrary action '+$action)
}
$rejected=$false
try{Repair-OfficeInstallReadiness $config 'start_service' "'malformed"|Out-Null}catch{$rejected=$_.Exception.Message -eq 'invalid_repair'}
Assert $rejected 'reject malformed fingerprint before privilege or writes'
$config.installed=$true;$config.msi=$false
$script:service=[pscustomobject]@{Name='Exantas Support';PathName='"C:\Program Files\Exantas Support\Exantas Support.exe" --service';StartName='LocalSystem';State='Stopped';StartMode='Manual'}
$script:admin=$false;$script:protected=$true;$script:starts=0;$script:changes=0
function Test-OfficeRepairAdministrator {return $script:admin}
function Assert-OfficeProtectedServiceFile($Executable) {if(!$script:protected -or $Executable -cne $config.expected_exe){throw 'untrusted_install_write_access'}}
function Start-Service {param($Name,$ErrorAction)
    if($Name -cne 'Exantas Support'){throw 'foreign_service'}
    $script:starts++;$script:service.State='Running'
}
function Set-Service {param($Name,$StartupType,$ErrorAction)
    if($Name -cne 'Exantas Support' -or $StartupType -cne 'Automatic'){throw 'foreign_service_change'}
    $script:changes++;$script:service.StartMode='Auto'
}
function Get-Service {param($Name)
    $object=[pscustomobject]@{Name=$Name}
    $object|Add-Member ScriptMethod WaitForStatus {param($Status,$Timeout) if($script:service.State -cne $Status){throw 'service_unconfirmed'}}
    return $object
}
function Expect-Rejection($Action,$Fingerprint,$Message) {
    $failed=$false
    try{Repair-OfficeInstallReadiness $config $Action $Fingerprint|Out-Null}catch{$failed=$_.Exception.Message -eq $Message}
    Assert $failed $Message
}
$fingerprint=(Get-OfficeServiceSnapshot $config).fingerprint
Expect-Rejection 'start_service' $fingerprint 'administrator_required'
$script:admin=$true;$script:protected=$false
Expect-Rejection 'start_service' $fingerprint 'untrusted_install_write_access'
$script:protected=$true
Expect-Rejection 'start_service' ('0'*64) 'repair_state_changed'
Assert ($script:starts -eq 0 -and $script:changes -eq 0) 'no mutation without valid privilege/path/snapshot'
$result=Repair-OfficeInstallReadiness $config 'start_service' $fingerprint
Assert ($result.applied -and $script:starts -eq 1 -and $script:service.State -eq 'Running') 'confirmed start and readback'
Expect-Rejection 'start_service' $fingerprint 'repair_state_changed'
Assert ($script:starts -eq 1) 'replayed confirmation cannot start again'
$fingerprint=(Get-OfficeServiceSnapshot $config).fingerprint
$result=Repair-OfficeInstallReadiness $config 'automatic_service' $fingerprint
Assert ($result.applied -and $script:changes -eq 1 -and $script:service.StartMode -eq 'Auto') 'confirmed automatic mode and readback'
$config.msi=$true
Expect-Rejection 'automatic_service' $fingerprint 'installed_exe_required'
$config.msi=$null
Expect-Rejection 'automatic_service' $fingerprint 'installed_exe_required'
$report=Get-OfficeInstallReadiness $config
Assert (@($report.checks|Where-Object code -eq 'installation_mode_unconfirmed')[0].status -eq 'unknown') 'unknown mode is not MSI or safe EXE'
Assert ($null -eq $report.repair_fingerprint) 'unknown mode cannot offer repairs'
. (Join-Path (Split-Path -Parent $Source) 'office-update.ps1') -LibraryOnly
Assert (Test-UpdateTolerableCoreProcess '"C:\Program Files\Exantas Support\Exantas Support.exe" --office-install-check') 'completion main window must not permanently block updates'
Assert (!(Test-UpdateTolerableCoreProcess '"C:\Program Files\Exantas Support\Exantas Support.exe" --office-install-check --connect 123456789')) 'completion flag cannot exempt a connection'
Assert (!(Test-UpdateTolerableCoreProcess '"C:\Program Files\Exantas Support\Exantas Support.exe" --office-install-repair start_service')) 'repair process remains blocking'
Write-Output "PASS: $script:count readiness assertions; synthetic providers; no registry/service/network mutations"
