#!/usr/bin/env bash
#
# Shell test for scripts/theming/theme-provision.sh detection and resolved map.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROVISION="$REPO_ROOT/scripts/theming/theme-provision.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

pass=0
fail=0
check() {
    local name="$1" condition="$2"
    if eval "$condition"; then
        printf 'PASS %s\n' "$name"
        pass=$((pass + 1))
    else
        printf 'FAIL %s\n' "$name"
        fail=$((fail + 1))
    fi
}

check_resolved() {
    local name="$1" key="$2" expected="$3" actual
    actual="$(jq -r ".$key // empty" "$RESOLVED" 2>/dev/null)"
    if [[ "$actual" == "$expected" ]]; then
        printf 'PASS %s\n' "$name"
        pass=$((pass + 1))
    else
        printf 'FAIL %s (got %s, expected %s)\n' "$name" "$actual" "$expected"
        fail=$((fail + 1))
    fi
}

# --- case 1: installed themes + a deliberate user selection -----------------
export HOME="$TMP_DIR/case1"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export APP_THEMING_NO_EXTERNAL=1
RESOLVED="$XDG_STATE_HOME/quickshell/theme-stack/resolved.json"

mkdir -p "$XDG_DATA_HOME/themes/adw-gtk3" \
         "$XDG_CONFIG_HOME/Kvantum/Colloid" \
         "$XDG_STATE_HOME/quickshell/theme-stack"
printf '[Settings]\n' > "$XDG_CONFIG_HOME/Kvantum/Colloid/Colloid.kvconfig"
printf '[Settings]\n' > "$XDG_CONFIG_HOME/Kvantum/Colloid/ColloidDark.kvconfig"
printf '[General]\ntheme=CustomUserTheme\n' > "$XDG_CONFIG_HOME/Kvantum/kvantum.kvconfig"

bash "$PROVISION" dark --detect >/dev/null 2>&1

check 'detect writes resolved.json' "test -f '$RESOLVED'"
check_resolved 'detected gtk theme in dark mode' gtkTheme adw-gtk3-dark
check_resolved 'detected kvantum source dir' kvantumSourceDir Colloid
check_resolved 'detected light kvconfig source' kvantumLightSource Colloid.kvconfig
check_resolved 'detected dark kvconfig source' kvantumDarkSource ColloidDark.kvconfig
check_resolved 'qt quick style' qtQuickStyle Material
check_resolved 'resolved mode' mode dark
check 'user-selected kvantum theme survives detection' \
    "grep -q '^theme=CustomUserTheme$' '$XDG_CONFIG_HOME/Kvantum/kvantum.kvconfig'"

# --- case 2: no themes installed ---------------------------------------------
export HOME="$TMP_DIR/case2"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export APP_THEMING_THEME_ROOTS="$XDG_DATA_HOME/themes:$HOME/.themes"
export APP_THEMING_KVANTUM_ROOTS="$XDG_CONFIG_HOME/Kvantum"
RESOLVED="$XDG_STATE_HOME/quickshell/theme-stack/resolved.json"
mkdir -p "$XDG_STATE_HOME/quickshell/theme-stack"

bash "$PROVISION" dark --detect >/dev/null 2>&1

check_resolved 'fallback gtk theme in dark mode' gtkTheme Adwaita-dark
check_resolved 'fallback kvantum theme' kvantumTheme MaterialAdw
check_resolved 'fallback qt quick style' qtQuickStyle Material
check_resolved 'fallback gtk source' 'sources.gtk' missing
check_resolved 'fallback kvantum source' 'sources.kvantum' missing

# --- installer opt-out wiring ------------------------------------------------
INSTALL="$REPO_ROOT/install.sh"
check 'installer documents --no-theme-packages' \
    "grep -qF -- '--no-theme-packages' '$INSTALL'"
check 'installer defines APP_THEME_PACKAGES default' \
    "grep -q 'APP_THEME_PACKAGES=\"\${APP_THEME_PACKAGES:-1}\"' '$INSTALL'"
check 'installer validates APP_THEME_PACKAGES' \
    "grep -q 'check_01 APP_THEME_PACKAGES' '$INSTALL'"
check 'installer --help exits 0' \
    "bash '$INSTALL' --help >/dev/null 2>&1"
check 'invalid theme-packages option exits 2' \
    "bash '$INSTALL' --theme-packages=bogus >/dev/null 2>&1; test \$? -eq 2"

# --- --install is safe under the no-external test seam -----------------------
mkdir -p "$TMP_DIR/bin"
printf '#!/usr/bin/env bash\nexit 99\n' > "$TMP_DIR/bin/yay"
chmod +x "$TMP_DIR/bin/yay"
PATH="$TMP_DIR/bin:$PATH" APP_THEMING_NO_EXTERNAL=1 \
    bash "$PROVISION" dark --install >/dev/null 2>&1
check '--install is a no-op with APP_THEMING_NO_EXTERNAL=1' \
    "test -f '$RESOLVED'"

printf '%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
