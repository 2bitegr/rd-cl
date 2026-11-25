param([string]$Source, [string]$Output)
$ErrorActionPreference='Stop'
$tokens=$null;$parseErrors=$null
[Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$parseErrors) | Out-Null
if($parseErrors.Count){throw ($parseErrors | Out-String)}
. $Source -LibraryOnly
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('rdcl-update-fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$passed=New-Object Collections.Generic.List[string]
function Assert($Value,[string]$Message){if(!$Value){throw $Message}}
function Check([string]$Name,[scriptblock]$Body){& $Body;$passed.Add($Name)}
function Reject([scriptblock]$Body){$failed=$false;try{& $Body}catch{$failed=$true};Assert $failed 'Expected rejection'}
try {
  Check 'Atomic journal replacement preserves readable current state' {
    $path=Join-Path $scratch 'state.json';Write-UpdateState $path @{phase='offered'};Write-UpdateState $path @{phase='replacing'}
    Assert ((Get-Content -Raw $path | ConvertFrom-Json).phase -eq 'replacing') 'Journal replacement failed'
  }
  Check 'A user-owned folder cannot become the trusted machine update root' {Reject {Assert-PrivateUpdateDirectory $scratch}}
  foreach($bad in @('../x','C:/x','data\x','CON.txt','nul','a//b','x.','x:stream')) {
    $invalidPath=$bad
    Check "Reject unsafe path $invalidPath" {Assert (!(Test-SafeRuntimePath $invalidPath)) 'Unsafe path accepted'}
  }
  $old=Join-Path $scratch 'old';$new=Join-Path $scratch 'new';$installed=Join-Path $scratch 'installed';$backup=Join-Path $scratch 'backup'
  foreach($dir in @($old,$new,$installed,$backup)){New-Item -ItemType Directory -Path $dir | Out-Null}
  foreach($dir in @($old,$new)){[IO.File]::WriteAllText((Join-Path $dir 'rustdesk.exe'),$(if($dir -eq $old){'old-executable'}else{'new-executable'}));[IO.File]::WriteAllText((Join-Path $dir 'librustdesk.dll'),$(if($dir -eq $old){'old-core'}else{'new-core'}))}
  $oldFiles=@(Get-RuntimeInventory $old);$newFiles=@(Get-RuntimeInventory $new)
  Check 'Verified copy and immutable backup retain exact previous bytes' {
    Copy-VerifiedRuntime $old $installed $oldFiles;Copy-VerifiedRuntime $installed $backup $oldFiles
    Assert-RuntimeInventory $backup $oldFiles -Exact
    Copy-VerifiedRuntime $new $installed $newFiles;Assert-RuntimeInventory $installed $newFiles -Exact
  }
  Check 'Corrupt payload is rejected before replacing any installed bytes' {
    [IO.File]::WriteAllText((Join-Path $new 'librustdesk.dll'),'corrupt')
    Reject {Copy-VerifiedRuntime $new $installed $newFiles}
    Assert-RuntimeInventory $installed $newFiles -Exact
  }
  Check 'Extra payload files and duplicate Windows names are rejected' {
    [IO.File]::WriteAllText((Join-Path $old 'extra.dll'),'unexpected')
    Reject {Assert-RuntimeInventory $old $oldFiles -Exact}
    Reject {Assert-RuntimeInventory $backup @($oldFiles[0],$oldFiles[0])}
  }
  Check 'Locked destination fails without corrupting retained backup' {
    $locked=[IO.File]::Open((Join-Path $installed 'librustdesk.dll'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{Reject {Copy-VerifiedRuntime $backup $installed $oldFiles}}finally{$locked.Dispose()}
    Assert-RuntimeInventory $backup $oldFiles -Exact
  }
  Check 'Partial replacement restores old bytes and preserves unrelated local data' {
    [IO.File]::WriteAllText((Join-Path $installed 'local-settings.txt'),'preserve-customer-data')
    [IO.File]::WriteAllText((Join-Path $installed 'rustdesk.exe'),'partial-update')
    Copy-VerifiedRuntime $backup $installed $oldFiles
    Assert-RuntimeInventory $installed $oldFiles
    Assert ([IO.File]::ReadAllText((Join-Path $installed 'local-settings.txt')) -eq 'preserve-customer-data') 'Unrelated data changed'
  }
  Check 'Atomic replacement preserves data behind an unrelated hardlink alias' {
    $alias=Join-Path $scratch 'unrelated-hardlink.exe';$target=Join-Path $installed 'rustdesk.exe'
    New-Item -ItemType HardLink -Path $alias -Target $target | Out-Null
    $before=[IO.File]::ReadAllText($alias)
    $source=Join-Path $scratch 'replacement.exe';[IO.File]::WriteAllText($source,'new-replacement-bytes')
    Copy-UpdateFile $source $target
    Assert ([IO.File]::ReadAllText($alias) -ceq $before) 'Hardlink alias data was modified'
    Assert ([IO.File]::ReadAllText($target) -ceq 'new-replacement-bytes') 'Target entry was not replaced'
    Copy-VerifiedRuntime $backup $installed $oldFiles
  }
  Check 'Manual-reset barrier stays set across observers and grants no world modification' {
    $script:journal=$null
    $eventName='Local\rdcl-update-fixture-'+[guid]::NewGuid().ToString('N')
    $ownerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $event=Open-UpdateBarrier $eventName $ownerSid
    try {
      Assert (!$event.WaitOne(0)) 'New idle barrier is set'
      $event.Set()|Out-Null;Assert ($event.WaitOne(0)) 'Barrier did not set';Assert ($event.WaitOne(0)) 'Barrier reset after one observer'
      $event.Reset()|Out-Null;Assert (!$event.WaitOne(0)) 'Barrier did not reset'
      foreach($rule in $event.GetAccessControl().Access) {
        if($rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-1-0') {
          Assert (($rule.EventWaitHandleRights -band [Security.AccessControl.EventWaitHandleRights]::Modify) -eq 0) 'World may clear barrier'
        }
      }
      Reject {Open-UpdateBarrier $eventName 'S-1-5-18'}
    } finally {$event.Dispose()}
  }
  Check 'Lost action response reuses the persisted action identity' {
    $script:journalPath=Join-Path $scratch 'action.json'
    $script:journal=@{job=@{id=[guid]::NewGuid().ToString();fence=[guid]::NewGuid().ToString()};release=@{sha256='a'*64};pending_action=$null}
    $script:ids=New-Object Collections.Generic.List[string]
    function Invoke-OfficeUpdate($Endpoint,$Body){$script:ids.Add($Body.action_id);throw 'simulated_connection_lost'}
    Reject {Send-UpdateAction 'permit' @{idle=$true}}
    $script:journal=Get-Content -Raw $script:journalPath | ConvertFrom-Json
    Reject {Send-UpdateAction 'permit' @{idle=$true}}
    Assert ($script:ids.Count -eq 2 -and $script:ids[0] -eq $script:ids[1]) 'Lost response generated a second command'
  }
  Check 'Confirmed action clears the durable pending request' {
    function Invoke-OfficeUpdate($Endpoint,$Body){return [pscustomobject]@{job=[pscustomobject]@{id=$Body.job_id;fence=$Body.fence;state='installing'}}}
    Send-UpdateAction 'permit' @{idle=$true} | Out-Null
    Assert ($null -eq $script:journal.pending_action) 'Pending action not cleared'
  }
  Check 'Independent recovery host is verified; existing unrelated task is never overwritten' {
    $script:root=Join-Path $scratch 'recovery';New-Item -ItemType Directory $script:root|Out-Null
    $script:installRoot=$installed;$script:CorePath=Join-Path $installed 'rustdesk.exe'
    $script:machine=@{host_path='';installation_id=[guid]::NewGuid().ToString()}
    $script:taskRegistered=0
    function Get-ScheduledTask {return $null}
    function New-ScheduledTaskAction {param($Execute,$Argument);return @{Execute=$Execute;Arguments=$Argument}}
    function New-ScheduledTaskTrigger {param([switch]$AtStartup);return @{Boot=$true}}
    function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel);return @{UserId=$UserId}}
    function New-ScheduledTaskSettingsSet {param($ExecutionTimeLimit,[switch]$StartWhenAvailable,$MultipleInstances,$RestartCount,$RestartInterval);return @{}}
    function Register-ScheduledTask {param($TaskName,$Action,$Trigger,$Principal,$Settings,$Description);$script:taskRegistered++}
    Initialize-IndependentRecovery
    $firstHost=$script:machine.host_path
    Assert (Test-Path $firstHost) 'Verified recovery host missing'
    Assert ($script:taskRegistered -eq 1) 'Owned recovery task was not prepared'
    $before=(Get-FileHash $firstHost -Algorithm SHA256).Hash
    [IO.File]::WriteAllText((Join-Path $installed 'rustdesk.exe'),'next-verified-executable')
    Initialize-IndependentRecovery -Promote
    Assert ($script:machine.host_path -ne $firstHost) 'Host slot was overwritten in place'
    Assert ((Get-FileHash $firstHost -Algorithm SHA256).Hash -eq $before) 'Previous recovery host lost'
    $selected=$script:machine.host_path
    function Get-ScheduledTask {return [pscustomobject]@{Description='unrelated-existing-task';Principal=@{UserId='SYSTEM'};Actions=@()}}
    Reject {Initialize-IndependentRecovery}
    Assert ($script:machine.host_path -eq $selected) 'Unrelated task changed host selection'
  }
  Check 'Changed inactive recovery files block cleanup and preserve the active host' {
    $inactive=Join-Path $script:root 'host-a\rustdesk.exe'
    [IO.File]::WriteAllText($inactive,'unexpected-changed-file')
    $active=$script:machine.host_path
    Reject {Initialize-IndependentRecovery -Promote}
    Assert ($script:machine.host_path -eq $active) 'Active recovery host changed on failed cleanup'
    Assert ([IO.File]::ReadAllText($inactive) -eq 'unexpected-changed-file') 'Changed bytes were removed'
  }
  Check 'Lost permit reply reports the unchanged old runtime without starting another installation' {
    $script:root=$scratch;$script:installRoot=$installed
    Copy-VerifiedRuntime $backup $installed $oldFiles
    $script:journalPath=Join-Path $scratch 'lost-permit.json'
    $job=[pscustomobject]@{id=[guid]::NewGuid().ToString();fence=[guid]::NewGuid().ToString();state='installing';old_version='3.1.2'}
    $script:journal=@{job=$job;phase='backed_up';pending_action=$null;release=@{sha256='a'*64};old_files=$oldFiles;new_files=$newFiles}
    $script:barrier=New-Object psobject
    $script:barrier|Add-Member ScriptMethod Set {return $true};$script:barrier|Add-Member ScriptMethod Reset {return $true}
    $script:actions=New-Object Collections.Generic.List[string]
    function Get-UpdateReport {return @{version='3.1.2';idle=$true;service_running=$true;identity_preserved=$true;inventory_verified=$false}}
    function Assert-PrivateUpdateDirectory($Root) {}
    function Invoke-OfficeUpdate($Endpoint,$Body) {
      if($Endpoint -eq 'poll'){return [pscustomobject]@{job=$job}}
      $script:actions.Add($Body.action)
      return [pscustomobject]@{job=[pscustomobject]@{id=$job.id;fence=$job.fence;state='rolled_back'}}
    }
    function Complete-UpdateJob([string]$Phase){$script:journal.phase=$Phase}
    Invoke-UpdateCycle
    Assert ($script:actions.Count -eq 1 -and $script:actions[0] -eq 'rollback') 'Permit reply loss caused redispatch'
    Assert-RuntimeInventory $installed $oldFiles
  }
  foreach($mask in 0..3) {
    $combination=$mask
    Check "Power-cut mixture $combination restores only owned runtime files" {
      $case=Join-Path $scratch ('powercut-'+$combination);New-Item -ItemType Directory $case|Out-Null
      $script:installRoot=Join-Path $case 'installed';New-Item -ItemType Directory $script:installRoot|Out-Null
      $payload=Join-Path $case 'payload';New-Item -ItemType Directory $payload|Out-Null
      [IO.File]::WriteAllText((Join-Path $payload 'rustdesk.exe'),'verified-new-exe')
      [IO.File]::WriteAllText((Join-Path $payload 'librustdesk.dll'),'verified-new-core')
      [IO.File]::WriteAllText((Join-Path $payload 'new-only.dll'),'verified-new-only')
      $next=@(Get-RuntimeInventory $payload)
      Copy-VerifiedRuntime $backup $script:installRoot $oldFiles
      for($i=0;$i -lt 2;$i++){if($combination -band (1 -shl $i)){Copy-UpdateFile (Join-Path $payload $oldFiles[$i].path) (Join-Path $script:installRoot $oldFiles[$i].path)}}
      Copy-UpdateFile (Join-Path $payload 'new-only.dll') (Join-Path $script:installRoot 'new-only.dll')
      [IO.File]::WriteAllText((Join-Path $script:installRoot 'customer-config.txt'),'customer-updated-this-during-backup')
      $script:journalPath=Join-Path $case 'journal.json'
      $script:journal=@{phase='replacing';recovery_attempts=0;backup=$backup;old_files=$oldFiles;new_files=$next;job=@{old_version='3.1.2'}}
      function Stop-UpdateProcesses {}
      function Start-UpdateService {}
      function Get-UpdateReport {return @{version='3.1.2';identity_preserved=$true}}
      function Invoke-UpdateCore {param($Mode);return @{}}
      function Send-UpdateAction {param($Action,$Report,$Code);Assert ($Action -eq 'rollback' -and $Report.inventory_verified) 'Rollback not verified'}
      Restore-UpdateBackup
      Assert-RuntimeInventory $script:installRoot $oldFiles
      Assert (!(Test-Path (Join-Path $script:installRoot 'new-only.dll'))) 'Owned new-only file retained'
      Assert ([IO.File]::ReadAllText((Join-Path $script:installRoot 'customer-config.txt')) -ceq 'customer-updated-this-during-backup') 'Customer data overwritten'
      Assert ($script:journal.phase -eq 'rolled_back' -and $script:journal.recovery_attempts -eq 1) 'Durable rollback phase missing'
    }
  }
  Check 'Unknown changed runtime bytes prevent rollback deletion and preserve evidence' {
    $target=Join-Path $script:installRoot 'rustdesk.exe';[IO.File]::WriteAllText($target,'unknown-third-party-change')
    Reject {Restore-UpdateBackup}
    Assert ([IO.File]::ReadAllText($target) -ceq 'unknown-third-party-change') 'Unknown runtime bytes changed'
  }
  Check 'Lost verified-success response retains the new runtime and the uncertain fleet slot' {
    $script:journal=@{phase='verifying';pending_action=$null};$script:actions=New-Object Collections.Generic.List[string]
    function Restore-UpdateBackup {throw 'must_not_restore_after_lost_success_ack'}
    function Send-UpdateAction {param($Action,$Report,$Code);$script:actions.Add($Action)}
    Handle-UpdateCycleFailure 'network_lost'
    Assert ($script:actions.Count -eq 1 -and $script:actions[0] -eq 'uncertain') 'Lost success response released fleet or restored runtime'
  }
  Check 'A rejected signature fails the unpermitted job instead of retrying installation' {
    $script:journal=@{phase='offered';pending_action=$null};$script:actions=New-Object Collections.Generic.List[string]
    function Send-UpdateAction {param($Action,$Report,$Code);$script:actions.Add($Action)}
    function Complete-UpdateJob {param($Phase);$script:journal.phase=$Phase}
    Handle-UpdateCycleFailure 'release_signature_invalid'
    Assert ($script:actions.Count -eq 1 -and $script:actions[0] -eq 'fail' -and $script:journal.phase -eq 'failed') 'Untrusted package did not fail safely'
  }
  Check 'A lost rollback acknowledgement finishes local recovery after verified server readback' {
    $script:root=$scratch;$script:installRoot=$installed;Copy-VerifiedRuntime $backup $installed $oldFiles
    $job=[pscustomobject]@{id=[guid]::NewGuid().ToString();fence=[guid]::NewGuid().ToString();state='unknown';old_version='3.1.2'}
    $script:journal=@{job=$job;phase='rolled_back';pending_action=$null;release=@{sha256='a'*64};old_files=$oldFiles;new_files=$newFiles}
    $script:journalPath=Join-Path $scratch 'rollback-reply.json';$script:completed=$false
    function Assert-PrivateUpdateDirectory($Root) {}
    function Invoke-OfficeUpdate($Endpoint,$Body){return [pscustomobject]@{job=$job}}
    function Get-Service {param($Name);return @{Status='Running'}}
    function Get-UpdateReport {return @{version='3.1.2';identity_preserved=$true}}
    function Send-UpdateAction {param($Action,$Report,$Code);Assert ($Action -eq 'rollback' -and $Report.inventory_verified) 'Rollback readback not verified'}
    function Complete-UpdateJob {param($Phase);Assert ($Phase -eq 'rolled_back') 'Wrong recovered phase';$script:completed=$true}
    Invoke-UpdateCycle
    Assert $script:completed 'Confirmed rollback did not finish tray/retention recovery'
  }
  Check 'Office-signed unsigned package is hash-checked before extraction; corrupted data never executes' {
    $script:fixtureInstaller=Join-Path $scratch 'unsigned-fixture.exe';[IO.File]::WriteAllText($script:fixtureInstaller,'synthetic-never-executed-payload')
    $release=[pscustomobject]@{verification='office-ed25519-v1';size_bytes=(Get-Item $script:fixtureInstaller).Length;sha256=(Get-FileHash $script:fixtureInstaller -Algorithm SHA256).Hash.ToLowerInvariant()}
    $script:started=0
    function Start-Process {param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru,[switch]$Wait);$script:started++;Assert ($ArgumentList[0] -ceq '--office-update-extract') 'Non-extraction invocation';return @{ExitCode=0}}
    Expand-OfficeUpdatePayload $script:fixtureInstaller (Join-Path $scratch 'fake-payload-output') $release
    Assert ($script:started -eq 1) 'Verified unsigned fixture was not offered for extraction'
    [IO.File]::WriteAllText($script:fixtureInstaller,'changed')
    Reject {Expand-OfficeUpdatePayload $script:fixtureInstaller (Join-Path $scratch 'fake-payload-output') $release}
    Assert ($script:started -eq 1) 'Changed bytes reached execution'
  }
  foreach($policy in @('hash-only','none','authenticode')) {
    $invalidPolicy=$policy
    Check "Unapproved verification policy $invalidPolicy cannot execute an installer" {
      function Start-Process {throw 'must_not_execute'}
      Reject {Expand-OfficeUpdatePayload $script:fixtureInstaller (Join-Path $scratch 'fake-payload-output') ([pscustomobject]@{verification=$invalidPolicy})}
    }
  }
  foreach($nativeCode in @(577,1260)) {
    $blockedCode=$nativeCode
    Check "Windows policy rejection $blockedCode is reported without weakening protection" {
      $release=[pscustomobject]@{verification='office-ed25519-v1';size_bytes=(Get-Item $script:fixtureInstaller).Length;sha256=(Get-FileHash $script:fixtureInstaller -Algorithm SHA256).Hash.ToLowerInvariant()}
      function Start-Process {throw (New-Object ComponentModel.Win32Exception($blockedCode))}
      $code='';try{Expand-OfficeUpdatePayload $script:fixtureInstaller (Join-Path $scratch 'blocked-payload-output') $release}catch{$code=$_.Exception.Message}
      Assert ($code -ceq 'windows_policy_blocked') 'Policy rejection was not classified'
      $script:journal=@{phase='offered';pending_action=$null};$script:actions=New-Object Collections.Generic.List[string]
      function Send-UpdateAction {param($Action,$Report,$Code);$script:actions.Add($Action)}
      function Complete-UpdateJob {param($Phase);$script:journal.phase=$Phase}
      Handle-UpdateCycleFailure $code
      Assert ($script:actions.Count -eq 1 -and $script:actions[0] -eq 'fail') 'Policy rejection did not stop distribution'
    }
  }
  Check 'A blocked child exit cannot become successful extraction' {
    $release=[pscustomobject]@{verification='office-ed25519-v1';size_bytes=(Get-Item $script:fixtureInstaller).Length;sha256=(Get-FileHash $script:fixtureInstaller -Algorithm SHA256).Hash.ToLowerInvariant()}
    function Start-Process {return @{ExitCode=-1073740760}}
    $code='';try{Expand-OfficeUpdatePayload $script:fixtureInstaller (Join-Path $scratch 'blocked-exit-output') $release}catch{$code=$_.Exception.Message}
    Assert ($code -ceq 'windows_policy_blocked') 'Blocked exit became success'
  }
  Check 'Hidden main window and helpers are tolerated; session windows still block' {
    foreach($line in @('"C:\Program Files\rd-cl\rd-cl.exe"','"C:\Program Files\rd-cl\rd-cl.exe" ','C:\rd-cl\rd-cl.exe','"C:\Program Files\rd-cl\rd-cl.exe" --tray','"C:\Program Files\rd-cl\rd-cl.exe" --server')) {
      Assert (Test-UpdateTolerableCoreProcess $line) "Tolerable process blocked: $line"
    }
    foreach($line in @('"C:\Program Files\rd-cl\rd-cl.exe" --cm','"C:\Program Files\rd-cl\rd-cl.exe" --connect 123456789','"C:\Program Files\rd-cl\rd-cl.exe" --install','"C:\Program Files\rd-cl\rd-cl.exe" rustdesk://connection/new/1','"C:\Program Files\rd-cl\rd-cl.exe" --cm-no-ui')) {
      Assert (!(Test-UpdateTolerableCoreProcess $line)) "Session window accepted: $line"
    }
  }
  Check 'Native source has no UAC bypass, upstream-update enable or arbitrary execution endpoint' {
    $text=Get-Content -Raw -LiteralPath $Source
    Assert ($text -notmatch '(?i)Set-ExecutionPolicy|ExecutionPolicy\s+Bypass|Invoke-Expression|Restart-Computer') 'Unapproved bypass/reboot found'
    Assert ($text -match 'MaximumRedirection 0' -and $text -match '--office-update-verify') 'Trust boundary missing'
  }
  $result=@{status='PASS';source_sha256=(Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant();tests=$passed.Count;names=@($passed);product_installation='NOT_RUN';service_changes='NOT_RUN';network='NOT_RUN';fixture=$scratch}
  if($Output){[IO.File]::WriteAllText($Output,($result|ConvertTo-Json -Depth 5))}
  $result|ConvertTo-Json -Depth 5
} finally {
  # Only the owned synthetic test directory; no product/profile/cache paths.
  if($scratch -and $scratch -like (Join-Path ([IO.Path]::GetTempPath()) 'rdcl-update-fixture-*')){Remove-Item -LiteralPath $scratch -Recurse -Force}
}
