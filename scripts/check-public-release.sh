#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "Checking public release hygiene..."

blocked_paths="$(find . -type f \
  \( -name '*.pfx' -o -name '*.p12' -o -name '*.pem' -o -name '*.key' -o -name '*:Zone.Identifier' \) \
  -not -path './.git/*' \
  -not -path './target/*' \
  -not -path './flutter/build/*')"

if [[ -n "$blocked_paths" ]]; then
  echo "Blocked files found:"
  echo "$blocked_paths"
  exit 1
fi

secret_hits="$(rg -l -i \
  'BEGIN (RSA|OPENSSH|PRIVATE) KEY|DATABASE_URL\s*=|AUTH[_-]?SECRET\s*=|WEBHOOK[_-]?SECRET\s*=|SIGNING[_-]?KEY\s*=|EXANTAS_OFFICE_API_TOKEN\s*=|OFFICE_ADMIN|exantas@' \
  --glob '!target/**' \
  --glob '!flutter/build/**' \
  --glob '!.git/**' \
  --glob '!docs/**' \
  --glob '!README.md' \
  --glob '!SECURITY.md' \
  --glob '!BUILDING.md' \
  --glob '!scripts/check-public-release.sh' \
  . || true)"

if [[ -n "$secret_hits" ]]; then
  echo "Potential secret-bearing files need manual review:"
  echo "$secret_hits"
  exit 1
fi

if rg -n 'use-permanent-password|HARD_SETTINGS.*password|ExantasSupportPresetSalt|00[A-Za-z0-9+/=]{20,}' src/common.rs; then
  echo "Unsafe unattended credential defaults found in src/common.rs"
  exit 1
fi

if ! rg -q 'https://github.com/2bitegr/rd-cl' flutter src README.md docs BUILDING.md SECURITY.md; then
  echo "Source-code link was not found."
  exit 1
fi

echo "Public release hygiene checks passed."
