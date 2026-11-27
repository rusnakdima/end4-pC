#!/usr/bin/env bash
#
# install.sh — end4-pC full setup installer
#
# Full option and environment-variable list: ./install.sh --help
#
# Common examples:
#   ./install.sh --offline                     # no network: check imports only
#   ./install.sh --offline --wheelhouse=./wheels  # offline pip from local wheels
#   sudo ./install.sh --target-user=NAME --with-vnc --vnc-mode=mirror
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR="$SCRIPT_DIR"          # end4-pC root
DOTS_SOURCE="$SCRIPT_DIR/dots"                 # vendored dotfiles + Hyprland config

# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------
# Parsing happens here, before any detection or writes, so --help and bad
# arguments always exit without touching the system.
PROG=${0##*/}
VERSION=dev

usage() {
    cat <<'EOF'
Usage: install.sh [OPTIONS]

Deploy end4-pC into the target user's config and state directories.

Options:
  -h, --help                 Show this help and exit.
  --version                  Print version and exit.
  --offline                  Never touch the network: no pip install/upgrade and
                             no whisper model download. Python deps are only
                             checked for importability (or installed from a
                             wheelhouse, see --wheelhouse).
  --wheelhouse DIR           Offline only: install Python deps from a local wheel
                             directory (pip --no-index --find-links=DIR). DIR
                             must exist.
  --wheelhouse=DIR           Same, single-token form.
  --skip-checks              Deploy even if the QML compile check finds new
                             errors in the checkout.
  --target-user NAME         Deploy into NAME's home instead of detecting the
                             target (SUDO_USER under sudo, else the invoking
                             user, else the first /home user).
  --with-waydroid            Also run optional/waydroid/install-waydroid.sh.
  --with-vnc                 Also run optional/vnc/install-vnc.sh.
  --vnc-mode MODE            VNC layout: full or mirror (default: full).
  --vnc-audio BACKEND        VNC audio: sunshine or none (default: sunshine).
  --vnc-autologin 0|1        Enable VNC autologin (default: 1).
  --skip-stt-model           Do not pre-download the whisper base model.
  --keep-window-buttons      Keep GTK/Qt titlebar buttons (default: disabled).
  --no-app-theming           Do not apply external app theming.
  --no-app-theming-qt-env    Do not set QT_STYLE_OVERRIDE=kvantum.
  --no-app-theming-hook      Do not install matugen post-hooks.
  --no-theme-packages        Do not install compatible GTK/Qt theme packages.
  --reload-sddm              Ask to restart SDDM after deploying the greeter
                             (interactive only; ends active sessions).
  --                         Stop option parsing.

Environment (flags take precedence; binary variables must be 0 or 1):
  OFFLINE=1                  Same as --offline.
  OFFLINE_WHEELHOUSE=DIR     Same as --wheelhouse (DIR must exist).
  SKIP_STT_MODEL_DOWNLOAD=1  Same as --skip-stt-model.
  DISABLE_WINDOW_BUTTONS=0   Same as --keep-window-buttons.
  APP_THEMING=0              Same as --no-app-theming.
  APP_THEMING_QT_ENV=0       Same as --no-app-theming-qt-env.
  APP_THEMING_MATUGEN_HOOK=0 Same as --no-app-theming-hook.
  APP_THEME_PACKAGES=0       Same as --no-theme-packages.
  RELOAD_SDDM=1              Same as --reload-sddm.
  VNC_MODE / VNC_AUDIO / VNC_AUTOLOGIN  Same as the matching flags.

Examples:
  ./install.sh --offline --wheelhouse ./wheels
  sudo ./install.sh --target-user dmitriy --with-vnc --vnc-mode mirror
  ./install.sh --keep-window-buttons --skip-checks

Exit status:
  0  install finished and all smoke checks passed
  1  install finished but some smoke checks failed
  2  invalid command line or option value (nothing was changed)
EOF
}

die() { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 2; }
need_value() { [[ $# -ge 2 ]] || die "$1 needs a value"; }
is_01() { [[ "$1" == 0 || "$1" == 1 ]]; }

check_01() {
    is_01 "$2" || die "$1 must be 0 or 1 (got '$2')"
}

# Defaults. Flags override the environment; both are validated below.
SKIP_CHECKS=0
WITH_WAYDROID=0
WITH_VNC=0
VNC_MODE="${VNC_MODE:-full}"
VNC_AUDIO="${VNC_AUDIO:-sunshine}"
VNC_AUTOLOGIN="${VNC_AUTOLOGIN:-1}"
DISABLE_WINDOW_BUTTONS="${DISABLE_WINDOW_BUTTONS:-1}"
APP_THEMING="${APP_THEMING:-1}"
APP_THEMING_QT_ENV="${APP_THEMING_QT_ENV:-1}"
APP_THEMING_MATUGEN_HOOK="${APP_THEMING_MATUGEN_HOOK:-1}"
APP_THEME_PACKAGES="${APP_THEME_PACKAGES:-1}"
RELOAD_SDDM="${RELOAD_SDDM:-0}"
OFFLINE="${OFFLINE:-0}"
OFFLINE_WHEELHOUSE="${OFFLINE_WHEELHOUSE:-}"
SKIP_STT_MODEL_DOWNLOAD="${SKIP_STT_MODEL_DOWNLOAD:-0}"
TARGET_USER_OVERRIDE=""

while (($#)); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --version) printf 'end4-pC installer %s\n' "$VERSION"; exit 0 ;;
        --offline) OFFLINE=1 ;;
        --wheelhouse=*) OFFLINE_WHEELHOUSE="${1#*=}" ;;
        --wheelhouse) need_value "$@"; OFFLINE_WHEELHOUSE="$2"; shift ;;
        --skip-checks) SKIP_CHECKS=1 ;;
        --target-user=*) TARGET_USER_OVERRIDE="${1#*=}" ;;
        --target-user) need_value "$@"; TARGET_USER_OVERRIDE="$2"; shift ;;
        --with-waydroid) WITH_WAYDROID=1 ;;
        --with-vnc) WITH_VNC=1 ;;
        --vnc-mode=*) VNC_MODE="${1#*=}" ;;
        --vnc-mode) need_value "$@"; VNC_MODE="$2"; shift ;;
        --vnc-audio=*) VNC_AUDIO="${1#*=}" ;;
        --vnc-audio) need_value "$@"; VNC_AUDIO="$2"; shift ;;
        --vnc-autologin=*) VNC_AUTOLOGIN="${1#*=}" ;;
        --vnc-autologin) need_value "$@"; VNC_AUTOLOGIN="$2"; shift ;;
        --skip-stt-model) SKIP_STT_MODEL_DOWNLOAD=1 ;;
        --keep-window-buttons) DISABLE_WINDOW_BUTTONS=0 ;;
        --no-app-theming) APP_THEMING=0 ;;
        --no-app-theming-qt-env) APP_THEMING_QT_ENV=0 ;;
        --no-app-theming-hook) APP_THEMING_MATUGEN_HOOK=0 ;;
        --no-theme-packages) APP_THEME_PACKAGES=0 ;;
        --reload-sddm) RELOAD_SDDM=1 ;;
        --) shift; break ;;
        -*) die "unknown option: $1 (try --help)" ;;
        *) die "unexpected argument: $1 (try --help)" ;;
    esac
    shift
done

