$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$sourcePath = Join-Path $PSScriptRoot '..\technician-companion.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "Companion PowerShell syntax failed: $($parseErrors[0].Message)" }

$requiredFunctions = @(
  'Get-DecisionValue', 'Protect-Text', 'Unprotect-Text',
  'Get-CanonicalOfficeApiBaseUrl', 'Get-V2WorkflowSuppressionScope',
  'Set-V2WorkflowSuppressionScopeFromCapabilities', 'Test-V2WorkflowMarkerScope', 'Read-V2WorkflowSuppressions',
  'Save-V2WorkflowSuppressions', 'Add-V2WorkflowSuppression',
  'Test-V2WorkflowSuppressed', 'Flush-OfflineQueue'
)
$definitions = @($ast.FindAll({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $requiredFunctions -contains $node.Name
}, $true))
if ($definitions.Count -ne $requiredFunctions.Count) {
  throw 'The suppression test could not locate every production function.'
}
Invoke-Expression (($definitions | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine)

function Write-CompanionLog {
  param([string]$Message)
  $script:LastCompanionLog = $Message
}

$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('exantas-workflow-suppression-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null
$script:WorkflowSuppressionPath = Join-Path $testDirectory 'workflow-v2-suppression.dpapi'
$script:ApiBaseUrl = 'HTTPS://Office.Example.test:443/api/v1/'
$script:CompanionConfig = @{
  ApiBaseUrl = 'HTTPS://Office.Example.test:443/api/v1/'
  CompanionToken = 'synthetic-companion-token'
  OfficeUserId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  PairingId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  RustDeskPeerId = 'local-peer-a'
}
$script:LogPath = Join-Path $testDirectory 'test.log'

function Assert-Equal {
  param([object]$Expected, [object]$Actual, [string]$Message)
  if ($Expected -cne $Actual) { throw "$Message (expected '$Expected', got '$Actual')" }
}

function Assert-Throws {
  param([scriptblock]$Action, [string]$Message)
  try { & $Action } catch { return }
  throw $Message
}

function Assert-True {
  param([bool]$Value, [string]$Message)
  if (!$Value) { throw $Message }
}

try {
  Assert-Equal 'synthetic-dpapi-roundtrip' (Unprotect-Text (Protect-Text 'synthetic-dpapi-roundtrip')) 'DPAPI round trip failed.'
  $legacyConfig = @{
    ApiBaseUrl = 'HTTPS://Office.Example.test:443/api/v1/'
    CompanionToken = 'synthetic-companion-token'
    RustDeskPeerId = 'local-peer-a'
    OfficeUserId = ''
    PairingId = ''
  }
  $script:CompanionConfig = $legacyConfig
  $capabilities = [pscustomobject]@{
    office_user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    pairing_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  }
  $changed = Set-V2WorkflowSuppressionScopeFromCapabilities -Capabilities $capabilities `
    -ExpectedApiBaseUrl 'https://office.example.test/api/v1' -ExpectedToken 'synthetic-companion-token' `
    -ExpectedPeerId 'local-peer-a'
  Assert-Equal $true $changed 'A legacy config should hydrate from authenticated capability scope.'
  Assert-Equal 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $legacyConfig.OfficeUserId 'Office principal was not hydrated.'
  Assert-Equal 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $legacyConfig.PairingId 'Pairing identity was not hydrated.'
  $changed = Set-V2WorkflowSuppressionScopeFromCapabilities -Capabilities $capabilities `
    -ExpectedApiBaseUrl 'https://office.example.test/api/v1' -ExpectedToken 'synthetic-companion-token' `
    -ExpectedPeerId 'local-peer-a'
  Assert-Equal $false $changed 'An already hydrated scope should not require a config rewrite.'
  Assert-Throws {
    Set-V2WorkflowSuppressionScopeFromCapabilities -Capabilities $capabilities `
      -ExpectedApiBaseUrl 'https://another-office.example/api/v1' -ExpectedToken 'synthetic-companion-token' `
      -ExpectedPeerId 'local-peer-a'
  } 'A capability response must not hydrate after the API scope changes.'
  Assert-Throws {
    Set-V2WorkflowSuppressionScopeFromCapabilities -Capabilities $capabilities `
      -ExpectedApiBaseUrl 'https://office.example.test/api/v1' -ExpectedToken 'changed-token' `
      -ExpectedPeerId 'local-peer-a'
  } 'A capability response must not hydrate after the token changes.'
  Assert-Throws {
    Set-V2WorkflowSuppressionScopeFromCapabilities -Capabilities $capabilities `
      -ExpectedApiBaseUrl 'https://office.example.test/api/v1' -ExpectedToken 'synthetic-companion-token' `
      -ExpectedPeerId 'changed-peer'
  } 'A capability response must not hydrate after the paired peer changes.'
  Assert-Throws {
    Set-V2WorkflowSuppressionScopeFromCapabilities -Capabilities ([pscustomobject]@{}) `
      -ExpectedApiBaseUrl 'https://office.example.test/api/v1' -ExpectedToken 'synthetic-companion-token' `
      -ExpectedPeerId 'local-peer-a'
  } 'Enabled v2 with missing account/pairing IDs must fail closed.'

  $session = [pscustomobject]@{
    id = 'source-session-a'
    peer_id = 'remote-peer-a'
    rustdesk_session_id = '18446744073709551615'
  }
  $context = [pscustomobject]@{ classification = 'bound'; suppress_legacy = $true }
  Add-V2WorkflowSuppression -Session $session -Context $context

  $protectedFile = Get-Content -LiteralPath $WorkflowSuppressionPath -Raw
  $roundTripMarkerJson = Unprotect-Text $protectedFile.Trim()
  if ([string]::IsNullOrWhiteSpace($roundTripMarkerJson)) { throw 'Suppression marker DPAPI payload decoded to empty text.' }
  if ($protectedFile.Contains('aaaaaaaa-aaaa') -or $protectedFile.Contains('source-session-a')) {
    throw 'The DPAPI marker file contains readable scope/session data.'
  }
  Assert-Equal $true (Test-V2WorkflowSuppressed -Session $session) 'Same pairing should suppress the same source session.'

  $markers = @(Read-V2WorkflowSuppressions)
  $storedMarker = $markers | Where-Object { $_.session_id -eq 'source-session-a' } | Select-Object -First 1
  Assert-Equal '2' ([string]$storedMarker.workflow_contract_version) 'Marker must identify contract v2.'
  Assert-Equal 'https://office.example.test/api/v1' $storedMarker.api_base_url 'API base should be canonicalized in the marker.'
  Assert-Equal 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $storedMarker.office_user_id 'Marker must retain the stable Office principal.'
  Assert-Equal 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $storedMarker.pairing_id 'Marker must retain the current pairing identity.'
  $script:CompanionConfig.ApiBaseUrl = 'https://another-office.example/api/v1'
  $suppressed = Test-V2WorkflowSuppressed -Session $session
  Assert-Equal $false $suppressed 'A different API base must not inherit suppression.'
  $script:CompanionConfig.ApiBaseUrl = 'https://office.example.test/api/v1'
  $script:CompanionConfig.PairingId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  $suppressed = Test-V2WorkflowSuppressed -Session $session
  Assert-Equal $false $suppressed 'A different pairing ID must not inherit suppression.'
  $script:CompanionConfig.PairingId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  $markers += [pscustomobject]@{
    session_id = 'old-unscoped-session'
    peer_id = 'remote-peer-a'
    from_peer = 'local-peer-a'
    rustdesk_session_id = '123456'
    workflow_classification = 'bound'
  }
  Save-V2WorkflowSuppressions -Markers $markers
  $oldSession = [pscustomobject]@{ id = 'old-unscoped-session'; peer_id = 'remote-peer-a'; rustdesk_session_id = '123456' }
  $suppressed = Test-V2WorkflowSuppressed -Session $oldSession
  Assert-Equal $false $suppressed 'An old unscoped marker must not suppress the current account.'

  $script:ApiBaseUrl = 'https://office.example.test/api/v1'
  $script:CompanionConfig = @{
    ApiBaseUrl = 'https://office.example.test/api/v1'
    CompanionToken = 'synthetic-companion-token'
    OfficeUserId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    PairingId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
    RustDeskPeerId = 'local-peer-a'
  }
  $suppressed = Test-V2WorkflowSuppressed -Session $session
  Assert-Equal $false $suppressed 'A different Office principal/pairing must not inherit suppression.'

  $script:CompanionConfig.OfficeUserId = ''
  Assert-Throws { Add-V2WorkflowSuppression -Session $session -Context $context } 'A new marker must not be stored without stable account and pairing IDs.'
  $script:CompanionConfig.OfficeUserId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'

  $script:WorkflowQueue = @()
  $script:SavedWorkflowQueue = @()
  $script:WorkflowV2Enabled = $true
  $script:WorkflowContexts = @{}
  $script:SubmittedWorkflowComments = New-Object System.Collections.Generic.List[object]
  $script:WorkflowDecryptedCount = 0
  $script:OriginalUnprotectText = (Get-Command Unprotect-Text).ScriptBlock
  function Read-OfflineQueue { return @($script:WorkflowQueue) }
  function Save-OfflineQueue { param([object[]]$Items) $script:SavedWorkflowQueue = @($Items) }
  function Test-OfficeWorkflowV2 { param([string]$Token) return $script:WorkflowV2Enabled }
  function Get-OfficeWorkContext { param([object]$Session,[string]$Token) return $script:WorkflowContexts[[string]$Session.id] }
  function Unprotect-Text {
    param([string]$Value)
    if ($Value -in @('synthetic-protected-payload', 'source-identity-unavailable')) {
      $script:WorkflowDecryptedCount++
      return $script:LegacyCommentText
    }
    return & $script:OriginalUnprotectText $Value
  }
  function Submit-SessionComment {
    param([object]$Session,[string]$Comment,[string]$Token,[string]$IdempotencyKey)
    $script:SubmittedWorkflowComments.Add([pscustomobject]@{ session_id=$Session.id; comment=$Comment; key=$IdempotencyKey })
    return @{ action = 'final' }
  }

  foreach ($classification in @('unassigned', 'pending_identity')) {
    $sourceId = 'queued-' + $classification
    $source = [pscustomobject]@{ id=$sourceId; peer_id='remote-peer-' + $classification; rustdesk_session_id='5550001' }
    $queued = [pscustomobject]@{
      session_id=$sourceId; customer_name='Do not use'; peer_id=$source.peer_id; rustdesk_session_id='5550001'
      idempotency_key='queue-' + $classification; protected_comment='synthetic-protected-payload'; attempts=0
      created_at='2026-10-10T10:00:00Z'
    }
    $script:WorkflowQueue = @($queued)
    $script:WorkflowContexts[$sourceId] = [pscustomobject]@{ classification=$classification; suppress_legacy=$true }
    $script:SavedWorkflowQueue = @()
    $script:SubmittedWorkflowComments.Clear()
    $script:WorkflowDecryptedCount = 0
    Flush-OfflineQueue -Token 'synthetic-companion-token' -Sessions @($source)
    Assert-Equal 1 $script:SavedWorkflowQueue.Count "A v2 $classification queue row must remain held."
    Assert-Equal $classification $script:SavedWorkflowQueue[0].workflow_review "The $classification queue row needs explicit review state."
    Assert-Equal 'synthetic-protected-payload' $script:SavedWorkflowQueue[0].protected_comment "The $classification encrypted payload must be retained verbatim."
    Assert-Equal 'Do not use' $script:SavedWorkflowQueue[0].customer_name "The $classification queue's legacy customer label must not be reinterpreted."
    Assert-Equal 0 $script:SubmittedWorkflowComments.Count "A v2 $classification source must never be sent to the legacy endpoint."
    Assert-Equal 0 $script:WorkflowDecryptedCount "A held $classification payload should remain encrypted and unparsed."
  }

  $script:WorkflowV2Enabled = $false # Explicit capabilities-disabled / 404 compatibility path.
  $script:WorkflowQueue = @([pscustomobject]@{
    session_id='legacy-prefix-session'; customer_name='Legacy'; peer_id='legacy-peer'
    idempotency_key='legacy-prefix-key'; protected_comment='synthetic-protected-payload'; attempts=0
    created_at='2026-10-10T10:00:00Z'
  })
  $script:SavedWorkflowQueue = @()
  $script:SubmittedWorkflowComments.Clear()
  $script:WorkflowDecryptedCount = 0
  $script:LegacyCommentText = '~ Legacy v1 prefix remains literal'
  Flush-OfflineQueue -Token 'synthetic-companion-token'
  Assert-Equal 1 $script:SubmittedWorkflowComments.Count 'With v2 explicitly unavailable, the old queue keeps v1 delivery semantics.'
  Assert-Equal '~ Legacy v1 prefix remains literal' $script:SubmittedWorkflowComments[0].comment 'The old v1 prefix must reach the legacy endpoint unchanged.'
  Assert-Equal 0 $script:SavedWorkflowQueue.Count 'A confirmed legacy submission should remove the queued row.'

  $script:WorkflowV2Enabled = $true
  $unmatchedLegacy = [pscustomobject]@{
    session_id='queue-source-not-found'; customer_name='Legacy label'; peer_id='unknown-peer'
    idempotency_key='unmatched-key'; protected_comment='source-identity-unavailable'; attempts=0
    created_at='2026-10-10T10:00:00Z'
  }
  $script:WorkflowQueue = @($unmatchedLegacy)
  $script:SavedWorkflowQueue = @()
  $script:SubmittedWorkflowComments.Clear()
  $script:WorkflowDecryptedCount = 0
  Flush-OfflineQueue -Token 'synthetic-companion-token' -Sessions @([pscustomobject]@{ id='some-other-session'; peer_id='unknown-peer' })
  Assert-Equal 1 $script:SavedWorkflowQueue.Count 'A queue row without an authoritative source-ID match must stay held.'
  Assert-Equal 'source-identity-unavailable' $script:SavedWorkflowQueue[0].protected_comment 'An unidentified row must be preserved verbatim.'
  Assert-True (!$script:SavedWorkflowQueue[0].PSObject.Properties['workflow_review']) 'Do not guess a review classification without source identity.'
  Assert-Equal 0 $script:SubmittedWorkflowComments.Count 'An unidentified v2-era source must not fall back to the legacy endpoint.'
  Assert-Equal 0 $script:WorkflowDecryptedCount 'An unidentified source payload must remain encrypted.'

  Write-Output 'PASS: scoped suppression, offline queue quarantine, v1 compatibility, and unknown source-ID hold.'
} finally {
  Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
