#!/usr/bin/env bash
# Contract test: the SDDM drop-in is merged, never clobbered, and both the
# installer and the opt-in sync path deploy through the same helper.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
MERGER="$ROOT/scripts/sddm/merge-sddm-conf.py"
HELPER="$ROOT/scripts/sddm/deploy-theme.sh"

# 1. A real merger exists and rewrites a real drop-in without losing local keys.
[[ -f "$MERGER" ]] || fail 'scripts/sddm/merge-sddm-conf.py is missing'
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/sddm.conf" <<'EOF'
[General]
DisplayServer=x11-user
InputMethod=old
GreeterEnvironment=OLD=1
MaxUid=1000

[Theme]
Current=other
Cursor=theme
EOF
python3 "$MERGER" --file "$tmp/sddm.conf" || fail 'merger exited non-zero'
grep -q '^DisplayServer=x11-user$' "$tmp/sddm.conf" || fail 'lost custom DisplayServer'
grep -q '^MaxUid=1000$' "$tmp/sddm.conf" || fail 'lost custom MaxUid'
grep -q '^Cursor=theme$' "$tmp/sddm.conf" || fail 'lost custom Cursor'
grep -q '^Current=ii-sddm-theme$' "$tmp/sddm.conf" || fail 'did not set Current'
grep -q '^InputMethod=qtvirtualkeyboard$' "$tmp/sddm.conf" || fail 'did not set InputMethod'
grep -q '^GreeterEnvironment=QML2_IMPORT_PATH=/usr/share/sddm/themes/ii-sddm-theme/Components/$' "$tmp/sddm.conf" ||
    fail 'did not set QML2_IMPORT_PATH'
if grep -qE 'InputMethod=old|Current=other|OLD=1' "$tmp/sddm.conf"; then
    fail 'old managed values were left behind'
fi

# 2. A missing drop-in is created from scratch with both managed sections.
fresh="$tmp/fresh.conf"
python3 "$MERGER" --file "$fresh" || fail 'merger failed on a missing drop-in'
grep -q '^\[General\]$' "$fresh" || fail 'fresh drop-in has no [General]'
grep -q '^\[Theme\]$' "$fresh" || fail 'fresh drop-in has no [Theme]'
grep -q '^Current=ii-sddm-theme$' "$fresh" || fail 'fresh drop-in has no Current'

# 3. Replaying the merge is a no-op.
before=$(cat "$tmp/sddm.conf")
python3 "$MERGER" --file "$tmp/sddm.conf" || fail 'second merger run exited non-zero'
[[ "$(cat "$tmp/sddm.conf")" == "$before" ]] || fail 'merger is not idempotent'

# 4. Deploy helper wires the merger and the opt-in greeter refresh.
[[ -x "$HELPER" ]] || fail 'scripts/sddm/deploy-theme.sh is missing or not executable'
grep -q 'merge-sddm-conf.py' "$HELPER" ||
    fail 'deploy helper does not call the config merger'
grep -q -- '--reload-sddm' "$HELPER" ||
    fail 'deploy helper has no opt-in greeter reload'

# 5. Both entry points use the helper; sync makes SDDM opt-in.
grep -q 'deploy-theme.sh' "$ROOT/install.sh" ||
    fail 'install.sh does not deploy the SDDM theme through the helper'
grep -q 'deploy-theme.sh' "$ROOT/sync.sh" ||
    fail 'sync.sh does not deploy the SDDM theme through the helper'
grep -q -- '--sddm' "$ROOT/sync.sh" ||
    fail 'sync.sh has no --sddm flag'
if grep -q 'ii-sddm-theme/setup.sh' "$ROOT/install.sh"; then
    fail 'installer still calls the upstream setup.sh (clones + clobbers config)'
fi

echo 'PASS: SDDM config merge contract'
