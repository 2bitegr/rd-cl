param(
  [string]$ApiBaseUrl = $env:EXANTAS_OFFICE_API_BASE_URL,
  [int]$PollSeconds = 3,
  [switch]$Pair,
  [switch]$InstallStartup,
  [switch]$InstallOnly,
  [switch]$UninstallStartup,
  [switch]$Watchdog
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
  $ApiBaseUrl = 'https://api-office.exantas.eu/api/v1'
}
$ApiBaseUrl = $ApiBaseUrl.TrimEnd('/')
$PollSeconds = [Math]::Max(2, $PollSeconds)

$CompanionVersion = '2026.10.10.01'
$AppDir = Join-Path $env:APPDATA 'Exantas\RustDeskCompanion'
$ConfigPath = Join-Path $AppDir 'config.json'
$LogPath = Join-Path $AppDir 'companion.log'
$QueuePath = Join-Path $AppDir 'pending-comments.json'
$WorkflowSuppressionPath = Join-Path $AppDir 'workflow-v2-suppression.dpapi'
$WebSocketSignalPath = Join-Path $AppDir 'ws-signal.txt'
$StartupShortcutName = 'Exantas RustDesk Companion.lnk'
$StartupShortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) $StartupShortcutName
$InstalledScriptPath = Join-Path $AppDir 'technician-companion.ps1'
$TaskName = 'Exantas RustDesk Companion'
$WatchdogTaskName = 'Exantas RustDesk Companion Watchdog'
$TaskPath = '\Exantas\'

New-Item -ItemType Directory -Force -Path $AppDir | Out-Null

try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
  # Older Windows builds may not expose this property. The API call will fail later if TLS is unsupported.
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:ShouldExit = $false
$script:ForcePoll = $false
$script:SnoozedSessionIds = New-Object 'System.Collections.Generic.HashSet[string]'
$script:CompanionConfig = $null
$script:PendingSessions = @()
$script:SingleInstanceMutex = $null
$script:WebSocketPowerShell = $null
$script:WebSocketAsyncResult = $null
$script:LastWebSocketSignalUtc = [DateTime]::MinValue

function Write-CompanionLog {
  param([string]$Message)
  $timestamp = (Get-Date).ToString('s')
  Add-Content -Path $LogPath -Value "[$timestamp] $Message"
}

function Start-SingleInstanceGuard {
  $createdNew = $false
  $mutexName = "Local\ExantasRustDeskCompanion-$env:USERNAME"
  $script:SingleInstanceMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
  if (!$createdNew) {
    Write-CompanionLog 'Another companion instance is already running.'
    exit 0
  }
}

function Stop-SingleInstanceGuard {
  if ($null -eq $script:SingleInstanceMutex) {
    return
  }
  try {
    $script:SingleInstanceMutex.ReleaseMutex() | Out-Null
  } catch {
  }
  $script:SingleInstanceMutex.Dispose()
  $script:SingleInstanceMutex = $null
}

function Protect-Text {
  param([string]$Text)
  if ($null -eq $Text) {
    $Text = ''
  }
  $secure = ConvertTo-SecureString $Text -AsPlainText -Force
  return ConvertFrom-SecureString $secure
}

function Unprotect-Text {
  param([string]$ProtectedText)
  if ([string]::IsNullOrWhiteSpace($ProtectedText)) {
    return ''
  }
  $secure = ConvertTo-SecureString $ProtectedText
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

function Get-CommentIdempotencyKey {
  param(
    [object]$Session,
    [string]$Comment
  )
  $source = "$($Session.id)|$Comment"
  $bytes = [Text.Encoding]::UTF8.GetBytes($source)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($bytes)
    return 'rcc_' + (-join ($hash | ForEach-Object { $_.ToString('x2') }))
  } finally {
    $sha.Dispose()
  }
}

function Read-OfflineQueue {
  if (!(Test-Path $QueuePath)) {
    return @()
  }
  try {
    $raw = Get-Content -Path $QueuePath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
      return @()
    }
    return @($raw | ConvertFrom-Json)
  } catch {
    Write-CompanionLog "Offline queue read failed: $($_.Exception.Message)"
    return @()
  }
}

function Save-OfflineQueue {
  param([object[]]$Items)
  if ($null -eq $Items -or $Items.Count -eq 0) {
    '[]' | Set-Content -Path $QueuePath -Encoding UTF8
    return
  }
  @($Items) | ConvertTo-Json -Depth 8 | Set-Content -Path $QueuePath -Encoding UTF8
}

function Get-OfflineQueueCount {
  return @((Read-OfflineQueue)).Count
}

function Add-OfflineComment {
  param(
    [object]$Session,
    [string]$Comment,
    [string]$IdempotencyKey,
    [string]$LastError
  )

  $items = New-Object System.Collections.Generic.List[object]
  foreach ($item in @(Read-OfflineQueue)) {
    $items.Add($item)
  }
  foreach ($item in $items) {
    if ([string]$item.idempotency_key -eq $IdempotencyKey) {
      Write-CompanionLog "Offline comment already queued for session $($Session.id)."
      return
    }
  }

  $items.Add([pscustomobject]@{
    session_id = [string]$Session.id
    customer_name = [string]$Session.customer_name
    peer_id = [string]$Session.peer_id
    from_peer = [string]$script:CompanionConfig.RustDeskPeerId
    rustdesk_session_id = Get-DecisionValue -Decision $Session -Name 'rustdesk_session_id'
    idempotency_key = $IdempotencyKey
    protected_comment = Protect-Text $Comment
    attempts = 0
    last_error = $LastError
    created_at = (Get-Date).ToUniversalTime().ToString('o')
  })
  Save-OfflineQueue -Items $items.ToArray()
  Write-CompanionLog "Queued offline comment for session $($Session.id)."
}

function Should-QueueSubmissionFailure {
  param([string]$Message)
  return !($Message -match 'validation_error|missing_recipient|access_denied|not_found|Pending session not found|Invalid companion session')
}

