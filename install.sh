#!/usr/bin/env bash
#
# install.sh — end4-pC full setup installer
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR="$SCRIPT_DIR"          # end4-pC root
DOTS_SOURCE="$SCRIPT_DIR/dots"                 # vendored dotfiles + Hyprland config

# ---------------------------------------------------------------------------
# Root / target-user detection
# ---------------------------------------------------------------------------
resolve_target_home() {
    if [[ $(id -u) -eq 0 ]]; then
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
}

# ---------------------------------------------------------------------------
# Quickshell config
# ---------------------------------------------------------------------------
install_qs_config() {
    echo "[install] Deploying Quickshell config..."
    local dest="$TARGET_HOME/.config/quickshell/end4-pC"
    mkdir -p "$(dirname "$dest")"
    rsync -av --delete --exclude '/dots/' --exclude '/.omp/' --exclude '/file:/' "$SOURCE_DIR/" "$dest/"

    # Patch QUICKSHELL_CONFIG_NAME="ii" → "end4-pC" in installed scripts
    find "$dest/scripts" -type f -name '*.sh' -print0 | while IFS= read -r -d '' f; do
        if grep -q 'QUICKSHELL_CONFIG_NAME="ii"' "$f" 2>/dev/null; then
            sed -i 's/QUICKSHELL_CONFIG_NAME="ii"/QUICKSHELL_CONFIG_NAME="end4-pC"/g' "$f"
        fi
    done
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
    rsync -a --delete --exclude 'shellOverrides' "$src/hyprland/" "$dest/hyprland/"
    rsync -a --delete "$src/hyprlock/" "$dest/hyprlock/"
    rsync -a --delete "$src/scripts/" "$dest/scripts/"
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
    [[ -f "$TARGET_HOME/.config/nvim/lazy-lock.json" ]] || cp "$src" "$TARGET_HOME/.config/nvim/lazy-lock.json"
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
    "$venv/bin/pip" install --upgrade pip
    "$venv/bin/pip" install pillow materialyoucolor loguru tqdm numpy opencv-python faster-whisper
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
}

# ---------------------------------------------------------------------------
# SDDM greeter
# ---------------------------------------------------------------------------
install_sddm_theme() {
    echo "[install] Installing SDDM greeter..."
    local theme_dest="/usr/share/sddm/themes/ii-sddm-theme"
    require_sudo "the SDDM greeter" || return 0
    if [[ ! -d "$theme_dest" ]]; then
        if [[ -d "$SOURCE_DIR/ii-sddm-theme" ]]; then
            $ELEVATE cp -r "$SOURCE_DIR/ii-sddm-theme" "$theme_dest"
        elif [[ -d "$SOURCE_DIR/../ii-sddm-theme" ]]; then
            $ELEVATE cp -r "$SOURCE_DIR/../ii-sddm-theme" "$theme_dest"
        else
            echo "[install] WARN: ii-sddm-theme source not found, skipping system install"
        fi
    fi

    # Ensure backgrounds dir exists
    $ELEVATE mkdir -p "$theme_dest/Backgrounds"

    # Copy current wallpaper to SDDM backgrounds if not already synced
    if [[ -f "$TARGET_HOME/.config/ii-sddm-theme/last_static_wallpaper" ]]; then
        local cur_wp
        cur_wp=$(cat "$TARGET_HOME/.config/ii-sddm-theme/last_static_wallpaper" 2>/dev/null || echo "")
        if [[ -n "$cur_wp" && -f "$cur_wp" ]]; then
            local ext="${cur_wp##*.}"
            $ELEVATE cp --preserve=mode,timestamps "$cur_wp" "$theme_dest/Backgrounds/background.${ext}"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Wallpaper sync script
# ---------------------------------------------------------------------------
install_wallpaper_sync() {
    echo "[install] Deploying wallpaper sync script..."
    local sync_dest="$TARGET_HOME/.config/ii-sddm-theme/sddm-wallpaper-sync.sh"
    mkdir -p "$(dirname "$sync_dest")"

    # Use the sddm-wallpaper-sync.sh from current user's home if it exists,
    # otherwise embed the known good version.
    if [[ -f "$TARGET_HOME/.config/ii-sddm-theme/sddm-wallpaper-sync.sh" ]]; then
        # Skip if source and destination are the same (already deployed)
        if [[ "$TARGET_HOME/.config/ii-sddm-theme/sddm-wallpaper-sync.sh" != "$sync_dest" ]]; then
            cp "$TARGET_HOME/.config/ii-sddm-theme/sddm-wallpaper-sync.sh" "$sync_dest"
        fi
    else
        # Write the known-good version directly, but atomically: the script is
        # executed by the wallpaper switch, so it must never be observed
        # half-written.
        local tmp
        tmp=$(mktemp "${sync_dest}.XXXXXX")
        cat > "$tmp" << 'SYNC_EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ -n "${SUDO_USER:-}" ]; then
    USER_HOME="$(eval echo "~$SUDO_USER")"
elif [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    runtime_uid=$(basename "$XDG_RUNTIME_DIR")
    USER_HOME="$(getent passwd "$runtime_uid" | cut -d: -f6)" || true
    [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ] && USER_HOME="/home/dmitriy"
else
    USER_HOME="/home/dmitriy"
fi
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
SKIP_CHECKS=0
for arg in "$@"; do
    case "$arg" in
        --skip-checks) SKIP_CHECKS=1 ;;
    esac
done

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

    # Before anything is changed: a config that does not compile takes the
    # shell down, so it is checked first.
    check_config_compiles "$SOURCE_DIR" "$TARGET_HOME/.config/quickshell/end4-pC" || exit 1

    install_packages
    install_qs_config
    install_hyprland_config
    patch_hyprland_env
    patch_hyprland_lua
    install_fish_config
    install_kitty_config
    install_omp_config
    install_nvim_bootstrap
    install_python_venv
    install_ii_config
    install_sddm_theme
    install_wallpaper_sync
    install_fonts

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
