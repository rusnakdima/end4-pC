#!/usr/bin/env bash
#
# Shell test: materialQT.sh must take source/destination roles from the resolved map.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MATERIAL_QT="$REPO_ROOT/scripts/kvantum/materialQT.sh"

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

setup_case() {
    local mode="$1"
    local d="$TMP_DIR/$mode"
    mkdir -p "$d/home/.config/Kvantum/Colloid" \
             "$d/home/.config/Kvantum/MaterialAdw" \
             "$d/state/quickshell/theme-stack" "$d/bin"
    printf 'light-source\n' > "$d/home/.config/Kvantum/Colloid/Colloid.kvconfig"
    printf 'dark-source\n' > "$d/home/.config/Kvantum/Colloid/ColloidDark.kvconfig"
    cat > "$d/state/quickshell/theme-stack/resolved.json" <<'JSON'
{"version":1,"mode":"dark","gtkTheme":"adw-gtk3","kvantumTheme":"MaterialAdw","kvantumSourceDir":"Colloid","kvantumLightSource":"Colloid.kvconfig","kvantumDarkSource":"ColloidDark.kvconfig","qtQuickStyle":"Material","sources":{}}
JSON
    if [[ "$mode" == "light" ]]; then
        printf '#!/usr/bin/env bash\necho prefer-light\n' > "$d/bin/gsettings"
    else
        printf '#!/usr/bin/env bash\necho prefer-dark\n' > "$d/bin/gsettings"
    fi
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/bin/python"
    printf '#!/usr/bin/env bash\ntouch "%s/notified"\n' "$d/home" > "$d/bin/notify-send"
    chmod +x "$d/bin/"*
}

run_case() {
    local mode="$1"
    local d="$TMP_DIR/$mode"
    HOME="$d/home" \
    XDG_CONFIG_HOME="$d/home/.config" \
    XDG_STATE_HOME="$d/state" \
    APP_THEMING_SCRIPT_DIR="$REPO_ROOT" \
    APP_THEMING_NO_EXTERNAL=1 \
    PATH="$d/bin:$PATH" \
        bash "$MATERIAL_QT" >/dev/null 2>&1
}

setup_case dark
run_case dark
check 'dark apply copies the dark kvconfig byte-for-byte' \
    "cmp -s '$TMP_DIR/dark/home/.config/Kvantum/Colloid/ColloidDark.kvconfig' '$TMP_DIR/dark/home/.config/Kvantum/MaterialAdw/MaterialAdw.kvconfig'"

setup_case light
run_case light
check 'light apply copies the light kvconfig byte-for-byte' \
    "cmp -s '$TMP_DIR/light/home/.config/Kvantum/Colloid/Colloid.kvconfig' '$TMP_DIR/light/home/.config/Kvantum/MaterialAdw/MaterialAdw.kvconfig'"

setup_case missing
rm -rf "$TMP_DIR/missing/home/.config/Kvantum/Colloid"
run_case missing
check 'missing source dir is non-fatal to notifications under NO_EXTERNAL' \
    "test ! -e '$TMP_DIR/missing/home/notified'"

setup_case selfcopy
d="$TMP_DIR/selfcopy"
jq '.kvantumSourceDir = "MaterialAdw" | .kvantumDarkSource = "MaterialAdw.kvconfig"' \
    "$d/state/quickshell/theme-stack/resolved.json" > "$d/resolved.tmp"
mv "$d/resolved.tmp" "$d/state/quickshell/theme-stack/resolved.json"
printf 'existing-destination\n' > "$d/home/.config/Kvantum/MaterialAdw/MaterialAdw.kvconfig"
cat > "$d/bin/cp" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$d/cp.log"
exec /usr/bin/cp "\$@"
EOF
chmod +x "$d/bin/cp"
run_case selfcopy
selfcopy_status=$?
check 'self-copy mapping is skipped without an error' \
    "test $selfcopy_status -eq 0"
check 'self-copy mapping never invokes cp on the generated destination' \
    "test ! -s '$d/cp.log'"
check 'self-copy mapping leaves the generated kvconfig intact' \
    "grep -qx 'existing-destination' '$d/home/.config/Kvantum/MaterialAdw/MaterialAdw.kvconfig'"

setup_case datasource
d="$TMP_DIR/datasource"
mkdir -p "$d/home/.local/share/Kvantum/Colloid"
mv "$d/home/.config/Kvantum/Colloid/Colloid.kvconfig" "$d/home/.local/share/Kvantum/Colloid/Colloid.kvconfig"
mv "$d/home/.config/Kvantum/Colloid/ColloidDark.kvconfig" "$d/home/.local/share/Kvantum/Colloid/ColloidDark.kvconfig"
APP_THEMING_KVANTUM_ROOTS="$d/home/.config/Kvantum:$d/home/.local/share/Kvantum" \
    run_case datasource
check 'source in XDG_DATA_HOME is copied from its own root' \
    "cmp -s '$d/home/.local/share/Kvantum/Colloid/ColloidDark.kvconfig' '$d/home/.config/Kvantum/MaterialAdw/MaterialAdw.kvconfig'"

printf '%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