# Fail fast on bad values: nothing above this point has changed the system.
check_01 OFFLINE "$OFFLINE"
check_01 SKIP_STT_MODEL_DOWNLOAD "$SKIP_STT_MODEL_DOWNLOAD"
check_01 DISABLE_WINDOW_BUTTONS "$DISABLE_WINDOW_BUTTONS"
check_01 APP_THEMING "$APP_THEMING"
check_01 APP_THEMING_QT_ENV "$APP_THEMING_QT_ENV"
check_01 APP_THEMING_MATUGEN_HOOK "$APP_THEMING_MATUGEN_HOOK"
check_01 APP_THEME_PACKAGES "$APP_THEME_PACKAGES"
check_01 RELOAD_SDDM "$RELOAD_SDDM"
check_01 VNC_AUTOLOGIN "$VNC_AUTOLOGIN"
case "$VNC_MODE" in full|mirror) ;; *) die "invalid --vnc-mode '$VNC_MODE' (expected full or mirror)" ;; esac
case "$VNC_AUDIO" in sunshine|none) ;; *) die "invalid --vnc-audio '$VNC_AUDIO' (expected sunshine or none)" ;; esac
if [[ -n "$OFFLINE_WHEELHOUSE" && ! -d "$OFFLINE_WHEELHOUSE" ]]; then
    die "wheelhouse directory does not exist: $OFFLINE_WHEELHOUSE"
fi
if [[ -n "$TARGET_USER_OVERRIDE" ]]; then
    getent passwd "$TARGET_USER_OVERRIDE" >/dev/null 2>&1 \
        || die "unknown user: $TARGET_USER_OVERRIDE"
fi

