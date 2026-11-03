#!/usr/bin/env bash
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1

hits="$(git ls-files '*.sh' | xargs -r grep -nE '(^[[:space:]]*#([^!]|$))|([[:space:]]#[[:space:]])' | grep -vE '^[^:]+:1:#!' || true)"
if [[ -n "$hits" ]]; then
  echo "comments found in shell files:"
  echo "$hits"
  exit 1
fi
echo "no comments in shell files"

panel_hits="$(head -n 660 Panel.qml | grep -nE '^[[:space:]]*//|[^:"]//[[:space:]]|/\*' || true)"
if [[ -n "$panel_hits" ]]; then
  echo "comments found in the properties and helpers of Panel.qml:"
  echo "$panel_hits"
  exit 1
fi
echo "no comments in the properties and helpers of Panel.qml"
