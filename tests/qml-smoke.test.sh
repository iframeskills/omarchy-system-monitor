#!/usr/bin/env bash
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shell_dir="${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}"

if ! command -v quickshell >/dev/null 2>&1 || [[ ! -d "$shell_dir/Ui" ]]; then
  printf 'FAIL: the smoke test needs quickshell and the Omarchy shell in %s\n' "$shell_dir"
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/config/Ui" "$work/bin"
ln -s "$shell_dir/Commons" "$work/config/Commons"
for file in "$shell_dir"/Ui/*; do
  [[ "$(basename "$file")" == "KeyboardPanel.qml" ]] && continue
  ln -s "$file" "$work/config/Ui/$(basename "$file")"
done
cp "$root/tests/qml-smoke/KeyboardPanel.qml" "$work/config/Ui/KeyboardPanel.qml"
cp "$root/tests/qml-smoke/shell.qml" "$work/config/shell.qml"

printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/sudo.log"\n' "$work" >"$work/bin/sudo"
chmod +x "$work/bin/sudo"

SMOKE_PLUGIN_DIR="$root" QT_QPA_PLATFORM=offscreen PATH="$work/bin:$PATH" \
  XDG_RUNTIME_DIR="$work/runtime" XDG_CACHE_HOME="$work/cache" XDG_STATE_HOME="$work/state" \
  timeout 30 quickshell -p "$work/config" >"$work/log.txt" 2>&1

failures=0
fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

grep -q "SMOKE clicked" "$work/log.txt" || fail "the popup did not load or the Apply button was not found: $(grep -o 'SMOKE .*' "$work/log.txt" | head -1)"
if grep -E "ReferenceError|TypeError|is not a type|unavailable|is not defined|module .* is not installed" "$work/log.txt"; then
  fail "the QML log has errors"
fi

expected="-n /usr/local/bin/asahi-fanctl curve 12 40 1500 4000 800"
actual="$(cat "$work/sudo.log" 2>/dev/null || true)"
[[ "$actual" == "$expected" ]] || fail "Apply ran fanctl with '$actual', expected '$expected'"

if (( failures > 0 )); then
  sed 's/\x1b\[[0-9;]*m//g' "$work/log.txt" | tail -40
  exit 1
fi
printf 'ok: the popup loads and Apply sends the custom fan curve\n'
