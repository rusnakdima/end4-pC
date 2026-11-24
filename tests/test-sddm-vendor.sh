#!/usr/bin/env bash
# Contract test: the greeter is integrated as a git submodule of the user's
# fork, and install.sh updates it without clobbering per-device generated state.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. Theme source exists (submodule is checked out).
for f in \
    sddm/ii-sddm-theme/Components/Input.qml \
    sddm/ii-sddm-theme/Components/InputLogin.qml \
    sddm/ii-sddm-theme/Themes/ii-sddm.conf \
    sddm/ii-sddm-theme/PATCHES.md; do
    [[ -f "$ROOT/$f" ]] || fail "missing theme file: $f"
done

# 2. It really is the user's fork, referenced as a gitlink.
grep -q 'path = sddm/ii-sddm-theme' "$ROOT/.gitmodules" ||
    fail '.gitmodules does not declare the greeter submodule'
grep -q 'rusnakdima/ii-sddm-theme' "$ROOT/.gitmodules" ||
    fail '.gitmodules does not point at the rusnakdima fork'
gitlink="$(cd "$ROOT" && git ls-files -s sddm/ii-sddm-theme)"
[[ "$gitlink" == 160000\ * ]] || fail "greeter is not a git submodule gitlink: $gitlink"

# 3. install.sh installs from the submodule and errors clearly when it is
#    uninitialized (an empty directory must not silently deploy a blank theme).
grep -q 'sddm/ii-sddm-theme' "$ROOT/install.sh" ||
    fail 'install.sh does not reference the greeter submodule'
grep -q 'uninitialized git submodule' "$ROOT/install.sh" ||
    fail 'install.sh has no clear error for an uninitialized submodule'
grep -q 'rm -f "$theme_dest/.git"' "$ROOT/install.sh" ||
    fail 'install.sh does not strip the submodule .git pointer on fresh install'

# 4. Generated state is explicitly guarded during reinstall.
grep -q 'PRESERVE_GENERATED' "$ROOT/install.sh" ||
    fail 'install.sh has no PRESERVE_GENERATED guard for generated theme state'
for f in 'Settings.qml' 'ii-sddm.conf' 'Backgrounds/'; do
    grep -q -- "$f" "$ROOT/install.sh" ||
        fail "install.sh does not mention preserved path: $f"
done

# 5. Generated background binaries are not tracked.
tracked="$(cd "$ROOT" && git ls-files 'sddm/ii-sddm-theme/Backgrounds/background.*')"
[[ -z "$tracked" ]] || fail "generated backgrounds are tracked: $tracked"

# 6. The update path also refreshes shell/python helpers.
grep -q -- "-o -name '\*.sh'" "$ROOT/install.sh" ||
    fail 'install.sh update filter does not copy *.sh helpers'
grep -q -- "-o -name '\*.py'" "$ROOT/install.sh" ||
    fail 'install.sh update filter does not copy *.py helpers'

echo 'PASS: greeter submodule and generated-state preservation contract'
