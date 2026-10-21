#requires -Version 7.4
# Compatibility entrypoint: cloud and manual Windows builds use the same implementation.
[CmdletBinding()]
param(
  [string]$SourceDir = (Split-Path -Parent $PSScriptRoot),
  [string]$BuildBase,
  [string]$ToolsRoot,
  [string]$VcpkgRoot,
  [ValidatePattern('^$|^[0-9a-fA-F]{40}$')][string]$ExpectedCommit = '',
  [switch]$ValidateOnly
)
& (Join-Path $PSScriptRoot 'windows-cloud-build.ps1') @PSBoundParameters
