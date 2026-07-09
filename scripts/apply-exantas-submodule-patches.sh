#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hbb_common="$repo_root/libs/hbb_common"
patch_file="$repo_root/patches/hbb_common-exantas-config.patch"

if [[ ! -d "$hbb_common/.git" && ! -f "$hbb_common/.git" ]]; then
  echo "libs/hbb_common is not initialized. Run: git submodule update --init --recursive"
  exit 1
fi

apply_args=(--ignore-whitespace --ignore-space-change --unidiff-zero)

if git -C "$hbb_common" apply "${apply_args[@]}" --check "$patch_file" 2>/dev/null; then
  git -C "$hbb_common" apply "${apply_args[@]}" "$patch_file"
  echo "Applied hbb_common Exantas public config patch."
  exit 0
fi

if git -C "$hbb_common" apply "${apply_args[@]}" --reverse --check "$patch_file" 2>/dev/null; then
  echo "hbb_common Exantas public config patch is already applied."
  exit 0
fi

echo "Could not apply hbb_common Exantas public config patch cleanly."
exit 1
