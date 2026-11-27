#!/usr/bin/env bash
# Deploy the ii-sddm-theme greeter from the vendored git submodule and register
# it in SDDM's config. Shared by install.sh and `sync.sh --sddm` so a sync can
# never drift from a fresh install.
#
# The upstream setup.sh is deliberately NOT used: it clones from GitHub and
# overwrites the whole drop-in, destroying per-machine keys such as
# DisplayServer and MaximumUid (see docs/sddm-archpc-notes.md).
set -uo pipefail

PROG=${0##*/}
usage() {
    cat <<'EOF'
Usage: deploy-theme.sh [OPTIONS]

Copy the vendored greeter into /usr/share/sddm/themes/ii-sddm-theme and merge
the end4-pC keys into /etc/sddm.conf.d/ii-sddm-theme.conf.

Options:
  -h, --help         Show this help and exit.
  --config-only      Only update the config drop-in, do not copy theme files.
  --theme-only       Only copy theme files, do not touch the config drop-in.
  --reload-sddm      With a TTY, restart SDDM after deploying. This ends
                     active graphical sessions; without a TTY the manual
                     command is printed instead.

Environment:
  END4PC_SOURCE_DIR    Checkout root (default: this script's grandparent).
  END4PC_TARGET_HOME   Target user's home (default: caller's home).
  END4PC_TARGET_USER   Target user name (default: caller).
  END4PC_ELEVATE       Privilege prefix (default: sudo when not root).
  END4PC_SDDM_CONF     Config drop-in path (default: /etc/sddm.conf.d/ii-sddm-theme.conf).
  END4PC_SDDM_THEME_DIR Theme directory (default: /usr/share/sddm/themes/ii-sddm-theme).
EOF
}

reload_sddm=0
config_only=0
theme_only=0
while (($#)); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --config-only) config_only=1 ;;
        --theme-only) theme_only=1 ;;
        --reload-sddm) reload_sddm=1 ;;
        --) shift; break ;;
        -*) echo "$PROG: unknown option: $1 (try --help)" >&2; exit 2 ;;
        *) echo "$PROG: unexpected argument: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

source_dir="${END4PC_SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
target_home="${END4PC_TARGET_HOME:-$HOME}"
target_user="${END4PC_TARGET_USER:-$(id -un)}"
theme_src="$source_dir/sddm/ii-sddm-theme"
theme_dest="${END4PC_SDDM_THEME_DIR:-/usr/share/sddm/themes/ii-sddm-theme}"
conf_dropin="${END4PC_SDDM_CONF:-/etc/sddm.conf.d/ii-sddm-theme.conf}"
conf_dir="$(dirname "$conf_dropin")"

ELEVATE="${END4PC_ELEVATE:-}"
if [[ $(id -u) -ne 0 ]]; then
    [[ -n "$ELEVATE" ]] || ELEVATE="sudo"
    elevate_bin="${ELEVATE%% *}"
    if ! command -v "$elevate_bin" >/dev/null 2>&1; then
        echo "$PROG: root privileges are required to deploy the greeter" >&2
        exit 1
    fi
fi

require_sudo() {
    # install.sh passes ELEVATE=sudo when it has passwordless sudo, so a
    # non-root caller can legitimately write system files through it.
    if [[ $(id -u) -eq 0 || -n "$ELEVATE" ]]; then
        return 0
    fi
    echo "$PROG: $1 requires root; run with sudo" >&2
    return 1
}

deploy_theme_files() {
    if [[ ! -f "$theme_src/Components/Input.qml" ]]; then
        echo "$PROG: ERROR: sddm/ii-sddm-theme is an uninitialized git submodule." >&2
        echo "$PROG:        Run: git submodule update --init --recursive" >&2
        return 1
    fi

    if [[ ! -d "$theme_dest" ]]; then
        $ELEVATE mkdir -p "$(dirname "$theme_dest")" || return 1
        $ELEVATE cp -r "$theme_src" "$theme_dest" || return 1
        # A submodule keeps its .git as a *file* pointing at the parent repo's
        # modules dir; never install that pointer into the system theme.
        $ELEVATE rm -f "$theme_dest/.git"
    else
        # Update code in place, but keep each device's generated state.
        local PRESERVE_GENERATED=1
        local src rel
        while IFS= read -r -d '' src; do
            rel="${src#"$theme_src"/}"
            if [[ "$PRESERVE_GENERATED" == "1" ]]; then
                case "$rel" in
                    Components/Settings.qml|iiMatugen/Settings.qml|noMatugen/Settings.qml|Matugen/Settings.qml|Themes/ii-sddm.conf|Backgrounds/*)
                        continue
                        ;;
                esac
            fi
            $ELEVATE mkdir -p "$theme_dest/$(dirname "$rel")" || return 1
            $ELEVATE cp -f "$src" "$theme_dest/$rel" || return 1
        done < <(find "$theme_src" -type f \
            \( -name '*.qml' -o -name 'qmldir' -o -name '*.js' \
               -o -name '*.sh' -o -name '*.py' \
               -o -name 'PATCHES.md' \) -print0)
    fi

    $ELEVATE mkdir -p "$theme_dest/Backgrounds" || return 1

    # Copy the current wallpaper to SDDM backgrounds if not already synced.
    if [[ -f "$target_home/.config/ii-sddm-theme/last_static_wallpaper" ]]; then
        local cur_wp ext
        cur_wp="$(cat "$target_home/.config/ii-sddm-theme/last_static_wallpaper" 2>/dev/null || echo "")"
        if [[ -n "$cur_wp" && -f "$cur_wp" ]]; then
            ext="${cur_wp##*.}"
            $ELEVATE cp --preserve=mode,timestamps "$cur_wp" "$theme_dest/Backgrounds/background.${ext}"
        fi
    fi
}

write_config() {
    require_sudo "configuring SDDM" || return 1
    local tmp
    tmp="$(mktemp)"
    if [[ -f "$conf_dropin" ]]; then
        cp "$conf_dropin" "$tmp" || return 1
    fi
    python3 "$source_dir/scripts/sddm/merge-sddm-conf.py" --file "$tmp" || { rm -f "$tmp"; return 1; }
    $ELEVATE mkdir -p "$conf_dir" || { rm -f "$tmp"; return 1; }
    $ELEVATE install -m 644 "$tmp" "$conf_dropin" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    echo "$PROG: $conf_dropin updated (other keys preserved)"
}

reload_greeter() {
    if [[ ! -t 0 ]]; then
        echo "$PROG: non-interactive; refresh the greeter with:"
        echo "  sudo systemctl restart sddm"
        return 0
    fi
    local answer
    read -r -p "$PROG: restart SDDM now? This ends active graphical sessions [y/N] " answer
    if [[ "$answer" != y && "$answer" != Y ]]; then
        echo "$PROG: skipped greeter restart; run 'sudo systemctl restart sddm' later"
        return 0
    fi
    if systemctl restart sddm; then
        echo "$PROG: SDDM restarted"
    else
        echo "$PROG: SDDM restart failed; run 'sudo systemctl restart sddm' manually" >&2
        return 1
    fi
}

fail=0
if [[ $config_only -eq 0 ]]; then
    deploy_theme_files || fail=1
fi
if [[ $theme_only -eq 0 ]]; then
    write_config || fail=1
fi
if [[ $fail -eq 0 && $reload_sddm -eq 1 ]]; then
    reload_greeter || fail=1
fi
exit "$fail"