function Test-OfficeWorkflowV2 {
  param([string]$Token)
  $requestApiBase = Get-CanonicalOfficeApiBaseUrl $script:ApiBaseUrl
  $requestPeerId = [string]$script:CompanionConfig.RustDeskPeerId
  $capabilities = Invoke-OfficeApi -Method 'GET' -Path '/rustdesk-companion/workflow-capabilities' -Token $Token -NotFoundIsNull
  # A transport-level 404 is the explicit compatibility signal from an older API.
  if ($null -eq $capabilities) { return $false }
  if ($capabilities.status -ne 'ok' -or $capabilities.enabled -isnot [bool] -or
      $capabilities.contract_versions -isnot [System.Array]) {
    throw 'Invalid Office workflow capabilities response.'
  }
  $supportsV2 = $capabilities.enabled -and (@($capabilities.contract_versions) -contains 2)
  if ($supportsV2) {
    $scopeChanged = Set-V2WorkflowSuppressionScopeFromCapabilities -Capabilities $capabilities `
      -ExpectedApiBaseUrl $requestApiBase -ExpectedToken $Token -ExpectedPeerId $requestPeerId
    if ($scopeChanged) {
      Save-CompanionConfig -Token $script:CompanionConfig.CompanionToken `
        -RustDeskPeerId $script:CompanionConfig.RustDeskPeerId `
        -OfficeUserId $script:CompanionConfig.OfficeUserId -PairingId $script:CompanionConfig.PairingId `
        -TechnicianName $script:CompanionConfig.TechnicianName `
        -TechnicianEmail $script:CompanionConfig.TechnicianEmail
    }
  }
  return $supportsV2
}

function Get-OfficeWorkContext {
  param(
    [object]$Session,
    [string]$Token
  )
  $body = @{
    peer_id = [string]$Session.peer_id
    from_peer = [string]$script:CompanionConfig.RustDeskPeerId
  }
  $rustDeskSessionId = Get-DecisionValue -Decision $Session -Name 'rustdesk_session_id'
  if (![string]::IsNullOrWhiteSpace($rustDeskSessionId) -and $rustDeskSessionId -ne '0') {
    $body.rustdesk_session_id = $rustDeskSessionId
  }
  $context = Invoke-OfficeApi -Method 'POST' -Path '/rustdesk-companion/work-context' -Token $Token -Body $body
  $validClassifications = @('excluded', 'unassigned', 'bound', 'pending_identity')
  if ($context.status -ne 'ok' -or $context.contract_version -ne 2 -or
      $context.suppress_legacy -ne $true -or
      $validClassifications -notcontains [string]$context.classification) {
    throw 'Invalid Office work context response.'
  }
  if ($context.classification -eq 'bound' -and
      ([string]::IsNullOrWhiteSpace([string]$context.work_item_id) -or
       [string]::IsNullOrWhiteSpace([string]$context.work_revision) -or
       [string]::IsNullOrWhiteSpace([string]$context.remote_session_id))) {
    throw 'Incomplete bound Office work context response.'
  }
  return $context
}

function Read-V2WorkflowSuppressions {
  if (!(Test-Path -LiteralPath $WorkflowSuppressionPath)) {
    return @()
  }
  try {
    $protected = (Get-Content -LiteralPath $WorkflowSuppressionPath -Raw).Trim()
    $json = Unprotect-Text $protected
    if ([string]::IsNullOrWhiteSpace($json)) { return @() }
    return @($json | ConvertFrom-Json)
  } catch {
    Write-CompanionLog 'Workflow suppression markers could not be read; this poll is stopped to prevent a legacy fallback.'
    throw 'Workflow suppression markers are unavailable.'
  }
}

function Get-CanonicalOfficeApiBaseUrl {
  param([string]$Url)
  if ([string]::IsNullOrWhiteSpace($Url)) { return '' }
  $parsed = $null
  if (![Uri]::TryCreate($Url.Trim(), [UriKind]::Absolute, [ref]$parsed) -or
      $parsed.Scheme -notin @('http', 'https') -or
      ![string]::IsNullOrEmpty($parsed.UserInfo) -or
      ![string]::IsNullOrEmpty($parsed.Query) -or
      ![string]::IsNullOrEmpty($parsed.Fragment)) {
    return ''
  }
  $builder = New-Object System.UriBuilder($parsed)
  $builder.Scheme = $parsed.Scheme.ToLowerInvariant()
  $builder.Host = $parsed.Host.ToLowerInvariant()
  $builder.Path = $parsed.AbsolutePath.TrimEnd('/')
  return $builder.Uri.AbsoluteUri.TrimEnd('/')
}

function Get-V2WorkflowSuppressionScope {
  $config = $script:CompanionConfig
  if ($null -eq $config) { return $null }
  $apiBase = Get-CanonicalOfficeApiBaseUrl ([string](Get-DecisionValue -Decision $config -Name 'ApiBaseUrl'))
  $officeUserId = [string](Get-DecisionValue -Decision $config -Name 'OfficeUserId')
  $pairingId = [string](Get-DecisionValue -Decision $config -Name 'PairingId')
  $fromPeer = [string](Get-DecisionValue -Decision $config -Name 'RustDeskPeerId')
  $parsedOfficeUserId = [Guid]::Empty
  $parsedPairingId = [Guid]::Empty
  if ([string]::IsNullOrWhiteSpace($apiBase) -or
      [string]::IsNullOrWhiteSpace($officeUserId) -or
      [string]::IsNullOrWhiteSpace($pairingId) -or
      ![Guid]::TryParse($officeUserId, [ref]$parsedOfficeUserId) -or
      ![Guid]::TryParse($pairingId, [ref]$parsedPairingId) -or
      [string]::IsNullOrWhiteSpace($fromPeer)) {
    return $null
  }
  return [pscustomobject]@{
    api_base_url = $apiBase
    office_user_id = $parsedOfficeUserId.ToString('D')
    pairing_id = $parsedPairingId.ToString('D')
    from_peer = $fromPeer
  }
}

function Set-V2WorkflowSuppressionScopeFromCapabilities {
  param(
    [object]$Capabilities,
    [string]$ExpectedApiBaseUrl,
    [string]$ExpectedToken,
    [string]$ExpectedPeerId
  )
  $apiBase = Get-CanonicalOfficeApiBaseUrl $ExpectedApiBaseUrl
  $officeUserId = [string](Get-DecisionValue -Decision $Capabilities -Name 'office_user_id')
  $pairingId = [string](Get-DecisionValue -Decision $Capabilities -Name 'pairing_id')
  $currentApiBase = Get-CanonicalOfficeApiBaseUrl $script:ApiBaseUrl
  $configuredApiBase = Get-CanonicalOfficeApiBaseUrl ([string](Get-DecisionValue -Decision $script:CompanionConfig -Name 'ApiBaseUrl'))
  $currentToken = [string](Get-DecisionValue -Decision $script:CompanionConfig -Name 'CompanionToken')
  $currentPeerId = [string](Get-DecisionValue -Decision $script:CompanionConfig -Name 'RustDeskPeerId')
  if ([string]::IsNullOrWhiteSpace($apiBase) -or $apiBase -cne $currentApiBase -or
      $apiBase -cne $configuredApiBase -or $ExpectedToken -cne $currentToken -or
      $ExpectedPeerId -cne $currentPeerId) {
    throw 'The Office API, token, or paired peer changed during workflow scope verification.'
  }
  $parsedOfficeUserId = [Guid]::Empty
  $parsedPairingId = [Guid]::Empty
  if (![Guid]::TryParse($officeUserId, [ref]$parsedOfficeUserId) -or
      ![Guid]::TryParse($pairingId, [ref]$parsedPairingId)) {
    throw 'Office workflow capabilities omitted valid stable account/pairing IDs; pair again or contact Office support.'
  }
  $officeUserId = $parsedOfficeUserId.ToString('D')
  $pairingId = $parsedPairingId.ToString('D')
  $existingOfficeUserId = [string](Get-DecisionValue -Decision $script:CompanionConfig -Name 'OfficeUserId')
  $existingPairingId = [string](Get-DecisionValue -Decision $script:CompanionConfig -Name 'PairingId')
  if (![string]::IsNullOrWhiteSpace($existingOfficeUserId) -and $existingOfficeUserId -cne $officeUserId) {
    throw 'The authenticated Office principal differs from the saved workflow scope.'
  }
  if (![string]::IsNullOrWhiteSpace($existingPairingId) -and $existingPairingId -cne $pairingId) {
    throw 'The authenticated pairing differs from the saved workflow scope.'
  }
  $changed = [string]::IsNullOrWhiteSpace($existingOfficeUserId) -or
    [string]::IsNullOrWhiteSpace($existingPairingId)
  $script:CompanionConfig.ApiBaseUrl = $apiBase
  $script:CompanionConfig.OfficeUserId = $officeUserId
  $script:CompanionConfig.PairingId = $pairingId
  $script:ApiBaseUrl = $apiBase
  return $changed
}

function Test-V2WorkflowMarkerScope {
  param(
    [object]$Marker,
    [object]$Scope
  )
  if ($null -eq $Scope) { return $false }
  if ([string](Get-DecisionValue -Decision $Marker -Name 'workflow_contract_version') -ne '2' -or
      [string](Get-DecisionValue -Decision $Marker -Name 'workflow_classification') -notin @('bound', 'excluded', 'unassigned', 'pending_identity')) {
    return $false
  }
  return (Get-CanonicalOfficeApiBaseUrl ([string](Get-DecisionValue -Decision $Marker -Name 'api_base_url'))) -ceq $Scope.api_base_url -and
    [string](Get-DecisionValue -Decision $Marker -Name 'office_user_id') -ceq $Scope.office_user_id -and
    [string](Get-DecisionValue -Decision $Marker -Name 'pairing_id') -ceq $Scope.pairing_id -and
    [string](Get-DecisionValue -Decision $Marker -Name 'from_peer') -ceq $Scope.from_peer
}

function Save-V2WorkflowSuppressions {
  param([object[]]$Markers)
  $json = @($Markers) | ConvertTo-Json -Depth 5
  $protected = Protect-Text $json
  $temporaryPath = "$WorkflowSuppressionPath.tmp"
  Set-Content -LiteralPath $temporaryPath -Value $protected -Encoding UTF8
  Move-Item -LiteralPath $temporaryPath -Destination $WorkflowSuppressionPath -Force
}

function Add-V2WorkflowSuppression {
  param(
    [object]$Session,
    [object]$Context
  )
  if ($Context.classification -notin @('bound', 'excluded', 'unassigned', 'pending_identity') -or
      $Context.suppress_legacy -ne $true) {
    return
  }
  $sessionId = [string]$Session.id
  $peerId = [string]$Session.peer_id
  $rustDeskSessionId = Get-DecisionValue -Decision $Session -Name 'rustdesk_session_id'
  $scope = Get-V2WorkflowSuppressionScope
  if ($null -eq $scope) {
    throw 'The current Office account/pairing scope is unavailable; workflow suppression was not stored.'
  }
  if ([string]::IsNullOrWhiteSpace($sessionId) -and
      [string]::IsNullOrWhiteSpace([string]$rustDeskSessionId)) {
    return
  }
  $markers = New-Object System.Collections.Generic.List[object]
  foreach ($marker in @(Read-V2WorkflowSuppressions)) {
    $markers.Add($marker)
  }
  $alreadyStored = @($markers | Where-Object {
    (Test-V2WorkflowMarkerScope -Marker $_ -Scope $scope) -and (
    ([string](Get-DecisionValue -Decision $_ -Name 'session_id') -eq $sessionId -and
     [string](Get-DecisionValue -Decision $_ -Name 'peer_id') -eq $peerId) -or
    (![string]::IsNullOrWhiteSpace([string]$rustDeskSessionId) -and
     [string](Get-DecisionValue -Decision $_ -Name 'rustdesk_session_id') -eq [string]$rustDeskSessionId -and
     [string](Get-DecisionValue -Decision $_ -Name 'peer_id') -eq $peerId))
  }).Count -gt 0
  if ($alreadyStored) { return }
  $markers.Add([pscustomobject]@{
    workflow_contract_version = 2
    api_base_url = $scope.api_base_url
    office_user_id = $scope.office_user_id
    pairing_id = $scope.pairing_id
    session_id = $sessionId
    peer_id = $peerId
    from_peer = [string]$script:CompanionConfig.RustDeskPeerId
    rustdesk_session_id = [string]$rustDeskSessionId
    workflow_classification = [string]$Context.classification
    recorded_at = (Get-Date).ToUniversalTime().ToString('o')
  })
  Save-V2WorkflowSuppressions -Markers $markers.ToArray()
}

function Test-V2WorkflowSuppressed {
  param([object]$Session)
  $sessionId = [string]$Session.id
  $peerId = [string]$Session.peer_id
  $rustDeskSessionId = Get-DecisionValue -Decision $Session -Name 'rustdesk_session_id'
  $markers = @(Read-V2WorkflowSuppressions)
  $scope = Get-V2WorkflowSuppressionScope
  if ($null -eq $scope) {
    $hasScopedMarker = $false
    foreach ($marker in $markers) {
      if ([string](Get-DecisionValue -Decision $marker -Name 'workflow_contract_version') -eq '2') {
        $hasScopedMarker = $true
        break
      }
    }
    if ($hasScopedMarker) {
      # Old/unscoped markers are retained encrypted for review, but cannot be
      # assigned to whichever Office account happens to be paired now.
      throw 'The current Office account/pairing scope is unavailable; suppression checks are held.'
    }
    return $false
  }
  foreach ($marker in $markers) {
    if (!(Test-V2WorkflowMarkerScope -Marker $marker -Scope $scope) -or
        [string](Get-DecisionValue -Decision $marker -Name 'peer_id') -ne $peerId) { continue }
    if (![string]::IsNullOrWhiteSpace($sessionId) -and
        [string](Get-DecisionValue -Decision $marker -Name 'session_id') -eq $sessionId) { return $true }
    if (![string]::IsNullOrWhiteSpace([string]$rustDeskSessionId) -and
        [string](Get-DecisionValue -Decision $marker -Name 'rustdesk_session_id') -eq [string]$rustDeskSessionId) { return $true }
  }
  return $false
}

function Protect-Token {
  param([string]$Token)
  $secure = ConvertTo-SecureString $Token -AsPlainText -Force
  return ConvertFrom-SecureString $secure
}

function Unprotect-Token {
  param([string]$ProtectedToken)
  $secure = ConvertTo-SecureString $ProtectedToken
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

function Read-CompanionConfig {
  if (!(Test-Path $ConfigPath)) {
    return $null
  }
  $raw = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
  $technicianEmail = ''
  if ($raw.PSObject.Properties['technician_email']) {
    $technicianEmail = [string]$raw.technician_email
  }
  return @{
    ApiBaseUrl = [string]$raw.api_base_url
    CompanionToken = Unprotect-Token ([string]$raw.protected_companion_token)
    RustDeskPeerId = [string]$raw.rustdesk_peer_id
    OfficeUserId = [string](Get-DecisionValue -Decision $raw -Name 'office_user_id')
    PairingId = [string](Get-DecisionValue -Decision $raw -Name 'pairing_id')
    TechnicianName = [string]$raw.technician_name
    TechnicianEmail = $technicianEmail
    DeviceName = [string]$raw.device_name
    WindowsUser = [string]$raw.windows_user
  }
}

function Save-CompanionConfig {
  param(
    [string]$Token,
    [string]$RustDeskPeerId,
    [string]$OfficeUserId,
    [string]$PairingId,
    [string]$TechnicianName,
    [string]$TechnicianEmail
  )
  $canonicalApiBase = Get-CanonicalOfficeApiBaseUrl $ApiBaseUrl
  $parsedOfficeUserId = [Guid]::Empty
  $parsedPairingId = [Guid]::Empty
  if ([string]::IsNullOrWhiteSpace($canonicalApiBase) -or
      ![Guid]::TryParse($OfficeUserId, [ref]$parsedOfficeUserId) -or
      ![Guid]::TryParse($PairingId, [ref]$parsedPairingId)) {
    throw 'A valid Office API, account, and pairing identity are required to save companion configuration.'
  }
  $payload = [ordered]@{
    api_base_url = $canonicalApiBase
    protected_companion_token = Protect-Token $Token
    rustdesk_peer_id = $RustDeskPeerId
    office_user_id = $parsedOfficeUserId.ToString('D')
    pairing_id = $parsedPairingId.ToString('D')
    technician_name = $TechnicianName
    technician_email = $TechnicianEmail
    device_name = $env:COMPUTERNAME
    windows_user = "$env:USERDOMAIN\$env:USERNAME"
    saved_at = (Get-Date).ToUniversalTime().ToString('o')
  }
  $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
}

function Invoke-OfficeApi {
  param(
    [string]$Method,
    [string]$Path,
    [object]$Body = $null,
    [string]$Token = $null,
    [switch]$NotFoundIsNull
  )

  $headers = @{}
  if (![string]::IsNullOrWhiteSpace($Token)) {
    $headers.Authorization = "Bearer $Token"
  }

  $request = @{
    Uri = "$ApiBaseUrl$Path"
    Method = $Method
    Headers = $headers
    ContentType = 'application/json'
  }
  if ($null -ne $Body) {
    $request.Body = ($Body | ConvertTo-Json -Depth 8)
  }

  try {
    return Invoke-RestMethod @request
  } catch {
    if ($NotFoundIsNull -and $_.Exception.Response -and
        [int]$_.Exception.Response.StatusCode -eq 404) {
      return $null
    }
    $details = $_.Exception.Message
    if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
      try {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        if (![string]::IsNullOrWhiteSpace($responseBody)) {
          $details = "$details Body: $responseBody"
        }
      } catch {
        # Keep the original web exception if the response body cannot be read.
      }
    }
    throw $details
  }
}

function Get-DecisionValue {
  param(
    [object]$Decision,
    [string]$Name
  )
  if ($null -eq $Decision) {
    return ''
  }
  if ($Decision -is [System.Collections.IDictionary] -and $Decision.Contains($Name)) {
    return [string]$Decision[$Name]
  }
  $property = $Decision.PSObject.Properties[$Name]
  if ($null -ne $property) {
    return [string]$property.Value
  }
  return ''
}

function Get-RustDeskExeCandidates {
  $items = New-Object System.Collections.Generic.List[string]
  $items.Add((Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'))
  if (${env:ProgramFiles(x86)}) {
    $items.Add((Join-Path ${env:ProgramFiles(x86)} 'RustDesk\rustdesk.exe'))
  }
  $items.Add((Join-Path $env:LOCALAPPDATA 'Programs\RustDesk\rustdesk.exe'))
  try {
    $cmd = Get-Command rustdesk.exe -ErrorAction SilentlyContinue
    if ($cmd) {
      $items.Add($cmd.Source)
    }
  } catch {
  }
  return $items | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
}

function Get-RustDeskPeerId {
  foreach ($candidate in Get-RustDeskExeCandidates) {
    try {
      $output = & $candidate --get-id 2>$null | Select-Object -First 1
      $peerId = [string]$output
      if (![string]::IsNullOrWhiteSpace($peerId)) {
        return $peerId.Trim()
      }
    } catch {
      Write-CompanionLog "RustDesk ID read failed from ${candidate}: $($_.Exception.Message)"
    }
  }
  return ''
}

function New-Label {
  param([string]$Text, [int]$X, [int]$Y, [int]$W = 120)
  $label = New-Object System.Windows.Forms.Label
  $label.Text = $Text
  $label.Location = New-Object System.Drawing.Point -ArgumentList $X, $Y
  $label.Size = New-Object System.Drawing.Size -ArgumentList $W, 20
  return $label
}

function New-TextBox {
  param([int]$X, [int]$Y, [int]$W, [string]$Text = '', [switch]$Password)
  $box = New-Object System.Windows.Forms.TextBox
  $box.Location = New-Object System.Drawing.Point -ArgumentList $X, $Y
  $box.Size = New-Object System.Drawing.Size -ArgumentList $W, 22
  $box.Text = $Text
  if ($Password) {
    $box.UseSystemPasswordChar = $true
  }
  return $box
}

function Format-SessionDuration {
  param([object]$Seconds)
  [int]$value = 0
  if ($null -ne $Seconds) {
    [void][int]::TryParse([string]$Seconds, [ref]$value)
  }
  $minutes = [Math]::Ceiling([Math]::Max(0, $value) / 60)
  if ($minutes -le 1) {
    return '1 min'
  }
  return "$minutes min"
}

function Get-AthensTimeZone {
  foreach ($zoneId in @('GTB Standard Time', 'Europe/Athens')) {
    try {
      return [System.TimeZoneInfo]::FindSystemTimeZoneById($zoneId)
    } catch {
    }
  }
  return $null
}

function Format-SessionTime {
  param([object]$Value)
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return ''
  }
  try {
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $date = [DateTimeOffset]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles)
    $athensTimeZone = Get-AthensTimeZone
    if ($null -ne $athensTimeZone) {
      return ([System.TimeZoneInfo]::ConvertTime($date, $athensTimeZone)).ToString('HH:mm')
    }
    return $date.ToLocalTime().ToString('HH:mm')
  } catch {
    return ''
  }
}

function Show-PairDialog {
  param([hashtable]$Defaults = $null)

  $defaultApiBaseUrl = $ApiBaseUrl
  $defaultEmail = ''
  $defaultPeerId = Get-RustDeskPeerId
  if ($null -ne $Defaults) {
    if (![string]::IsNullOrWhiteSpace([string]$Defaults.ApiBaseUrl)) {
      $defaultApiBaseUrl = [string]$Defaults.ApiBaseUrl
    }
    if (![string]::IsNullOrWhiteSpace([string]$Defaults.TechnicianEmail)) {
      $defaultEmail = [string]$Defaults.TechnicianEmail
    }
    if (![string]::IsNullOrWhiteSpace([string]$Defaults.RustDeskPeerId)) {
      $defaultPeerId = [string]$Defaults.RustDeskPeerId
    }
  }

  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'Pair Exantas RustDesk Companion'
  $form.Size = New-Object System.Drawing.Size -ArgumentList 520, 275
  $form.StartPosition = 'CenterScreen'
  $form.FormBorderStyle = 'FixedDialog'
  $form.MaximizeBox = $false
  $form.MinimizeBox = $false

  $apiBox = New-TextBox 150 20 320 $defaultApiBaseUrl
  $emailBox = New-TextBox 150 55 320 $defaultEmail
  $passwordBox = New-TextBox 150 90 320 '' -Password
  $peerBox = New-TextBox 150 125 320 $defaultPeerId

  $form.Controls.Add((New-Label 'Office API URL' 20 22))
  $form.Controls.Add($apiBox)
  $form.Controls.Add((New-Label 'Office email' 20 57))
  $form.Controls.Add($emailBox)
  $form.Controls.Add((New-Label 'Office password' 20 92))
  $form.Controls.Add($passwordBox)
  $form.Controls.Add((New-Label 'RustDesk peer ID' 20 127))
  $form.Controls.Add($peerBox)

  $hint = New-Object System.Windows.Forms.Label
  $hint.Text = 'The Office password is used once for pairing and is not stored.'
  $hint.Location = New-Object System.Drawing.Point -ArgumentList 20, 162
  $hint.Size = New-Object System.Drawing.Size -ArgumentList 450, 20
  $form.Controls.Add($hint)

  $ok = New-Object System.Windows.Forms.Button
  $ok.Text = 'Pair'
  $ok.Location = New-Object System.Drawing.Point -ArgumentList 300, 195
  $ok.Size = New-Object System.Drawing.Size -ArgumentList 80, 28
  $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $form.AcceptButton = $ok
  $form.Controls.Add($ok)

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = 'Cancel'
  $cancel.Location = New-Object System.Drawing.Point -ArgumentList 390, 195
  $cancel.Size = New-Object System.Drawing.Size -ArgumentList 80, 28
  $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $form.CancelButton = $cancel
  $form.Controls.Add($cancel)

  if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    return $null
  }

  return @{
    ApiBaseUrl = $apiBox.Text.Trim().TrimEnd('/')
    Email = $emailBox.Text.Trim()
    Password = $passwordBox.Text
    RustDeskPeerId = $peerBox.Text.Trim()
  }
}

function Pair-Companion {
  $pairDefaults = $script:CompanionConfig
  if ($null -eq $pairDefaults) {
    try {
      $pairDefaults = Read-CompanionConfig
    } catch {
      $pairDefaults = $null
    }
  }

  while ($true) {
    $pairInput = Show-PairDialog -Defaults $pairDefaults
    if ($null -eq $pairInput) {
      throw 'Pairing cancelled.'
    }
    if ([string]::IsNullOrWhiteSpace($pairInput.ApiBaseUrl) -or
        [string]::IsNullOrWhiteSpace($pairInput.Email) -or
        [string]::IsNullOrWhiteSpace($pairInput.Password) -or
        [string]::IsNullOrWhiteSpace($pairInput.RustDeskPeerId)) {
      [System.Windows.Forms.MessageBox]::Show('Fill API URL, email, password, and RustDesk peer ID.', 'Pairing') | Out-Null
      continue
    }

    try {
      $script:ApiBaseUrl = $pairInput.ApiBaseUrl
      $login = Invoke-OfficeApi -Method 'POST' -Path '/admin/auth/login' -Body @{
        email = $pairInput.Email
        password = $pairInput.Password
      }
      $pairResult = Invoke-OfficeApi -Method 'POST' -Path '/rustdesk-companion/pair' -Body @{
        office_access_token = $login.access_token
        rustdesk_peer_id = $pairInput.RustDeskPeerId
        device_name = $env:COMPUTERNAME
        windows_user = "$env:USERDOMAIN\$env:USERNAME"
      }
      $officeUserId = [string](Get-DecisionValue -Decision $pairResult -Name 'office_user_id')
      $pairingId = [string](Get-DecisionValue -Decision $pairResult.device -Name 'id')
      if ([string]::IsNullOrWhiteSpace($officeUserId) -or [string]::IsNullOrWhiteSpace($pairingId)) {
        throw 'Pairing response omitted the stable Office user or pairing identity.'
      }
      Save-CompanionConfig -Token $pairResult.token -RustDeskPeerId $pairInput.RustDeskPeerId `
        -OfficeUserId $officeUserId -PairingId $pairingId `
        -TechnicianName $pairResult.technician_name -TechnicianEmail $pairInput.Email
      [System.Windows.Forms.MessageBox]::Show('Pairing completed.', 'Exantas RustDesk Companion') | Out-Null
      return Read-CompanionConfig
    } catch {
      Write-CompanionLog "Pairing failed: $($_.Exception.Message)"
      [System.Windows.Forms.MessageBox]::Show("Pairing failed.`r`n$($_.Exception.Message)", 'Exantas RustDesk Companion') | Out-Null
    }
  }
}

function Copy-InstalledScript {
  $source = $PSCommandPath
  if (![string]::Equals($source, $InstalledScriptPath, [StringComparison]::OrdinalIgnoreCase)) {
    Copy-Item -Path $source -Destination $InstalledScriptPath -Force
  }
}

function Get-LaunchArguments {
  param([switch]$ForWatchdog)
  $arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$InstalledScriptPath`" -ApiBaseUrl `"$ApiBaseUrl`" -PollSeconds $PollSeconds"
  if ($ForWatchdog) {
    return "$arguments -Watchdog"
  }
  return $arguments
}

function Start-CompanionRuntimeHidden {
  Copy-InstalledScript
  $powerShellPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Start-Process -FilePath $powerShellPath -ArgumentList (Get-LaunchArguments) -WorkingDirectory $AppDir -WindowStyle Hidden | Out-Null
}

function Test-CompanionRuntimeProcess {
  try {
    $processes = Get-CimInstance Win32_Process -Filter "name='powershell.exe' or name='pwsh.exe'" -ErrorAction Stop
  } catch {
    return $false
  }
  foreach ($process in $processes) {
    $commandLine = [string]$process.CommandLine
    if ($process.ProcessId -ne $PID -and
        $commandLine -like '*technician-companion.ps1*' -and
        $commandLine -notlike '*-Watchdog*') {
      return $true
    }
  }
  return $false
}

function Start-WatchdogLoop {
  Write-CompanionLog "Companion watchdog $CompanionVersion started."
  while ($true) {
    try {
      if (!(Test-CompanionRuntimeProcess)) {
        Write-CompanionLog 'Companion watchdog starting runtime.'
        Start-CompanionRuntimeHidden
      }
    } catch {
      Write-CompanionLog "Companion watchdog failed: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 30
  }
}

function Restart-Companion {
  Start-CompanionRuntimeHidden
  Write-CompanionLog 'Companion restart requested from tray menu.'
  $script:ShouldExit = $true
}

function Install-StartupShortcut {
  Copy-InstalledScript

  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($StartupShortcutPath)
  $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $shortcut.Arguments = Get-LaunchArguments
  $shortcut.WorkingDirectory = $AppDir
  $shortcut.IconLocation = Join-Path $env:WINDIR 'System32\shell32.dll,44'
  $shortcut.Save()
}

function Install-UserLogonTask {
  Copy-InstalledScript
  if (Test-Path $StartupShortcutPath) {
    Remove-Item -Path $StartupShortcutPath -Force
  }

  if (!(Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    Write-CompanionLog 'Scheduled Tasks module unavailable. Falling back to Startup shortcut.'
    Install-StartupShortcut
    return
  }

  $powerShellPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $action = New-ScheduledTaskAction -Execute $powerShellPath -Argument (Get-LaunchArguments) -WorkingDirectory $AppDir
  $watchdogAction = New-ScheduledTaskAction -Execute $powerShellPath -Argument (Get-LaunchArguments -ForWatchdog) -WorkingDirectory $AppDir
  $userId = "$env:USERDOMAIN\$env:USERNAME"
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
  $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

  try {
    Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Starts the Exantas RustDesk Companion user app hidden at logon.' -Force | Out-Null
    Register-ScheduledTask -TaskName $WatchdogTaskName -TaskPath $TaskPath -Action $watchdogAction -Trigger $trigger -Principal $principal -Settings $settings -Description 'Restarts the Exantas RustDesk Companion user app if it exits.' -Force | Out-Null
    Write-CompanionLog "Installed user logon task $TaskPath$TaskName."
  } catch {
    Write-CompanionLog "Scheduled task install failed: $($_.Exception.Message). Falling back to Startup shortcut."
    Install-StartupShortcut
  }
}

function Uninstall-StartupShortcut {
  if (Test-Path $StartupShortcutPath) {
    Remove-Item -Path $StartupShortcutPath -Force
  }
}

function Uninstall-UserLogonTask {
  if (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue) {
    try {
      Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction SilentlyContinue
      Unregister-ScheduledTask -TaskName $WatchdogTaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction SilentlyContinue
    } catch {
      Write-CompanionLog "Scheduled task removal failed: $($_.Exception.Message)"
    }
  }
  Uninstall-StartupShortcut
}

function Show-CommentDialog {
  param([object]$Session)

  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'RustDesk session notes'
  $form.Size = New-Object System.Drawing.Size -ArgumentList 560, 390
  $form.StartPosition = 'CenterScreen'
  $form.TopMost = $true
  $form.FormBorderStyle = 'FixedDialog'
  $form.MaximizeBox = $false
  $form.MinimizeBox = $false

  $customer = [string]$Session.customer_name
  if ([string]::IsNullOrWhiteSpace($customer)) {
    $customer = 'Unknown customer'
  }
  $peer = [string]$Session.peer_name
  if ([string]::IsNullOrWhiteSpace($peer)) {
    $peer = [string]$Session.peer_id
  }
  $duration = Format-SessionDuration $Session.duration_seconds
  $startedAt = Format-SessionTime $Session.started_at
  $endedAt = Format-SessionTime $Session.ended_at
  $timeRange = ''
  if ($startedAt -and $endedAt) {
    $timeRange = "    $startedAt-$endedAt"
  }

  $title = New-Object System.Windows.Forms.Label
  $title.Text = $customer
  $title.Font = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 11, ([System.Drawing.FontStyle]::Bold)
  $title.Location = New-Object System.Drawing.Point -ArgumentList 18, 18
  $title.Size = New-Object System.Drawing.Size -ArgumentList 500, 24
  $form.Controls.Add($title)

  $meta = New-Object System.Windows.Forms.Label
  $meta.Text = "Device: $peer    Duration: $duration$timeRange"
  $meta.Location = New-Object System.Drawing.Point -ArgumentList 18, 48
  $meta.Size = New-Object System.Drawing.Size -ArgumentList 500, 20
  $form.Controls.Add($meta)

  $help = New-Object System.Windows.Forms.Label
  $help.Text = 'Save sends the text. Plain text or ~ closes and emails. # keeps pending. - does nothing.'
  $help.Location = New-Object System.Drawing.Point -ArgumentList 18, 78
  $help.Size = New-Object System.Drawing.Size -ArgumentList 500, 20
  $form.Controls.Add($help)

  $text = New-Object System.Windows.Forms.TextBox
  $text.Multiline = $true
  $text.ScrollBars = 'Vertical'
  $text.AcceptsReturn = $true
  $text.Location = New-Object System.Drawing.Point -ArgumentList 20, 105
  $text.Size = New-Object System.Drawing.Size -ArgumentList 500, 170
  $form.Controls.Add($text)

  $save = New-Object System.Windows.Forms.Button
  $save.Text = 'Save'
  $save.Location = New-Object System.Drawing.Point -ArgumentList 440, 295
  $save.Size = New-Object System.Drawing.Size -ArgumentList 80, 30
  $save.Add_Click({
    if ([string]::IsNullOrWhiteSpace($text.Text)) {
      [System.Windows.Forms.MessageBox]::Show('Write a comment. Use - if no action is needed.', 'RustDesk session notes') | Out-Null
      return
    }
    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Close()
  })
  $form.Controls.Add($save)

  $form.AcceptButton = $save
  [void]$text.Focus()

  $dialogResult = $form.ShowDialog()
  if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
    return [pscustomobject]@{ Action = 'save'; Comment = $text.Text.Trim() }
  }
  if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Cancel) {
    return [pscustomobject]@{ Action = 'later'; Comment = '' }
  }
  return $null
}

function Submit-SessionComment {
  param(
    [object]$Session,
    [string]$Comment,
    [string]$Token,
    [string]$IdempotencyKey = $null
  )
  $encodedId = [Uri]::EscapeDataString([string]$Session.id)
  $body = @{
    comment = $Comment
  }
  if (![string]::IsNullOrWhiteSpace($IdempotencyKey)) {
    $body.idempotency_key = $IdempotencyKey
  }
  return Invoke-OfficeApi -Method 'POST' -Path "/rustdesk-companion/sessions/$encodedId/comment" -Token $Token -Body $body
}

function Sync-RustDeskSessions {
  param([string]$Token)
  return Invoke-OfficeApi -Method 'POST' -Path '/rustdesk-companion/sessions/sync' -Token $Token -Body @{}
}

function Flush-OfflineQueue {
  param(
    [string]$Token,
    [object[]]$Sessions = @()
  )

  $items = @(Read-OfflineQueue)
  if ($items.Count -eq 0) {
    return
  }

  $workflowV2 = $false
  try {
    $workflowV2 = Test-OfficeWorkflowV2 -Token $Token
  } catch {
    Write-CompanionLog 'Workflow capability check failed; offline comments remain queued.'
    return
  }

  $remaining = New-Object System.Collections.Generic.List[object]
  foreach ($item in $items) {
    $queuedSource = [pscustomobject]@{
      id = [string]$item.session_id
      peer_id = [string]$item.peer_id
      rustdesk_session_id = Get-DecisionValue -Decision $item -Name 'rustdesk_session_id'
    }
    if (Test-V2WorkflowSuppressed -Session $queuedSource) {
      $item | Add-Member -NotePropertyName workflow_review -NotePropertyValue 'v2_suppressed' -Force
      $remaining.Add($item)
      continue
    }
    if (![string]::IsNullOrWhiteSpace((Get-DecisionValue -Decision $item -Name 'workflow_review'))) {
      $remaining.Add($item)
      continue
    }
    try {
      $session = [pscustomobject]@{ id = [string]$item.session_id }
      if ($workflowV2) {
        $matches = @($Sessions | Where-Object { [string]$_.id -eq [string]$item.session_id })
        if ($matches.Count -ne 1) {
          # An old queue row without a current authoritative source match stays
          # byte-for-byte unchanged; do not guess whether it belongs to v2.
          $remaining.Add($item)
          continue
        }
        $context = Get-OfficeWorkContext -Session $matches[0] -Token $Token
        if ($context.suppress_legacy -eq $true) {
          Add-V2WorkflowSuppression -Session $matches[0] -Context $context
          $item | Add-Member -NotePropertyName workflow_review -NotePropertyValue ([string]$context.classification) -Force
          $remaining.Add($item)
          Write-CompanionLog 'An existing offline comment is held for Office review and was withheld from the legacy endpoint.'
          continue
        }
      }
      $comment = Unprotect-Text ([string]$item.protected_comment)
      [void](Submit-SessionComment -Session $session -Comment $comment -Token $Token -IdempotencyKey ([string]$item.idempotency_key))
      Write-CompanionLog "Flushed offline comment for session $($item.session_id)."
    } catch {
      if ($workflowV2) {
        $remaining.Add($item)
        Write-CompanionLog 'Workflow-aware offline sync failed; the encrypted comment remains queued.'
        continue
      }
      if (!(Should-QueueSubmissionFailure -Message $_.Exception.Message)) {
        Write-CompanionLog "Dropping offline comment for session $($item.session_id): $($_.Exception.Message)"
        continue
      }
      $attempts = 0
      if ($item.PSObject.Properties['attempts']) {
        [void][int]::TryParse([string]$item.attempts, [ref]$attempts)
      }
      $remaining.Add([pscustomobject]@{
        session_id = [string]$item.session_id
        customer_name = [string]$item.customer_name
        peer_id = [string]$item.peer_id
        idempotency_key = [string]$item.idempotency_key
        protected_comment = [string]$item.protected_comment
        attempts = $attempts + 1
        last_error = $_.Exception.Message
        created_at = [string]$item.created_at
      })
      Write-CompanionLog "Offline queue flush failed for session $($item.session_id): $($_.Exception.Message)"
    }
  }

  Save-OfflineQueue -Items $remaining.ToArray()
}

function Format-PendingSessionListItem {
  param([object]$Session)
  $customer = [string]$Session.customer_name
  if ([string]::IsNullOrWhiteSpace($customer)) {
    $customer = 'Unknown customer'
  }
  $peer = [string]$Session.peer_name
  if ([string]::IsNullOrWhiteSpace($peer)) {
    $peer = [string]$Session.peer_id
  }
  $duration = Format-SessionDuration $Session.duration_seconds
  $endedAt = Format-SessionTime $Session.ended_at
  if (![string]::IsNullOrWhiteSpace($endedAt)) {
    return "$customer | $peer | $duration | $endedAt"
  }
  return "$customer | $peer | $duration"
}

function Show-PendingListDialog {
  $sessions = @($script:PendingSessions)
  if ($sessions.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show('No pending RustDesk sessions.', 'Exantas RustDesk Companion') | Out-Null
    return $null
  }

  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'Pending RustDesk sessions'
  $form.Size = New-Object System.Drawing.Size -ArgumentList 640, 360
  $form.StartPosition = 'CenterScreen'
  $form.FormBorderStyle = 'FixedDialog'
  $form.MaximizeBox = $false
  $form.MinimizeBox = $false

  $list = New-Object System.Windows.Forms.ListBox
  $list.Location = New-Object System.Drawing.Point -ArgumentList 18, 18
  $list.Size = New-Object System.Drawing.Size -ArgumentList 590, 245
  foreach ($session in $sessions) {
    [void]$list.Items.Add((Format-PendingSessionListItem -Session $session))
  }
  if ($list.Items.Count -gt 0) {
    $list.SelectedIndex = 0
  }
  $form.Controls.Add($list)

  $open = New-Object System.Windows.Forms.Button
  $open.Text = 'Open'
  $open.Location = New-Object System.Drawing.Point -ArgumentList 438, 280
  $open.Size = New-Object System.Drawing.Size -ArgumentList 80, 30
  $open.Add_Click({
    if ($list.SelectedIndex -lt 0) {
      return
    }
    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Close()
  })
  $form.Controls.Add($open)

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = 'Close'
  $cancel.Location = New-Object System.Drawing.Point -ArgumentList 528, 280
  $cancel.Size = New-Object System.Drawing.Size -ArgumentList 80, 30
  $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $form.CancelButton = $cancel
  $form.Controls.Add($cancel)
  $form.AcceptButton = $open

  if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $list.SelectedIndex -ge 0) {
    return $sessions[$list.SelectedIndex]
  }
  return $null
}

function Handle-SessionDecision {
  param([object]$Session)

  $sessionId = [string]$Session.id
  if (Test-OfficeWorkflowV2 -Token $script:CompanionConfig.CompanionToken) {
    $context = Get-OfficeWorkContext -Session $Session -Token $script:CompanionConfig.CompanionToken
    if ($context.suppress_legacy) {
      Add-V2WorkflowSuppression -Session $Session -Context $context
      [void]$script:SnoozedSessionIds.Add($sessionId)
      Write-CompanionLog "Office workflow v2 owns this session context ($($context.classification)); legacy report dialog skipped."
      return
    }
  }
  $decision = Show-CommentDialog -Session $Session
  if ($null -eq $decision) {
    [void]$script:SnoozedSessionIds.Add($sessionId)
    return
  }

  $decisionAction = Get-DecisionValue -Decision $decision -Name 'Action'
  if ($decisionAction -eq 'later') {
    [void]$script:SnoozedSessionIds.Add($sessionId)
    return
  }

  if ($decisionAction -ne 'save') {
    Write-CompanionLog "Session popup returned unknown action for ${sessionId}: $decisionAction"
    return
  }

  $decisionComment = Get-DecisionValue -Decision $decision -Name 'Comment'
  $idempotencyKey = Get-CommentIdempotencyKey -Session $Session -Comment $decisionComment
  try {
    Write-CompanionLog "Submitting session comment for ${sessionId}."
    [void](Submit-SessionComment -Session $Session -Comment $decisionComment -Token $script:CompanionConfig.CompanionToken -IdempotencyKey $idempotencyKey)
    Write-CompanionLog "Submitted session comment for ${sessionId}."
    $script:SnoozedSessionIds.Remove($sessionId) | Out-Null
  } catch {
    $message = $_.Exception.Message
    if (Should-QueueSubmissionFailure -Message $message) {
      Add-OfflineComment -Session $Session -Comment $decisionComment -IdempotencyKey $idempotencyKey -LastError $message
      [void]$script:SnoozedSessionIds.Add($sessionId)
      return
    }
    throw
  }
}

function Get-WebSocketUrl {
  $base = $ApiBaseUrl.TrimEnd('/')
  if ($base.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
    $base = 'wss://' + $base.Substring(8)
  } elseif ($base.StartsWith('http://', [StringComparison]::OrdinalIgnoreCase)) {
    $base = 'ws://' + $base.Substring(7)
  }
  return "$base/rustdesk-companion/ws"
}

function Start-WebSocketListener {
  param([string]$Token)
  if ($null -ne $script:WebSocketPowerShell) {
    return
  }

  $webSocketUrl = Get-WebSocketUrl
  $scriptBlock = {
    param(
      [string]$Url,
      [string]$Token,
      [string]$SignalPath,
      [string]$LogPath
    )

    function Write-BackgroundLog {
      param([string]$Message)
      $timestamp = (Get-Date).ToString('s')
      Add-Content -Path $LogPath -Value "[$timestamp] $Message"
    }

    while ($true) {
      $client = $null
      try {
        $client = New-Object System.Net.WebSockets.ClientWebSocket
        $client.Options.SetRequestHeader('Authorization', "Bearer $Token")
        $client.ConnectAsync([Uri]$Url, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        Write-BackgroundLog "WebSocket connected to $Url."

        $buffer = New-Object byte[] 4096
        while ($client.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
          $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (,$buffer)
          $result = $client.ReceiveAsync($segment, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
          if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            break
          }
          (Get-Date).ToUniversalTime().ToString('o') | Set-Content -Path $SignalPath -Encoding ASCII
        }
      } catch {
        Write-BackgroundLog "WebSocket listener failed: $($_.Exception.Message)"
      } finally {
        if ($null -ne $client) {
          $client.Dispose()
        }
      }
      Start-Sleep -Seconds 10
    }
  }

  $script:WebSocketPowerShell = [powershell]::Create()
  [void]$script:WebSocketPowerShell.AddScript($scriptBlock).AddArgument($webSocketUrl).AddArgument($Token).AddArgument($WebSocketSignalPath).AddArgument($LogPath)
  $script:WebSocketAsyncResult = $script:WebSocketPowerShell.BeginInvoke()
}

function Stop-WebSocketListener {
  if ($null -eq $script:WebSocketPowerShell) {
    return
  }
  try {
    $script:WebSocketPowerShell.Stop()
  } catch {
  }
  try {
    $script:WebSocketPowerShell.Dispose()
  } catch {
  }
  $script:WebSocketPowerShell = $null
  $script:WebSocketAsyncResult = $null
}

function Test-WebSocketSignal {
  if (!(Test-Path $WebSocketSignalPath)) {
    return $false
  }
  try {
    $text = (Get-Content -Path $WebSocketSignalPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
      return $false
    }
    $signalUtc = ([DateTime]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)).ToUniversalTime()
    if ($signalUtc -gt $script:LastWebSocketSignalUtc) {
      $script:LastWebSocketSignalUtc = $signalUtc
      return $true
    }
  } catch {
    Write-CompanionLog "WebSocket signal read failed: $($_.Exception.Message)"
  }
  return $false
}

function New-NotifyIcon {
  $notify = New-Object System.Windows.Forms.NotifyIcon
  $notify.Icon = [System.Drawing.SystemIcons]::Application
  $notify.Text = 'Exantas RustDesk Companion'
  $notify.Visible = $true

  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  $syncNow = $menu.Items.Add('Sync now')
  $syncNow.Add_Click({
    $script:SnoozedSessionIds.Clear()
    $script:ForcePoll = $true
  })
  $pendingList = $menu.Items.Add('Pending sessions')
  $pendingList.Add_Click({
    try {
      $session = Show-PendingListDialog
      if ($null -ne $session) {
        Handle-SessionDecision -Session $session
        $script:ForcePoll = $true
      }
    } catch {
      Write-CompanionLog "Pending list action failed: $($_.Exception.Message)"
      [System.Windows.Forms.MessageBox]::Show("Pending action failed.`r`n$($_.Exception.Message)", 'Exantas RustDesk Companion') | Out-Null
    }
  })
  [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
  $pairAgain = $menu.Items.Add('Pair again')
  $pairAgain.Add_Click({
    try {
      $script:CompanionConfig = Pair-Companion
      $script:ForcePoll = $true
    } catch {
      [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Exantas RustDesk Companion') | Out-Null
    }
  })
  $restart = $menu.Items.Add('Restart')
  $restart.Add_Click({
    try {
      Restart-Companion
    } catch {
      Write-CompanionLog "Tray restart failed: $($_.Exception.Message)"
      [System.Windows.Forms.MessageBox]::Show("Restart failed.`r`n$($_.Exception.Message)", 'Exantas RustDesk Companion') | Out-Null
    }
  })
  $openLog = $menu.Items.Add('Open log')
  $openLog.Add_Click({
    try {
      if (!(Test-Path $LogPath)) {
        New-Item -ItemType File -Path $LogPath -Force | Out-Null
      }
      Start-Process -FilePath $LogPath | Out-Null
    } catch {
      [System.Windows.Forms.MessageBox]::Show("Open log failed.`r`n$($_.Exception.Message)", 'Exantas RustDesk Companion') | Out-Null
    }
  })
  [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
  $exit = $menu.Items.Add('Exit')
  $exit.Add_Click({ $script:ShouldExit = $true })
  $notify.ContextMenuStrip = $menu
  return $notify
}

function Update-NotifyText {
  param(
    [System.Windows.Forms.NotifyIcon]$NotifyIcon,
    [int]$PendingCount,
    [int]$QueuedCount = 0
  )
  if ($QueuedCount -gt 0) {
    $text = "Exantas RustDesk Companion - $PendingCount pending, $QueuedCount queued"
  } else {
    $text = "Exantas RustDesk Companion - $PendingCount pending"
  }
  if ($text.Length -gt 63) {
    $text = $text.Substring(0, 63)
  }
  $NotifyIcon.Text = $text
}

if ($UninstallStartup) {
  Uninstall-UserLogonTask
  [System.Windows.Forms.MessageBox]::Show('Startup entry removed.', 'Exantas RustDesk Companion') | Out-Null
  exit 0
}

if ($InstallStartup) {
  Install-UserLogonTask
}

if ($Watchdog) {
  Start-WatchdogLoop
  exit 0
}

if (!$InstallOnly) {
  Start-SingleInstanceGuard
}

try {
  $config = Read-CompanionConfig
} catch {
  Write-CompanionLog "Config read failed: $($_.Exception.Message)"
  $config = $null
}

if ($Pair -or $null -eq $config) {
  $config = Pair-Companion
}

if ($InstallOnly) {
  Write-CompanionLog 'Companion installed. Runtime start skipped because InstallOnly was set.'
  exit 0
}

$script:CompanionConfig = $config
$ApiBaseUrl = $script:CompanionConfig.ApiBaseUrl
$notifyIcon = New-NotifyIcon
Write-CompanionLog "Companion $CompanionVersion started for peer $($script:CompanionConfig.RustDeskPeerId)."
Start-WebSocketListener -Token $script:CompanionConfig.CompanionToken

try {
  while (!$script:ShouldExit) {
    try {
      $script:PendingSessions = @()
      try {
        [void](Sync-RustDeskSessions -Token $script:CompanionConfig.CompanionToken)
      } catch {
        Write-CompanionLog "RustDesk audit sync request failed: $($_.Exception.Message)"
      }

      $pending = Invoke-OfficeApi -Method 'GET' -Path '/rustdesk-companion/sessions/pending' -Token $script:CompanionConfig.CompanionToken
      $sourceItems = @($pending.items)
      $items = $sourceItems
      $workflowV2 = Test-OfficeWorkflowV2 -Token $script:CompanionConfig.CompanionToken
      if ($workflowV2) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($sourceSession in $sourceItems) {
          $context = Get-OfficeWorkContext -Session $sourceSession -Token $script:CompanionConfig.CompanionToken
          if ($context.suppress_legacy) {
            Add-V2WorkflowSuppression -Session $sourceSession -Context $context
          }
          if (!$context.suppress_legacy -and !(Test-V2WorkflowSuppressed -Session $sourceSession)) {
            $items.Add($sourceSession)
          }
        }
        $items = $items.ToArray()
      } else {
        $items = @($sourceItems | Where-Object { !(Test-V2WorkflowSuppressed -Session $_) })
      }
      $script:PendingSessions = $items
      Flush-OfflineQueue -Token $script:CompanionConfig.CompanionToken -Sessions $sourceItems
      Update-NotifyText -NotifyIcon $notifyIcon -PendingCount $items.Count -QueuedCount (Get-OfflineQueueCount)

      foreach ($session in $items) {
        if ($script:ShouldExit) {
          break
        }
        $sessionId = [string]$session.id
        if ($script:SnoozedSessionIds.Contains($sessionId)) {
          continue
        }

        try {
          Handle-SessionDecision -Session $session
        } catch {
          Write-CompanionLog "Session popup failed for ${sessionId}: $($_.Exception.Message)"
          $notifyIcon.Text = 'Exantas RustDesk Companion - action error'
        }
        break
      }
    } catch {
      Write-CompanionLog "Poll failed: $($_.Exception.Message)"
      $notifyIcon.Text = 'Exantas RustDesk Companion - API error'
    }

    $script:ForcePoll = $false
    for ($i = 0; $i -lt ($PollSeconds * 10); $i++) {
      if ($script:ShouldExit -or $script:ForcePoll) {
        break
      }
      if (Test-WebSocketSignal) {
        $script:ForcePoll = $true
        break
      }
      [System.Windows.Forms.Application]::DoEvents()
      Start-Sleep -Milliseconds 100
    }
  }
} finally {
  Stop-WebSocketListener
  $notifyIcon.Visible = $false
  $notifyIcon.Dispose()
  Stop-SingleInstanceGuard
  Write-CompanionLog 'Companion stopped.'
}
