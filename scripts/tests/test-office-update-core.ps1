param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$GuiPython,
    [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) {
    throw 'Native Windows PowerShell 5.1 fixture required'
}
if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18') {
    throw 'Run this isolated fixture as the existing guest user, never as SYSTEM'
}
if (Test-Path -LiteralPath $Output) {throw 'Refusing to overwrite an existing fixture receipt'}
if (!(Test-Path -LiteralPath (Split-Path -Parent $Output) -PathType Container)) {throw 'Prepare an owned output directory first'}
# Require a real existing x64 Windows GUI executable, not a console shim.
$binary=[IO.BinaryReader]::new([IO.File]::OpenRead($GuiPython))
try {
    if ($binary.ReadUInt16() -ne 0x5a4d) {throw 'GUI Python is not a PE executable'}
    $binary.BaseStream.Position=0x3c;$pe=$binary.ReadUInt32()
    $binary.BaseStream.Position=$pe
    if ($binary.ReadUInt32() -ne 0x4550 -or $binary.ReadUInt16() -ne 0x8664) {throw 'Expected native x64 GUI Python'}
    $binary.BaseStream.Position=$pe+24+68
    if ($binary.ReadUInt16() -ne 2) {throw 'Expected Windows GUI subsystem'}
} finally {$binary.Dispose()}
. $Source -LibraryOnly
$script:CorePath=(Get-Item -LiteralPath $GuiPython).FullName
$scratch=Join-Path (Split-Path -Parent $Output) ('core helper fixture '+[char]0x03a9)
if (Test-Path -LiteralPath $scratch) {throw 'Refusing to overwrite fixture scratch'}
$null=New-Item -ItemType Directory -Path $scratch
$probe=Join-Path $scratch ('core probe '+[char]0x03a9+'.py')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\office_update_core_probe.py') -Destination $probe
$script:passed=[Collections.Generic.List[string]]::new()
$script:currentCase='setup'
$script:expectedErrorCode=$null
$script:actualErrorCode=$null
$sentinel=$null
$oldBytecode=[Environment]::GetEnvironmentVariable('PYTHONDONTWRITEBYTECODE','Process')
$env:PYTHONDONTWRITEBYTECODE='1'
function Assert($Value,[string]$Code) {if (!$Value) {throw $Code}}
function Check([string]$Name,[scriptblock]$Body) {
    $script:currentCase=$Name
    $script:expectedErrorCode=$null;$script:actualErrorCode=$null
    & $Body
    $script:passed.Add($Name)
}
function Expect-Code([string]$Expected,[scriptblock]$Body) {
    $actual='NO_EXCEPTION'
    try {$null=& $Body} catch {$actual=$_.Exception.Message}
    if ($actual -cne $Expected) {
        $script:expectedErrorCode=$Expected
        $script:actualErrorCode=if($actual -cmatch '^(?:[a-z_]{1,64}|NO_EXCEPTION)$'){$actual}else{'REDACTED'}
    }
    Assert ($actual -ceq $Expected) 'unexpected_error_code'
    Assert ($actual -notmatch 'SYNTHETIC_PRIVATE_TEXT') 'stderr_leaked'
}
$status='FAIL';$errorCode=$null;$exceptionType=$null;$failureLine=$null
try {
    Check 'GUI success with absent LASTEXITCODE waits for completion' {
        Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name LASTEXITCODE -Scope Script -ErrorAction SilentlyContinue
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $reply=Invoke-UpdateCore $probe @('delayed')
        Assert ($reply.ok -eq $true) 'missing_success_reply'
        Assert ($clock.ElapsedMilliseconds -ge 450) 'did_not_wait_for_gui_child'
        Assert ($null -eq (Get-Variable LASTEXITCODE -ErrorAction SilentlyContinue)) 'ambient_exit_code_created'
    }
    Check 'GUI success ignores stale ambient nonzero exit' {
        $global:LASTEXITCODE=77
        $reply=Invoke-UpdateCore $probe @('ok')
        Assert ($reply.ok -eq $true -and $global:LASTEXITCODE -eq 77) 'ambient_exit_code_used'
    }
    Check 'Actual child failure rejects valid JSON despite stale zero exit' {
        $global:LASTEXITCODE=0
        Expect-Code 'core_check_failed' {Invoke-UpdateCore $probe @('nonzero')}
    }
    Check 'Exact empty spaced quoted slash Unicode and shell-like argv' {
        $unicode=-join @([char]0x0394,[char]0x03bf,[char]0x03ba,[char]0x03b9,[char]0x03bc,[char]0x03ae)
        $expected=@('two words','','quote"inside','end\','slash\"quote','C:\with spaces\','$()&|;%PATH%',$unicode,"line`nbreak")
        $reply=Invoke-UpdateCore $probe (@('ok')+$expected)
        Assert (@($reply.argv).Count -eq $expected.Count) 'argv_count_changed'
        for($i=0;$i -lt $expected.Count;$i++) {Assert ($reply.argv[$i] -ceq $expected[$i]) 'argv_value_changed'}
    }
    Check 'Empty stdout is rejected' {Expect-Code 'core_response_invalid' {Invoke-UpdateCore $probe @('empty')}}
    Check 'Malformed JSON is rejected without raw parser detail' {Expect-Code 'core_response_invalid' {Invoke-UpdateCore $probe @('malformed')}}
    Check 'Multiple JSON replies are rejected' {Expect-Code 'core_response_invalid' {Invoke-UpdateCore $probe @('multiple')}}
    Check 'Stderr on zero exit is rejected and redacted' {Expect-Code 'core_stderr_invalid' {Invoke-UpdateCore $probe @('stderr')}}
    Check 'Concurrent large stdout and stderr cannot deadlock' {Expect-Code 'core_stderr_invalid' {Invoke-UpdateCore $probe @('both')}}
    Check 'Output exceeding the fixed bound is rejected' {Expect-Code 'core_output_invalid' {Invoke-UpdateCore $probe @('overflow')}}
    Check 'CreateProcess failure is reported without raw path detail' {
        $script:CorePath=Join-Path $scratch 'SYNTHETIC_PRIVATE_TEXT-missing.exe'
        try {Expect-Code 'core_start_failed' {Invoke-UpdateCore $probe @('ok')}}
        finally {$script:CorePath=(Get-Item -LiteralPath $GuiPython).FullName}
    }
    Check 'Explicit trusted host executable is used instead of the install core' {
        $script:CorePath=Join-Path $scratch 'SYNTHETIC_PRIVATE_TEXT-missing.exe'
        try {
            $reply=Invoke-UpdateCore $probe @('ok') (Get-Item -LiteralPath $GuiPython).FullName
            Assert ($reply.ok -eq $true) 'explicit_executable_not_used'
        } finally {$script:CorePath=(Get-Item -LiteralPath $GuiPython).FullName}
    }
    Check 'NUL argv is rejected before starting a child' {Expect-Code 'core_argument_invalid' {Invoke-UpdateCore $probe @('ok',([string][char]0))}}
    Check 'Deadline terminates only its own helper and leaves a sentinel alive' {
        $sentinelMarker=Join-Path $scratch 'sentinel.pid'
        $start=[Diagnostics.ProcessStartInfo]::new()
        $start.FileName=$script:CorePath
        $start.Arguments=(@($probe,'sleep',$sentinelMarker) | ForEach-Object {ConvertTo-UpdateCoreArgument $_}) -join ' '
        $start.WorkingDirectory=$scratch;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
        $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
        $script:sentinel=[Diagnostics.Process]::new();$script:sentinel.StartInfo=$start
        Assert ($script:sentinel.Start()) 'sentinel_start_failed'
        $marker=Join-Path $scratch 'timeout-helper.pid'
        Expect-Code 'core_timeout' {Invoke-UpdateCore $probe @('sleep',$marker)}
        Assert (Test-Path -LiteralPath $marker) 'timeout_helper_did_not_start'
        $helperPid=[int][IO.File]::ReadAllText($marker)
        Assert ($null -eq (Get-Process -Id $helperPid -ErrorAction SilentlyContinue)) 'timed_out_helper_still_running'
        Assert (!$script:sentinel.HasExited) 'unrelated_sentinel_was_terminated'
    }
    $status='PASS'
} catch {
    $errorCode=if ($_.Exception.Message -cmatch '^[a-z_]{1,64}$') {$_.Exception.Message} else {'fixture_failed'}
    $exceptionType=$_.Exception.GetType().Name;$failureLine=$_.InvocationInfo.ScriptLineNumber
} finally {
    try {
        if ($null -ne $sentinel -and !$sentinel.HasExited) {
            $sentinel.Kill()
            if (!$sentinel.WaitForExit(5000)) {$status='FAIL';$errorCode='sentinel_cleanup_failed'}
        }
    } catch {$status='FAIL';$errorCode='sentinel_cleanup_failed'}
    finally {
        if ($null -ne $sentinel) {$sentinel.Dispose()}
        [Environment]::SetEnvironmentVariable('PYTHONDONTWRITEBYTECODE',$oldBytecode,'Process')
    }
}
$report=[ordered]@{
    status=$status;tests=$passed.Count;cases=@($passed.ToArray());failed_case=$(if($status -eq 'FAIL'){$currentCase}else{$null});error_code=$errorCode
    expected_error_code=$expectedErrorCode;actual_error_code=$actualErrorCode;exception_type=$exceptionType;script_line=$failureLine
    source_sha256=(Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant()
    gui_python_sha256=(Get-FileHash -LiteralPath $GuiPython -Algorithm SHA256).Hash.ToLowerInvariant()
    powershell_version=$PSVersionTable.PSVersion.ToString();gui_subsystem=2;scratch=$scratch
    product_installation='NOT_RUN';service_changes='NOT_RUN';network='NOT_RUN';nas='NOT_TOUCHED'
}
[IO.File]::WriteAllText($Output,($report | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
[Console]::WriteLine('native_core_process_cases='+$passed.Count+';status='+$status)
if ($status -ne 'PASS') {exit 1}