# ---------------------------------------------------------------------------
# Root / target-user detection
# ---------------------------------------------------------------------------
resolve_target_home() {
    if [[ -n "$TARGET_USER_OVERRIDE" ]]; then
        TARGET_USER="$TARGET_USER_OVERRIDE"
        TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
        [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || {
            echo "[install] ERROR: no home directory for $TARGET_USER" >&2
            exit 2
        }
    elif [[ $(id -u) -eq 0 ]]; then
        if [[ -n "${SUDO_USER:-}" ]]; then
            TARGET_HOME=$(eval echo "~$SUDO_USER")
            TARGET_USER="$SUDO_USER"
        else
            local -a candidates
            mapfile -t candidates < <(find /home -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
            if ((${#candidates[@]} == 0)); then
                echo "[install] ERROR: No target user found and SUDO_USER not set. Cannot proceed." >&2
                exit 1
            elif ((${#candidates[@]} == 1)); then
                TARGET_USER="${candidates[0]}"
                TARGET_HOME="/home/$TARGET_USER"
            else
                echo "[install] Multiple users found: ${candidates[*]}"
                echo "[install] Using first candidate: ${candidates[0]}"
                TARGET_USER="${candidates[0]}"
                TARGET_HOME="/home/$TARGET_USER"
            fi
        fi
    else
        TARGET_HOME="$HOME"
        TARGET_USER=$(whoami)
    fi
    export TARGET_HOME TARGET_USER
    # ELEVATE is "sudo" when running as non-root, empty when already root
    if [[ $(id -u) -ne 0 ]]; then
        export ELEVATE="sudo"
    else
        export ELEVATE=""
    fi
    echo "[install] Target: ~$TARGET_USER ($TARGET_HOME)"
}

# ---------------------------------------------------------------------------
# Root privilege helper
# ---------------------------------------------------------------------------
# A few steps write into system directories and therefore need root. When
# sudo cannot be used without a password those steps are skipped with a
# warning instead of aborting the whole install: the desktop itself does not
# depend on them, and the user can rerun the installer with sudo later.
HAVE_SUDO=1
if [[ $(id -u) -ne 0 ]] && ! sudo -n true &>/dev/null; then
    HAVE_SUDO=0
fi

require_sudo() {
    local what="$1"
    if [[ $HAVE_SUDO -eq 1 ]]; then
        return 0
    fi
    echo "[install] WARN: $what needs root, but sudo is not available without a password — skipped." >&2
    echo "[install]       Rerun this installer with sudo to complete it." >&2
    return 1
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
banner() {
    echo ""
    echo "============================================================"
    echo "  end4-pC Installer"
    echo "  Target: ~$TARGET_USER"
    echo "============================================================"
    echo ""
}

# ---------------------------------------------------------------------------
# Source package installer
# ---------------------------------------------------------------------------
install_packages() {
    echo "[install] Installing system packages..."
    # shellcheck source=install-system.sh
    source "$SOURCE_DIR/install-system.sh"
    install_packages
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# Copy a file into place atomically.
#
# GNU install and cp both unlink or truncate the destination, so the file is
# briefly missing or empty. Hyprland re-reads its config on every reload, and
# a reload that lands in that window fails with
# "cannot open ~/.config/hypr/hyprland.lua: No such file or directory",
# which Hyprland then keeps reporting until the next reload. Writing to a
# temporary file in the same directory and renaming it makes the swap
# atomic, so the config is never observed in a broken state.
deploy_atomic() {
    local src="$1" dest="$2" mode="${3:-644}"
    local tmp
    tmp=$(mktemp "${dest}.XXXXXX")
    cat "$src" > "$tmp"
    chmod "$mode" "$tmp"
    mv -f "$tmp" "$dest"
    # When install.sh runs under sudo, mktemp creates the file as root. Hand
    # it back to the target user so the desktop can still edit it later.
    if [[ $(id -u) -eq 0 && -n "${TARGET_USER:-}" ]]; then
        chown "$TARGET_USER:" "$dest" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Quickshell config
# ---------------------------------------------------------------------------
install_qs_config() {
    echo "[install] Deploying Quickshell config..."
    local dest="$TARGET_HOME/.config/quickshell/end4-pC"
    mkdir -p "$(dirname "$dest")"
    # Never copy the checkout's .git directory into the deployed config.
    rsync -av --delete --exclude '/dots/' --exclude '/.omp/' --exclude '/file:/' --exclude '/.git/' "$SOURCE_DIR/" "$dest/"

    # The keep-awake idle lock is held by a fixed-name user unit so a shell
    # reload cannot orphan it (and leave idle timeouts permanently disabled).
    install -Dm644 "$SOURCE_DIR/systemd/user/end4pc-keep-awake.service" \
        "$TARGET_HOME/.config/systemd/user/end4pc-keep-awake.service"

    # Patch QUICKSHELL_CONFIG_NAME="ii" → "end4-pC" in installed scripts
    find "$dest/scripts" -type f -name '*.sh' -print0 | while IFS= read -r -d '' f; do
        if grep -q 'QUICKSHELL_CONFIG_NAME="ii"' "$f" 2>/dev/null; then
            sed -i 's/QUICKSHELL_CONFIG_NAME="ii"/QUICKSHELL_CONFIG_NAME="end4-pC"/g' "$f"
        fi
    done
}

# ---------------------------------------------------------------------------
# Lock screen watchdog
# ---------------------------------------------------------------------------
# The guard is the only recovery path for a shell that dies while the session
# is locked. It must be installed AND enabled: a unit sitting in ~/.config is
# useless if no target wants it. Enabling via default.target.wants works even
# when the installer runs as root for another user (no `systemctl --user`
# session needed here).
install_lock_guard() {
    echo "[install] Deploying lock screen watchdog..."
    local bin_dir="$TARGET_HOME/.local/bin"
    local unit_dir="$TARGET_HOME/.config/systemd/user"
    local wants_dir="$unit_dir/default.target.wants"

    install -Dm755 "$SOURCE_DIR/scripts/lock/end4pc-lock-guard" \
        "$bin_dir/end4pc-lock-guard"
    install -Dm644 "$SOURCE_DIR/systemd/user/end4pc-lock-guard.service" \
        "$unit_dir/end4pc-lock-guard.service"
    mkdir -p "$wants_dir"
    ln -sfn ../end4pc-lock-guard.service \
        "$wants_dir/end4pc-lock-guard.service"

    if [[ $(id -u) -eq 0 && -n "${TARGET_USER:-}" ]]; then
        chown "$TARGET_USER:" \
            "$bin_dir/end4pc-lock-guard" \
            "$unit_dir/end4pc-lock-guard.service" \
            "$wants_dir/end4pc-lock-guard.service" 2>/dev/null || true
    fi

    # Pick the unit up in the current session when we are running as the
    # target user; otherwise it starts with that user's next session.
    if [[ "${TARGET_USER:-}" == "$(id -un)" ]]; then
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable --now end4pc-lock-guard.service 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Hyprland config
# ---------------------------------------------------------------------------
# The theme owns the Hyprland config: it ships the managed files under
# dots/.config/hypr and deploys them to ~/.config/hypr.
# ~/.config/hypr/custom stays user-owned and is never touched.
install_hyprland_config() {
    echo "[install] Deploying Hyprland config..."
    local src="$DOTS_SOURCE/.config/hypr"
    local dest="$TARGET_HOME/.config/hypr"
    if [[ ! -d "$src" ]]; then
        echo "[install] WARN: hyprland config source not found at $src" >&2
        return
    fi
    mkdir -p "$dest"

    # Managed files: the theme is the source of truth, stale ones are removed.
    # shellOverrides/ is written by the shell itself and is only seeded below.
    # Only sync managed subdirs that actually ship in this checkout. A sparse
    # or partial dots/ tree must not make rsync --delete fail (set -e) or wipe
    # live user config from a missing source directory.
    if [[ -d "$src/hyprland" ]]; then
        rsync -a --delete --exclude 'shellOverrides' "$src/hyprland/" "$dest/hyprland/"
    fi
    if [[ -d "$src/hyprlock" ]]; then
        rsync -a --delete "$src/hyprlock/" "$dest/hyprlock/"
    fi
    if [[ -d "$src/scripts" ]]; then
        rsync -a --delete "$src/scripts/" "$dest/scripts/"
    fi
    for file in hyprland.lua hypridle.conf hyprlock.conf; do
        [[ -f "$src/$file" ]] && deploy_atomic "$src/$file" "$dest/$file"
    done

    # Shell overrides: written by the shell, seeded only when missing.
    if [[ -d "$src/hyprland/shellOverrides" ]]; then
        mkdir -p "$dest/hyprland/shellOverrides"
        rsync -a --ignore-existing "$src/hyprland/shellOverrides/" "$dest/hyprland/shellOverrides/"
    fi
}

# ---------------------------------------------------------------------------
# Default keybinds
# ---------------------------------------------------------------------------
# All keybinds now come from one JSON catalog (defaults/hyprland/keybinds.json)
# which is rendered into the live main/custom Lua files by the migrated
# sync.sh. install_qs_config already deployed sync.sh, the catalog, the
# generator and the QML command bridge into ~/.config/quickshell/end4-pC, so
# delegate here instead of duplicating the generation logic. sync.sh detects
# the target user itself (SUDO_USER under sudo), so this is correct even when
# the installer runs elevated. --no-reload avoids reloading Hyprland mid-install.
install_keybind_defaults() {
    local deployed_sync="$TARGET_HOME/.config/quickshell/end4-pC/sync.sh"

    if [[ ! -f "$deployed_sync" || ! -f "$SOURCE_DIR/defaults/hyprland/keybinds.json" ]]; then
        echo "[install] WARN: keybind catalog or sync.sh missing; skipping keybind generation" >&2
        return 0
    fi

    echo "[install] Generating keybinds from catalog..."
    if [[ -n "${TARGET_USER:-}" && "${TARGET_USER}" != "$(id -un)" ]]; then
        # Installer runs as root (or another user) for a different target: run
        # sync.sh as the target user with an explicit HOME so its own
        # resolve_target_home() lands on the same home this installer used.
        sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" \
            "$deployed_sync" --keybinds-only --no-reload
    else
        "$deployed_sync" --keybinds-only --no-reload
    fi

    # The generator writes as the invoking user; make sure the live Hyprland
    # files and the command bridge are owned by the target user either way.
    if [[ $(id -u) -eq 0 && -n "${TARGET_USER:-}" ]]; then
        chown "$TARGET_USER:" \
            "$TARGET_HOME/.config/hypr/hyprland/keybinds.lua" \
            "$TARGET_HOME/.config/hypr/custom/keybinds.lua" \
            "$TARGET_HOME/.config/quickshell/end4-pC/state/generated-commands.json" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Hyprland env vars
# ---------------------------------------------------------------------------
patch_hyprland_env() {
    echo "[install] Patching Hyprland env vars..."
    local envlua="$TARGET_HOME/.config/hypr/hyprland/env.lua"
    [[ -f "$envlua" ]] || return 0

    # The patch is applied to a copy and then swapped in atomically, so a
    # Hyprland reload never sees a half-patched env.lua: env.lua decides which
    # Quickshell config is started, and a reload in the middle of the patch
    # would start the wrong one.
    local tmp
    tmp=$(mktemp "${envlua}.XXXXXX")
    cp "$envlua" "$tmp"

    # qsConfig in env.lua
    if ! grep -q 'qsConfig.*end4-pC' "$tmp"; then
        sed -i '/hl\.env.*qsConfig/d' "$tmp"
        printf '\nhl.env("qsConfig", "end4-pC")\n' >> "$tmp"
    fi

    # ILLOGICAL_IMPULSE_VIRTUAL_ENV in env.lua
    if ! grep -q 'ILLOGICAL_IMPULSE_VIRTUAL_ENV' "$tmp"; then
        printf '\nhl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", "%s/.local/state/quickshell/.venv")\n' \
            "$TARGET_HOME" >> "$tmp"
    fi

    # Qt draws its own titlebar on Wayland; this drops the decoration and with
    # it the close/maximize/minimize buttons. GTK apps are handled by
    # configure_window_decorations below.
    if [[ $DISABLE_WINDOW_BUTTONS -eq 1 ]] && ! grep -q 'QT_WAYLAND_DISABLE_WINDOWDECORATION' "$tmp"; then
        printf '\nhl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")\n' >> "$tmp"
    fi

    chmod --reference="$envlua" "$tmp" 2>/dev/null || chmod 644 "$tmp"
    mv -f "$tmp" "$envlua"

    # qsConfig in variables.lua (qsConfig is read from here by execs.lua)
    local varslua="$TARGET_HOME/.config/hypr/hyprland/variables.lua"
    if [[ -f "$varslua" ]]; then
        tmp=$(mktemp "${varslua}.XXXXXX")
        cp "$varslua" "$tmp"
        if grep -q 'hl\.env.*qsConfig.*ii' "$tmp"; then
            sed -i 's/hl\.env("qsConfig", "ii")/hl.env("qsConfig", "end4-pC")/' "$tmp"
        elif ! grep -q 'qsConfig.*end4-pC' "$tmp"; then
            printf '\nhl.env("qsConfig", "end4-pC")\n' >> "$tmp"
        fi
        chmod --reference="$varslua" "$tmp" 2>/dev/null || chmod 644 "$tmp"
        mv -f "$tmp" "$varslua"
    fi
}

# ---------------------------------------------------------------------------
# Hyprland Lua config: make the shell's animation overrides load
# ---------------------------------------------------------------------------
patch_hyprland_lua() {
    echo "[install] Patching Hyprland Lua config..."
    # The Lua entrypoint stays at ~/.config/hypr/hyprland.lua: that is the only
    # path Hyprland loads a Lua config from.
    local luafile="$TARGET_HOME/.config/hypr/hyprland.lua"
    [[ -f "$luafile" ]] || return 0

    # Animation presets are written to shellOverrides/animations.lua; without
    # this require the preset selection in the settings has no effect.
    local animfile="$TARGET_HOME/.config/hypr/hyprland/shellOverrides/animations.lua"
    mkdir -p "$(dirname "$animfile")"
    if [[ ! -f "$animfile" ]]; then
        printf -- '-- Animation preset overrides, managed by the end4-pC settings panel.\n' > "$animfile"
        echo "[install] Created $animfile"
    fi

    local need='require("hyprland/shellOverrides/animations")'
    if ! grep -qF "$need" "$luafile"; then
        printf '\n-- end4-pC: animation preset overrides\n%s\n' "$need" >> "$luafile"
        echo "[install] Added animation-override require to $luafile"
    fi
}

# ---------------------------------------------------------------------------
# Hyprland shell autostart: no sleep, no pgrep
# ---------------------------------------------------------------------------
# This checkout does not vendor hyprland.lua, so it cannot be fixed in dots/.
# Patch the deployed entrypoint in place instead. The old line used a fixed
# `sleep 5` and `pgrep -x qs`, which matched the process name instead of the
# config and made the panel appear ~5s late (or duplicate it). `qs -n` is
# Quickshell's --no-duplicate flag and handles both cases by config path.
patch_hyprland_autostart() {
    local luafile="$TARGET_HOME/.config/hypr/hyprland.lua"
    [[ -f "$luafile" ]] || return 0

    python3 "$SCRIPT_DIR/scripts/hyprland/patch-autostart.py" --file "$luafile"
}

# ---------------------------------------------------------------------------
# Window titlebar buttons
# ---------------------------------------------------------------------------
# Hyprland never draws a titlebar: the close/maximize/minimize buttons belong
# to the toolkit the app uses (GTK, Qt, Electron, ...). That is why there is
# no option for them in hyprland.conf, and why the switch lives in the toolkit
# configuration:
#
#   GTK 3/4          gtk-decoration-layout=":"      no buttons, titlebar stays
#   Qt (Wayland)     QT_WAYLAND_DISABLE_WINDOWDECORATION=1  no titlebar at all
#                    (written into hyprland/env.lua by patch_hyprland_env)
#   GNOME/Electron   button-layout="" via gsettings
#
# Apps read these at startup, so they have to be restarted to pick the change
# up. Set DISABLE_WINDOW_BUTTONS=0 to keep the buttons.
configure_window_decorations() {
    if [[ $DISABLE_WINDOW_BUTTONS -ne 1 ]]; then
        echo "[install] Window titlebar buttons: kept (DISABLE_WINDOW_BUTTONS=0)"
        return 0
    fi
    echo "[install] Disabling window titlebar buttons..."

    # An empty layout ("left:right") removes the buttons but keeps the
    # titlebar, which is all GTK offers: the headerbar itself is app UI, not
    # a decoration, and cannot be switched off from the outside.
    local ini
    for ini in "$TARGET_HOME/.config/gtk-3.0/settings.ini" "$TARGET_HOME/.config/gtk-4.0/settings.ini"; do
        mkdir -p "$(dirname "$ini")"
        if [[ ! -f "$ini" ]]; then
            printf '[Settings]\n' > "$ini"
        elif ! grep -q '^\[Settings\]' "$ini"; then
            # GTK ignores keys outside a group, so add the header if missing.
            local tmp
            tmp=$(mktemp "${ini}.XXXXXX")
            { printf '[Settings]\n'; cat "$ini"; } > "$tmp"
            chmod --reference="$ini" "$tmp" 2>/dev/null || chmod 644 "$tmp"
            mv -f "$tmp" "$ini"
        fi
        if grep -q '^gtk-decoration-layout=' "$ini"; then
            sed -i 's|^gtk-decoration-layout=.*|gtk-decoration-layout=:|' "$ini"
        else
            printf 'gtk-decoration-layout=:\n' >> "$ini"
        fi
        chown "$TARGET_USER" "$ini" 2>/dev/null || true
    done

    # Some Electron/Chromium builds read the GNOME setting instead of the GTK
    # one. Best effort: dconf needs the user's D-Bus session, which is not
    # there when the installer runs from a TTY.
    if command -v gsettings >/dev/null 2>&1; then
        local -a gs=(gsettings)
        if [[ $(id -u) -eq 0 ]] && id "$TARGET_USER" &>/dev/null; then
            gs=(sudo -u "$TARGET_USER" gsettings)
        fi
        if ! "${gs[@]}" set org.gnome.desktop.wm.preferences button-layout ':' 2>/dev/null; then
            echo "[install] NOTE: could not write the GNOME button-layout (no D-Bus session)." >&2
            echo "[install]       Run: gsettings set org.gnome.desktop.wm.preferences button-layout ':'" >&2
        fi
    fi
}

# ---------------------------------------------------------------------------
# External application window theming
# ---------------------------------------------------------------------------
# Push the current mode to GTK/Qt apps once at install time so they already
# match the shell before the first dark-mode toggle. The shell keeps them in
# sync afterwards via switchwall.sh.
apply_app_theming() {
    if [[ $APP_THEMING -ne 1 ]]; then
        echo "[install] App window theming: skipped (APP_THEMING=0)"
        return 0
    fi

    local script="$SOURCE_DIR/scripts/theming/app-theming.sh"
    if [[ ! -f "$script" ]]; then
        echo "[install] WARN: app-theming.sh not found — skipping app theming." >&2
        return 0
    fi

    local -a gs=(gsettings)
    if [[ $(id -u) -eq 0 ]] && id "$TARGET_USER" &>/dev/null; then
        gs=(sudo -u "$TARGET_USER" gsettings)
    fi

    local mode="light" scheme=""
    if command -v gsettings >/dev/null 2>&1; then
        scheme=$("${gs[@]}" get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
        [[ "$scheme" == "prefer-dark" ]] && mode="dark"
    fi

    local provisioner="$SOURCE_DIR/scripts/theming/theme-provision.sh"
    if [[ $APP_THEME_PACKAGES -eq 1 && -f "$provisioner" ]]; then
        echo "[install] Detecting compatible app themes..."
        if [[ $(id -u) -eq 0 ]] && id "$TARGET_USER" &>/dev/null; then
            sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" \
                XDG_CONFIG_HOME="$TARGET_HOME/.config" \
                XDG_STATE_HOME="$TARGET_HOME/.local/state" \
                bash "$provisioner" "$mode" --install >/dev/null 2>&1 || true
        else
            bash "$provisioner" "$mode" --install >/dev/null 2>&1 || true
        fi
    fi

    echo "[install] Applying app window theming ($mode)..."
    if [[ $(id -u) -eq 0 ]] && id "$TARGET_USER" &>/dev/null; then
        sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" \
            XDG_CONFIG_HOME="$TARGET_HOME/.config" \
            XDG_STATE_HOME="$TARGET_HOME/.local/state" \
            bash "$script" "$mode" >/dev/null 2>&1 || true
    else
        bash "$script" "$mode" >/dev/null 2>&1 || true
    fi
}

# Qt apps default to Breeze when QT_STYLE_OVERRIDE is unset/breeze, which makes
# Dolphin stay light in dark mode. Switch the Hyprland env to Kvantum; the Qt
# side of app-theming.sh then drives Kvantum's MaterialAdw + qt6ct matugen palette.
# This file is owned by the base install, so back it up before touching it.
apply_qt_style_env() {
    if [[ $APP_THEMING_QT_ENV -ne 1 ]]; then
        echo "[install] Qt style env: skipped (APP_THEMING_QT_ENV=0)"
        return 0
    fi
    local env_file="$TARGET_HOME/.config/hypr/hyprland/env.lua"
    if [[ ! -f "$env_file" ]]; then
        echo "[install] Qt style env: $env_file not found — skipping."
        return 0
    fi
    cp -p "$env_file" "$env_file.app-theming-backup" 2>/dev/null || true
    if grep -q 'QT_STYLE_OVERRIDE' "$env_file"; then
        sed -i -E 's|(QT_STYLE_OVERRIDE"[[:space:]]*,[[:space:]]*")[^"]*(")|\1kvantum\2|' "$env_file"
    else
        printf '\nhl.env("QT_STYLE_OVERRIDE", "kvantum")\n' >> "$env_file"
    fi
    echo "[install] Qt style set to kvantum (log out and back in for running apps)."
}

# Matugen overwrites gtk.css on every apply. A post_hook makes matugen itself
# re-inject the guarded MD3 block, so the layer survives even if applycolor.sh
# fails. Idempotent, backed up, and opt-out.
install_matugen_app_hooks() {
    if [[ $APP_THEMING_MATUGEN_HOOK -ne 1 ]]; then
        echo "[install] Matugen app hooks: skipped (APP_THEMING_MATUGEN_HOOK=0)"
        return 0
    fi
    local cfg="$TARGET_HOME/.config/matugen/config.toml"
    if [[ ! -f "$cfg" ]]; then
        echo "[install] Matugen app hooks: $cfg not found — skipping."
        return 0
    fi
    cp -p "$cfg" "$cfg.app-theming-backup" 2>/dev/null || true
    local script="$TARGET_HOME/.config/quickshell/end4-pC/scripts/theming/app-theming.sh"
    local hook="post_hook = 'bash $script --refresh >/dev/null 2>&1 || true'"
    local section tmp
    for section in templates.gtk3 templates.gtk4; do
        tmp="$(mktemp)"
        awk -v sec="$section" -v hook="$hook" '
            /^\[/ {
                if (insec && !has && !printed) { print hook; printed=1 }
                insec = ($0 == "[" sec "]"); has=0; printed=0; print; next
            }
            insec && /^[[:space:]]*post_hook/ { has=1 }
            { print }
            END { if (insec && !has && !printed) print hook }
        ' "$cfg" > "$tmp"
        mv "$tmp" "$cfg"
    done
    echo "[install] Matugen post-hooks installed for gtk3/gtk4."
}

# ---------------------------------------------------------------------------
# Fish shell
# ---------------------------------------------------------------------------
install_fish_config() {
    echo "[install] Deploying fish config..."
    local src="$DOTS_SOURCE/.config/fish"
    [[ -d "$src" ]] || { echo "[install] WARN: fish source not found at $src"; return; }
    mkdir -p "$TARGET_HOME/.config/fish"
    rsync -av --ignore-existing "$src/" "$TARGET_HOME/.config/fish/"
}

# ---------------------------------------------------------------------------
# Kitty
# ---------------------------------------------------------------------------
install_kitty_config() {
    echo "[install] Deploying kitty config..."
    local src="$DOTS_SOURCE/.config/kitty"
    [[ -d "$src" ]] || { echo "[install] WARN: kitty source not found at $src"; return; }
    mkdir -p "$TARGET_HOME/.config/kitty"
    rsync -av --ignore-existing "$src/" "$TARGET_HOME/.config/kitty/"
}

# ---------------------------------------------------------------------------
# Oh My Posh
# ---------------------------------------------------------------------------
install_omp_config() {
    echo "[install] Deploying oh-my-posh config..."
    local src="$DOTS_SOURCE/.config/atomic.omp.json"
    [[ -f "$src" ]] || { echo "[install] WARN: omp source not found at $src"; return; }
    # The prompt themes live in the themes/ directory: that is the path the
    # fish configuration reads.
    mkdir -p "$TARGET_HOME/.config/oh-my-posh/themes"
    deploy_atomic "$src" "$TARGET_HOME/.config/oh-my-posh/themes/atomic.omp.json"
}

# ---------------------------------------------------------------------------
# Neovim bootstrap (lazy-lock.json triggers lazy.nvim on first launch)
# ---------------------------------------------------------------------------
install_nvim_bootstrap() {
    echo "[install] Deploying neovim bootstrap..."
    local src="$DOTS_SOURCE/.config/nvim/lazy-lock.json"
    [[ -f "$src" ]] || { echo "[install] WARN: lazy-lock.json not found at $src"; return; }
    mkdir -p "$TARGET_HOME/.config/nvim"
    if [[ ! -f "$TARGET_HOME/.config/nvim/lazy-lock.json" ]]; then
        cp "$src" "$TARGET_HOME/.config/nvim/lazy-lock.json"
        if [[ $(id -u) -eq 0 && -n "${TARGET_USER:-}" ]]; then
            chown "$TARGET_USER:" "$TARGET_HOME/.config/nvim/lazy-lock.json" 2>/dev/null || true
        fi
    fi
}

# ---------------------------------------------------------------------------
# Image preview config (fish + nvim)
# ---------------------------------------------------------------------------
# The fish abbreviation and the nvim keymaps/command are shipped as snippets
# and installed into the user's existing configs behind markers, so repeated
# install.sh runs never duplicate them.
install_image_preview_configs() {
    echo "[install] Installing image preview config..."
    local snippets="$SOURCE_DIR/features/image-preview"
    [[ -d "$snippets" ]] || return 0

    mkdir -p "$TARGET_HOME/.config/fish/conf.d"
    deploy_atomic "$snippets/fish.fish" "$TARGET_HOME/.config/fish/conf.d/image-preview.fish"

    mkdir -p "$TARGET_HOME/.config/nvim/lua/plugins"
    deploy_atomic "$snippets/nvim-image.lua" "$TARGET_HOME/.config/nvim/lua/plugins/image.lua"

    local keymaps="$TARGET_HOME/.config/nvim/lua/config/keymaps.lua"
    local marker="end4-pC image-preview keymaps"
    mkdir -p "$(dirname "$keymaps")"
    touch "$keymaps"
    if grep -qF "$marker" "$keymaps"; then
        echo "[install] image preview keymaps already present"
    else
        {
            printf '\n-- >>> %s >>>\n' "$marker"
            cat "$snippets/nvim-keymaps.lua"
            printf -- '-- <<< %s <<<\n' "$marker"
        } >> "$keymaps"
    fi

    if [[ $(id -u) -eq 0 && -n "${TARGET_USER:-}" ]]; then
        chown "$TARGET_USER:" "$TARGET_HOME/.config/fish/conf.d/image-preview.fish" \
            "$TARGET_HOME/.config/nvim/lua/plugins/image.lua" "$keymaps" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Peek config (fish + nvim)
# ---------------------------------------------------------------------------
# The fish function and the nvim keymaps are shipped as snippets and appended
# behind markers so repeated install.sh runs never duplicate them.
install_peek_configs() {
    echo "[install] Installing peek config..."
    local snippets="$SOURCE_DIR/features/peek"
    [[ -d "$snippets" ]] || return 0

    mkdir -p "$TARGET_HOME/.config/fish/conf.d"
    deploy_atomic "$snippets/fish.fish" "$TARGET_HOME/.config/fish/conf.d/peek.fish"

    local keymaps="$TARGET_HOME/.config/nvim/lua/config/keymaps.lua"
    local marker="end4-pC peek keymaps"
    mkdir -p "$(dirname "$keymaps")"
    touch "$keymaps"
    if grep -qF "$marker" "$keymaps"; then
        echo "[install] peek keymaps already present"
    else
        {
            printf '\n-- >>> %s >>>\n' "$marker"
            cat "$snippets/nvim-keymaps.lua"
            printf -- '-- <<< %s <<<\n' "$marker"
        } >> "$keymaps"
    fi

    if [[ $(id -u) -eq 0 && -n "${TARGET_USER:-}" ]]; then
        chown "$TARGET_USER:" "$TARGET_HOME/.config/fish/conf.d/peek.fish" \
            "$keymaps" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Python venv
# ---------------------------------------------------------------------------
# Pre-download the whisper 'base' model so the first STT use is not delayed.
# Needs network access; the model is cached in ~/.cache/huggingface.
# Set SKIP_STT_MODEL_DOWNLOAD=1 to skip it.
warm_stt_model() {
    local venv="$1"
    if [[ "${SKIP_STT_MODEL_DOWNLOAD:-0}" == "1" ]]; then
        echo "[install] SKIP_STT_MODEL_DOWNLOAD=1 set, skipping whisper model download."
        return 0
    fi
    if [[ ${OFFLINE:-0} -eq 1 ]]; then
        echo "[install] Offline mode: skipping whisper model download (no network access)."
        echo "[install] The first speech-to-text use will need the model cached in ~/.cache/huggingface."
        return 0
    fi
    echo "[install] Pre-downloading the whisper 'base' model (needs network access)..."
    echo "[install] The model cache lives in ~/.cache/huggingface"
    if "$venv/bin/python" -c "from faster_whisper import WhisperModel; WhisperModel('base', device='cpu', compute_type='int8')" >/dev/null 2>&1; then
        echo "[install] Whisper 'base' model is ready."
    else
        echo "[install] WARNING: could not pre-download the whisper model." >&2
        echo "[install] The first speech-to-text use will retry the download (network access required)." >&2
    fi
    return 0
}

install_python_venv() {
    echo "[install] Setting up Python venv..."
    local venv="$TARGET_HOME/.local/state/quickshell/.venv"
    mkdir -p "$(dirname "$venv")"
    # Only create the venv when it is missing, so that an existing one is
    # repaired instead of being recreated. The dependency install below runs
    # either way, which is what fixes a venv that predates faster-whisper.
    if [[ ! -x "$venv/bin/python" ]]; then
        python3 -m venv "$venv"
    fi
    if [[ ${OFFLINE:-0} -eq 1 ]]; then
        # Never touch the network: no pip upgrade, no plain pip install.
        if [[ -n "${OFFLINE_WHEELHOUSE:-}" && -d "$OFFLINE_WHEELHOUSE" ]]; then
            echo "[install] Offline mode: installing Python deps from wheelhouse: $OFFLINE_WHEELHOUSE"
            if ! "$venv/bin/pip" install --no-index --find-links="$OFFLINE_WHEELHOUSE" \
                pillow materialyoucolor loguru tqdm numpy opencv-python faster-whisper; then
                echo "[install] WARNING: wheelhouse install failed; some Python modules may be missing." >&2
            fi
        else
            if [[ -n "${OFFLINE_WHEELHOUSE:-}" ]]; then
                echo "[install] WARN: wheelhouse '$OFFLINE_WHEELHOUSE' does not exist; checking imports instead." >&2
            fi
            # Offline, no wheelhouse: only check that the required modules
            # import. A missing module is reported but never aborts the install.
            local module missing=""
            for module in PIL materialyoucolor loguru tqdm numpy cv2 faster_whisper; do
                if ! "$venv/bin/python" -c "import $module" >/dev/null 2>&1; then
                    missing+="$module "
                fi
            done
            if [[ -n "$missing" ]]; then
                echo "[install] Offline mode: missing Python modules in $venv: ${missing% }" >&2
                echo "[install]          Installed features that need them may not work until the" >&2
                echo "[install]          packages are available (e.g. via a wheelhouse)." >&2
            fi
        fi
    else
        "$venv/bin/pip" install --upgrade pip
        "$venv/bin/pip" install pillow materialyoucolor loguru tqdm numpy opencv-python faster-whisper
    fi
    # Fail loudly when the speech to text backend cannot run, instead of only
    # finding out at the first recording.
    if ! "$venv/bin/python" -c "import faster_whisper" >/dev/null 2>&1; then
        echo "[install] WARNING: faster-whisper is not importable in $venv - speech to text will not work." >&2
    fi
    warm_stt_model "$venv"
}

# ---------------------------------------------------------------------------
# illogical-impulse config seed
# ---------------------------------------------------------------------------
install_ii_config() {
    echo "[install] Seeding illogical-impulse config..."
    local cfg="$TARGET_HOME/.config/illogical-impulse/config.json"
    [[ -f "$cfg" ]] && { echo "[install] Config already exists, skipping seed."; return; }
    mkdir -p "$(dirname "$cfg")"
    cat > "$cfg" << 'JSONEOF'
{
  "background": {
    "wallpaperPath": "~/.config/quickshell/end4-pC/assets/images/default_wallpaper.png"
  },
  "appearance": {
    "palette": {
      "seed": "#6B4C9A",
      "namedScheme": ""
    },
    "wallpaperTheming": {
      "enableQtApps": true
    }
  }
}
JSONEOF
    if [[ $(id -u) -eq 0 && -n "${TARGET_USER:-}" ]]; then
        chown "$TARGET_USER:" "$cfg" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# SDDM greeter
# ---------------------------------------------------------------------------
install_sddm_theme() {
    require_sudo "the SDDM greeter" || return 0
    echo "[install] Installing SDDM greeter..."
    # The shared helper also registers the theme in /etc/sddm.conf.d, which
    # the old installer never did. It merges that drop-in instead of
    # overwriting it, so per-machine keys survive a reinstall.
    local args=()
    [[ $RELOAD_SDDM -eq 1 ]] && args+=(--reload-sddm)
    env END4PC_SOURCE_DIR="$SOURCE_DIR" \
        END4PC_TARGET_HOME="$TARGET_HOME" \
        END4PC_TARGET_USER="$TARGET_USER" \
        END4PC_ELEVATE="$ELEVATE" \
        "$SOURCE_DIR/scripts/sddm/deploy-theme.sh" "${args[@]}" \
        || echo "[install] WARN: SDDM theme deployment failed" >&2
}

# ---------------------------------------------------------------------------
# Wallpaper sync script
# ---------------------------------------------------------------------------
install_wallpaper_sync() {
    echo "[install] Deploying wallpaper sync script..."
    local sync_dest="$TARGET_HOME/.config/ii-sddm-theme/sddm-wallpaper-sync.sh"
    mkdir -p "$(dirname "$sync_dest")"

    # An already deployed hook is user-owned state (it may carry local edits),
    # so never overwrite it with the embedded copy.
    if [[ -f "$sync_dest" ]]; then
        echo "[install] Keeping existing wallpaper sync hook: $sync_dest"
    else
        # Write the known-good version directly, but atomically: the script is
        # executed by the wallpaper switch, so it must never be observed
        # half-written.
        local tmp
        tmp=$(mktemp "${sync_dest}.XXXXXX")
        cat > "$tmp" << 'SYNC_EOF'
#!/usr/bin/env bash
set -euo pipefail

# The installer injects the resolved target home below. Deriving it at
# runtime from sudo/XDG used to fall back to a developer-specific path.
USER_HOME="__END4PC_TARGET_HOME__"
CONFIG_FILE="$USER_HOME/.config/illogical-impulse/config.json"
LAST_STATIC_MARKER="$USER_HOME/.config/ii-sddm-theme/last_static_wallpaper"
SDDM_THEME="/usr/share/sddm/themes/ii-sddm-theme"
SDDM_BACKGROUNDS="$SDDM_THEME/Backgrounds"
SDDM_CONF="$SDDM_THEME/Themes/ii-sddm.conf"
IMAGE_EXTS=("png" "jpg" "jpeg" "webp" "gif" "bmp")
VIDEO_EXTS=("mp4" "mkv" "mov" "webm" "m4v" "avi" "wmv" "flv" "ogv" "3gp" "gif" "qt")

log_info()  { echo "[sddm-wallpaper-sync] INFO: $*" >&2; }
log_warn()  { echo "[sddm-wallpaper-sync] WARN: $*" >&2; }
log_error() { echo "[sddm-wallpaper-sync] ERROR: $*" >&2; }

is_image() {
    local ext="${1##*.}"; ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    for e in "${IMAGE_EXTS[@]}"; do [[ "$ext" == "$e" ]] && return 0; done; return 1
}
is_video() {
    local ext="${1##*.}"; ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    for e in "${VIDEO_EXTS[@]}"; do [[ "$ext" == "$e" ]] && return 0; done; return 1
}
get_wallpaper_path() { jq -r '.background.wallpaperPath // empty' "$CONFIG_FILE" 2>/dev/null; }

main() {
    [ ! -f "$CONFIG_FILE" ] && { log_error "Config not found: $CONFIG_FILE"; exit 1; }
    wallpaper_path=$(get_wallpaper_path) || true
    [ -z "$wallpaper_path" ] || [ "$wallpaper_path" == "null" ] && { log_warn "No wallpaper path in $CONFIG_FILE"; exit 1; }
    wallpaper_path="${wallpaper_path/#\~/$USER_HOME}"
    [[ "$wallpaper_path" != /* ]] && { log_error "Wallpaper path not absolute: $wallpaper_path"; exit 1; }
    log_info "Wallpaper: $wallpaper_path"

    if is_video "$wallpaper_path"; then
        log_info "Video wallpaper, using last static"
        [ ! -f "$LAST_STATIC_MARKER" ] && { log_warn "No last-static marker"; exit 1; }
        wallpaper_path=$(cat "$LAST_STATIC_MARKER") || true
        [ ! -f "$wallpaper_path" ] && { log_warn "Last static missing: $wallpaper_path"; exit 1; }
        log_info "Using last static: $wallpaper_path"
    fi

    is_image "$wallpaper_path" || { log_error "Unsupported wallpaper type: $wallpaper_path"; exit 1; }
    [ ! -f "$wallpaper_path" ] && { log_error "Wallpaper file not found: $wallpaper_path"; exit 1; }

    local ext="${wallpaper_path##*.}"; ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    local dest_path="$SDDM_BACKGROUNDS/background.${ext}"
    local conf_background="Backgrounds/background.${ext}"

    if [ "$(id -u)" = "0" ]; then
        mkdir -p -m 755 "$SDDM_BACKGROUNDS"
        cp --preserve=mode,timestamps "$wallpaper_path" "$dest_path"
        chmod 644 "$dest_path"
        sed -i \
            -e "s|^Background=\"Backgrounds/background\.[^\"]*\"|Background=\"$conf_background\"|" \
            -e "s|^Background=\"Backgrounds/[^\"]*\"|Background=\"$conf_background\"|" \
            "$SDDM_CONF"
    else
        sudo mkdir -p -m 755 "$SDDM_BACKGROUNDS"
        sudo cp --preserve=mode,timestamps "$wallpaper_path" "$dest_path"
        sudo chmod 644 "$dest_path"
        sudo sed -i \
            -e "s|^Background=\"Backgrounds/background\.[^\"]*\"|Background=\"$conf_background\"|" \
            -e "s|^Background=\"Backgrounds/[^\"]*\"|Background=\"$conf_background\"|" \
            "$SDDM_CONF"
    fi
    echo "$wallpaper_path" > "$LAST_STATIC_MARKER"
    log_info "Synced: $wallpaper_path → $conf_background"
}

main "$@"
SYNC_EOF
        # Inline the resolved target home; escaping keeps unusual paths safe.
        escaped_home=${TARGET_HOME//\\/\\\\}
        escaped_home=${escaped_home//&/\\&}
        escaped_home=${escaped_home//|/\\|}
        sed -i "s|__END4PC_TARGET_HOME__|$escaped_home|" "$tmp"
        chmod 755 "$tmp"
        mv -f "$tmp" "$sync_dest"
    fi
    chmod +x "$sync_dest"

    # Sudoers rule — target user needs passwordless sudo for the sync script
    local sudoers_file="/etc/sudoers.d/sddm-wallpaper-sync-$TARGET_USER"
    if [[ ! -f "$sudoers_file" ]]; then
        if require_sudo "the SDDM wallpaper sync sudoers rule"; then
            $ELEVATE tee "$sudoers_file" > /dev/null << EOF
$TARGET_USER ALL=(ALL) NOPASSWD: $sync_dest
EOF
            $ELEVATE chmod 440 "$sudoers_file"
        fi
    fi

    # Hook into switchwall.sh: refresh the greeter wallpaper once switch() has
    # written the new wallpaperPath into the shell config.
    local switchwall="$TARGET_HOME/.config/quickshell/end4-pC/scripts/colors/switchwall.sh"
    if [[ -f "$switchwall" ]]; then
        if ! grep -q 'sddm-wallpaper-sync.sh' "$switchwall"; then
            local switch_line
            switch_line=$(grep -n '^    switch "\$imgpath"' "$switchwall" | tail -1 | cut -d: -f1)
            if [[ -n "$switch_line" ]]; then
                local tmp
                local orig_mode
                orig_mode=$(stat -c '%a' "$switchwall")
                tmp=$(mktemp)
                head -n "$switch_line" "$switchwall" > "$tmp"
                # sudo -n: the NOPASSWD sudoers rule covers this script, and its
                # root branch then avoids any password prompt from the desktop.
                printf '\n# SDDM wallpaper sync (installed by end4-pC install.sh)\nsudo -n %s &\n' "$sync_dest" >> "$tmp"
                tail -n +"$((switch_line + 1))" "$switchwall" >> "$tmp"
                mv "$tmp" "$switchwall"
                # mktemp creates the file with mode 600: the script has to stay
                # executable and readable for the desktop user.
                chmod "$orig_mode" "$switchwall"
                chown "$TARGET_USER" "$switchwall" 2>/dev/null || true
            else
                echo "[install] WARN: switch() invocation not found in $switchwall; wallpaper sync hook not installed" >&2
            fi
        fi
    fi
}

# ---------------------------------------------------------------------------
# Fonts
# ---------------------------------------------------------------------------
install_fonts() {
    echo "[install] Installing fonts..."
    local font_dir="$TARGET_HOME/.local/share/fonts"
    mkdir -p "$font_dir"
    if [[ -d "$SOURCE_DIR/assets/fonts" ]]; then
        find "$SOURCE_DIR/assets/fonts" -name '*.ttf' -exec cp {} "$font_dir/" \;
        if [[ $(id -u) -eq 0 && -n "${TARGET_USER:-}" ]]; then
            chown "$TARGET_USER:" "$font_dir"/*.ttf 2>/dev/null || true
        fi
    fi
    fc-cache -f "$font_dir" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Verify (smoke test)
# ---------------------------------------------------------------------------
verify() {
    echo ""
    echo "[install] Running smoke checks..."
    local ok=0
    local fail=0

    check() {
        local label="$1"; shift
        if "$@"; then
            echo "  ✓ $label"
            ((ok++))
        else
            echo "  ✗ $label"
            ((fail++))
        fi
    }

    check "~/.config/quickshell/end4-pC/shell.qml exists" \
        test -f "$TARGET_HOME/.config/quickshell/end4-pC/shell.qml"
    check "generated main keybinds.lua exists" \
        test -f "$TARGET_HOME/.config/hypr/hyprland/keybinds.lua"
    check "generated custom keybinds.lua exists" \
        test -f "$TARGET_HOME/.config/hypr/custom/keybinds.lua"
    check "generated command bridge JSON exists" \
        test -f "$TARGET_HOME/.config/quickshell/end4-pC/state/generated-commands.json"
    check "command bridge JSON is non-empty" \
        python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d,dict) and len(d)>0 else 1)' \
        "$TARGET_HOME/.config/quickshell/end4-pC/state/generated-commands.json"
    check "~/.config/fish/config.fish exists" \
        test -f "$TARGET_HOME/.config/fish/config.fish"
    check "~/.config/kitty/kitty.conf exists" \
        test -f "$TARGET_HOME/.config/kitty/kitty.conf"
    check "~/.config/oh-my-posh/themes/atomic.omp.json exists" \
        test -f "$TARGET_HOME/.config/oh-my-posh/themes/atomic.omp.json"
    check "~/.config/illogical-impulse/config.json exists" \
        test -f "$TARGET_HOME/.config/illogical-impulse/config.json"
    check "~/.local/state/quickshell/.venv exists" \
        test -d "$TARGET_HOME/.local/state/quickshell/.venv"
    check "~/.config/ii-sddm-theme/sddm-wallpaper-sync.sh exists" \
        test -f "$TARGET_HOME/.config/ii-sddm-theme/sddm-wallpaper-sync.sh"
    if [[ $DISABLE_WINDOW_BUTTONS -eq 1 ]]; then
        check "window buttons disabled (GTK 3)" \
            grep -q '^gtk-decoration-layout=:' "$TARGET_HOME/.config/gtk-3.0/settings.ini"
        check "window buttons disabled (GTK 4)" \
            grep -q '^gtk-decoration-layout=:' "$TARGET_HOME/.config/gtk-4.0/settings.ini"
        check "window buttons disabled (Qt env)" \
            grep -q 'QT_WAYLAND_DISABLE_WINDOWDECORATION' "$TARGET_HOME/.config/hypr/hyprland/env.lua"
    fi

    echo ""
    echo "[install] Smoke check: $ok passed, $fail failed"
    return $fail
}

# ---------------------------------------------------------------------------
# Config compile check
# ---------------------------------------------------------------------------
# A QML file that does not compile takes down every type that imports it,
# and with it the whole shell.
#
# The config that is about to be deployed is compared with the one that is
# currently deployed: a new problem aborts the deploy, a problem that is
# already deployed does not, so known work in progress does not block an
# install.
# Options and their defaults are parsed and validated at the top of the script
# (see "Command line"), before any deployment step runs.

check_config_compiles() {
    local src="$1" dest="$2"

    if [[ $SKIP_CHECKS -eq 1 ]]; then
        echo "[install] Skipping the config compile check (--skip-checks)"
        return 0
    fi
    if [[ ! -x "$SOURCE_DIR/tests/qml-compile-check.sh" ]]; then
        return 0
    fi

    local errors
    errors=$(cd "$SOURCE_DIR" && ./tests/qml-compile-check.sh "$src" 2>/dev/null | grep -v "^PASS:")
    if [[ -z "$errors" ]]; then
        echo "[install] Config compile check: ok"
        return 0
    fi

    # For every file that fails, the deployed copy is checked as well. A
    # problem that is already deployed is not new, so it does not block the
    # install; only a problem that the shell would not survive does.
    local introduced="" file message source_messages deployed_messages
    while IFS= read -r error; do
        file="${error%%:*}"
        file="${file#"$src"/}"
        source_messages=$(printf '%s\n' "$errors" | grep -F ": " | grep "^$src/$file: " \
            | sed -E "s|^[^:]+: ||" | sort -u)
        deployed_messages=""
        if [[ -f "$dest/$file" ]]; then
            deployed_messages=$(cd "$SOURCE_DIR" && ./tests/qml-compile-check.sh "$dest/$file" 2>/dev/null \
                | grep -v "^PASS:" | sed -E "s|^[^:]+: ||" | sort -u)
        fi
        while IFS= read -r message; do
            [[ -z "$message" ]] && continue
            if ! printf '%s\n' "$deployed_messages" | grep -qxF "$message"; then
                introduced+="$file: $message"$'\n'
            fi
        done <<< "$source_messages"
    done <<< "$errors"

    if [[ -z "$introduced" ]]; then
        echo "[install] Config compile check: only problems that are already deployed"
        printf '%s\n' "$errors" | sed 's/^/  /'
        return 0
    fi

    echo "[install] ERROR: the config does not compile:" >&2
    printf '%s' "$introduced" | sed 's/^/  /' >&2
    echo "[install] The shell would not start with this. Fix the errors, or" >&2
    echo "[install] deploy with --skip-checks if they are known." >&2
    return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    resolve_target_home
    banner

    # Show the effective options before the first write, so a typo in an
    # environment variable is visible even when it happens to be valid.
    echo "[install] Options: offline=$OFFLINE skip-checks=$SKIP_CHECKS"
    echo "[install]          window-buttons-kept=$((1 - DISABLE_WINDOW_BUTTONS)) app-theming=$APP_THEMING"
    echo "[install]          waydroid=$WITH_WAYDROID vnc=$WITH_VNC"
    if [[ $WITH_VNC -eq 1 ]]; then
        echo "[install]          vnc-mode=$VNC_MODE vnc-audio=$VNC_AUDIO vnc-autologin=$VNC_AUTOLOGIN"
    fi

    # Before anything is changed: a config that does not compile takes the
    # shell down, so it is checked first.
    check_config_compiles "$SOURCE_DIR" "$TARGET_HOME/.config/quickshell/end4-pC" || exit 1

    install_packages
    install_qs_config
    install_lock_guard
    install_hyprland_config
    install_keybind_defaults
    patch_hyprland_env
    patch_hyprland_lua
    patch_hyprland_autostart
    configure_window_decorations
    install_fish_config
    install_kitty_config
    install_omp_config
    install_nvim_bootstrap
    install_image_preview_configs
    install_peek_configs
    install_python_venv
    install_ii_config
    apply_app_theming
    apply_qt_style_env
    install_matugen_app_hooks
    install_sddm_theme
    install_wallpaper_sync
    install_fonts

    # Optional Waydroid setup — only with an explicit --with-waydroid flag.
    # Standalone script; never runs on a plain install. A failure is loud but
    # does not abort the desktop install (it is an add-on, not a dependency).
    if [[ ${WITH_WAYDROID:-0} -eq 1 ]]; then
        echo "[install] Optional component: Waydroid (--with-waydroid)"
        if ! "$SOURCE_DIR/optional/waydroid/install-waydroid.sh"; then
            echo "[install] WARN: Waydroid setup failed — see [waydroid] messages above." >&2
            echo "[install]       Rerun: ./optional/waydroid/install-waydroid.sh" >&2
        fi
    fi

    # Optional VNC/remote-desktop setup — only with --with-vnc.
    # This is an add-on and does not block the desktop install on failure.
    if [[ ${WITH_VNC:-0} -eq 1 ]]; then
        echo "[install] Optional component: VNC remote desktop (--with-vnc)"
        if ! env VNC_MODE="$VNC_MODE" VNC_AUDIO="$VNC_AUDIO" VNC_AUTOLOGIN="$VNC_AUTOLOGIN" \
            "$SOURCE_DIR/optional/vnc/install-vnc.sh"; then
            echo "[install] WARN: VNC setup failed — see [vnc] messages above." >&2
            echo "[install]       Rerun: ./optional/vnc/install-vnc.sh" >&2
        fi
    fi

    echo ""
    echo "[install] ============================================================"
    echo "[install]  Installation complete!"
    echo "[install]  Installed to: ~$TARGET_USER"
    echo "[install] ============================================================"
    echo ""
    echo "Next steps:"
    echo "  1. Start Hyprland (log out and select Hyprland session in SDDM)"
    echo "  2. On first launch, run: nvim (to bootstrap lazy.nvim plugins)"
    echo "  3. Press Super+/ to see keybindings"
    echo ""

    if verify; then
        echo "[install] All smoke checks passed."
    else
        echo "[install] Some smoke checks failed — review above."
    fi
}

main "$@"
