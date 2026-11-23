#!/usr/bin/env bash
# Contract test: the greeter is vendored in the repo and install.sh updates it
# without clobbering per-device generated state.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. Vendored code and config files exist.
for f in \
    sddm/ii-sddm-theme/Components/Input.qml \
    sddm/ii-sddm-theme/Components/InputLogin.qml \
    sddm/ii-sddm-theme/Themes/ii-sddm.conf; do
    [[ -f "$ROOT/$f" ]] || fail "missing vendored file: $f"
done

# 2. install.sh installs from the vendored tree.
grep -q 'sddm/ii-sddm-theme' "$ROOT/install.sh" ||
    fail 'install.sh does not reference the vendored sddm/ii-sddm-theme tree'

# 3. Generated state is explicitly guarded during reinstall.
grep -q 'PRESERVE_GENERATED' "$ROOT/install.sh" ||
    fail 'install.sh has no PRESERVE_GENERATED guard for generated theme state'
for f in 'Settings.qml' 'ii-sddm.conf' 'Backgrounds/'; do
    grep -q -- "$f" "$ROOT/install.sh" ||
        fail "install.sh does not mention preserved path: $f"
done

# 4. Generated background binaries are not tracked.
tracked="$(cd "$ROOT" && git ls-files 'sddm/ii-sddm-theme/Backgrounds/background.*')"
[[ -z "$tracked" ]] || fail "generated backgrounds are tracked: $tracked"

# 5. The update path also refreshes shell/python helpers, so local theme
# patches (e.g. iiMatugen/sddm-theme-apply.sh) survive a reinstall.
grep -q -- "-o -name '\*.sh'" "$ROOT/install.sh" ||
    fail 'install.sh update filter does not copy *.sh helpers'
grep -q -- "-o -name '\*.py'" "$ROOT/install.sh" ||
    fail 'install.sh update filter does not copy *.py helpers'

echo 'PASS: vendored theme and generated-state preservation contract'
