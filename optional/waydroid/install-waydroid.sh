#!/usr/bin/env bash
#
# install-waydroid.sh — optional Waydroid setup for end4-pC (archpc-style).
#
# Standalone and idempotent: safe to run repeatedly; every step is a no-op
# when its end state already exists. Also invoked by install.sh when run with
# --with-waydroid (never on a plain install).
#
# What it does:
#   1. Ensures a waydroid package is installed
#      - NVIDIA GPU  -> AUR waydroid-a17-nvidia-bin fork (Android 17, NV accel)
#      - otherwise   -> stock waydroid (extra repo), GAPPS like archpc
#   2. Ensures system images exist and runs init
#      - fork  : stages WayDroid-ATV GAPPS system.img + packaged vendor.img
#                into /etc/waydroid-extra/images (the fork's init auto-detects
#                that dir) then `waydroid init -f`, then waydroid-nvidia-setup
#      - stock : `waydroid init -s GAPPS` (official GAPPS channel)
#   3. Makes the system.img filesystem mountable
#      - ATV images are EROFS: if the running kernel lacks the erofs module
#        (partial upgrade: modules dir of the running kernel removed), fall
#        back to `erofsfuse` so /sbin/mount.erofs works. After the next reboot
#        into the installed kernel the module autoloads natively.
#   4. Reconciles /var/lib/waydroid/waydroid.cfg (archpc parity):
#        suspend_action=freeze, background_start=true
#      and repairs the fork's vendor_ota when its GitHub release URL 404s
#      (points it at the JSON shipped inside the package via file://).
#   5. Injects the Hyprland snippets (autostart / window rules / keybinds)
#      into ~/.config/hypr/custom/*.lua — marker-guarded, appended once.
#   6. Starts the Waydroid session (needs a Wayland socket) and, on the fork,
#      enables per-app windows (persist.waydroid.multi_windows).
#   7. Regenerates .desktop entries for installed Android apps (fallback:
#      scripts/waydroid-desktop-gen.sh in the quickshell tree).
#   8. Verifies: session RUNNING, apps listed, Play Store present on GAPPS.
#
# Root usage: uses `sudo` when not root. On this machine sudo is NOPASSWD for
# tee/mkdir/install/chmod/pacman/systemctl — the cfg edits and package installs
# therefore run passwordless; `waydroid init` / `waydroid-nvidia-setup` still
# prompt (run from a terminal for those).
#
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

# WayDroid-ATV GAPPS system build the nvidia fork pairs with (fork README pin).
ATV_TAG="${WAYDROID_ATV_TAG:-20261017}"
ATV_SYSTEM_URL="https://github.com/WayDroid-ATV/waydroid-builds/releases/download/${ATV_TAG}/lineage-24.0-${ATV_TAG}-GAPPS-waydroid_x86_64-system.zip"

# ---------------------------------------------------------------------------
# Target user (same rules install.sh uses: sudo -> SUDO_USER)
# ---------------------------------------------------------------------------
if [[ -n "${TARGET_HOME:-}" && -n "${TARGET_USER:-}" ]]; then
    :
elif [[ $(id -u) -eq 0 && -n "${SUDO_USER:-}" ]]; then
    TARGET_USER="$SUDO_USER"
    TARGET_HOME=$(eval echo "~$SUDO_USER")
else
    TARGET_USER="$(id -un)"
    TARGET_HOME="$HOME"
fi
TARGET_UID=$(id -u "$TARGET_USER")
CUSTOM_DIR="$TARGET_HOME/.config/hypr/custom"
SNIPPET_SRC="$SCRIPT_DIR/hyprland"

log()  { echo "[waydroid] $*"; }
warn() { echo "[waydroid] WARN: $*" >&2; }

# Root helper: empty when already root, otherwise sudo (NOPASSWD subset works
# passwordless; remaining commands prompt when run from a terminal).
if [[ $(id -u) -eq 0 ]]; then ROOT=""; else ROOT="sudo"; fi

run_as_target() {
    # Run a command as the desktop user with their runtime env (session
    # commands must never run as root).
    if [[ $(id -u) -eq "$TARGET_UID" ]]; then
        env "$@"
    else
        sudo -u "$TARGET_USER" env XDG_RUNTIME_DIR="/run/user/$TARGET_UID" "$@"
    fi
}

# ---------------------------------------------------------------------------
# 1. Package
# ---------------------------------------------------------------------------
has_nvidia() { lspci 2>/dev/null | grep -qi "nvidia"; }

install_package() {
    if command -v waydroid >/dev/null 2>&1; then
        log "waydroid already installed: $(pacman -Q waydroid-a17-nvidia-bin 2>/dev/null || pacman -Q waydroid 2>/dev/null || echo 'unknown package')"
        return 0
    fi
    if has_nvidia; then
        local helper=""
        for c in yay paru; do command -v "$c" >/dev/null 2>&1 && { helper="$c"; break; }; done
        if [[ -n "$helper" ]]; then
            log "installing NVIDIA fork via $helper: waydroid-a17-nvidia-bin"
            run_as_target "$helper" -S --noconfirm --needed waydroid-a17-nvidia-bin
        else
            warn "NVIDIA GPU detected but no yay/paru. Install the fork manually:"
            warn "  yay -S waydroid-a17-nvidia-bin    (Android 17 + NVIDIA acceleration)"
            warn "  (stock 'pacman -S waydroid' has poor/no NVIDIA support)"
            return 1
        fi
    else
        log "installing stock waydroid (GAPPS like archpc)"
        $ROOT pacman -S --noconfirm --needed waydroid
    fi
    command -v waydroid >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# 2. Images + init
# ---------------------------------------------------------------------------
is_fork() { pacman -Q waydroid-a17-nvidia-bin >/dev/null 2>&1; }

stage_fork_images() {
    local imgdir=/etc/waydroid-extra/images
    local syszip=/usr/lib/waydroid-nvidia/vendor
    if [[ -f "$imgdir/system.img" && -f "$imgdir/vendor.img" ]]; then
        log "preinstalled images already staged in $imgdir"
        return 0
    fi
    log "staging WayDroid-ATV ${ATV_TAG} GAPPS system + packaged vendor into $imgdir"
    local tmp; tmp=$(mktemp -d)
    # system image (ATV build, ~1.5 GB — the nvidia vendor is Android 17 and
    # does NOT work with official lineage-20 images: VINTF/libvintf mismatch
    # makes system_server bootloop).
    if ! curl -sfL --max-time 600 -o "$tmp/system.zip" "$ATV_SYSTEM_URL"; then
        warn "download failed: $ATV_SYSTEM_URL"
        rm -rf "$tmp"; return 1
    fi
    bsdtar -xf "$tmp/system.zip" -C "$tmp" system.img || { rm -rf "$tmp"; return 1; }
    # vendor image shipped inside the installed AUR package
    local vendor_zip
    vendor_zip=$(ls "$syszip"/waydroid-nvidia-vendor-x86_64-*.zip 2>/dev/null | head -1)
    if [[ -z "$vendor_zip" ]]; then
        warn "packaged vendor zip not found under $syszip"; rm -rf "$tmp"; return 1
    fi
    bsdtar -xf "$vendor_zip" -C "$tmp" vendor.img || { rm -rf "$tmp"; return 1; }
    $ROOT mkdir -p "$imgdir"
    $ROOT install -m644 "$tmp/system.img" "$imgdir/system.img"
    $ROOT install -m644 "$tmp/vendor.img"  "$imgdir/vendor.img"
    rm -rf "$tmp"
    log "images staged"
}

ensure_erofs_mountable() {
    # The staged system.img may be EROFS (ATV builds are). Waydroid mounts it
    # with plain `mount -o ro`; that needs either the erofs kernel module or
    # the mount.erofs FUSE helper (erofsfuse).
    local img=/etc/waydroid-extra/images/system.img
    [[ -f "$img" ]] || img=/var/lib/waydroid/images/system.img
    [[ -f "$img" ]] || return 0
    if ! file -b "$img" | grep -q EROFS; then
        return 0                       # ext4 images (stock) need nothing
    fi
    if grep -qw erofs /proc/filesystems 2>/dev/null; then
        log "erofs available in kernel"
        return 0
    fi
    if modprobe erofs 2>/dev/null; then
        log "erofs kernel module loaded"
        return 0
    fi
    # Running kernel has no modules dir (partial upgrade, reboot pending) or
    # erofs =m and not loaded: fall back to the FUSE helper for mount.erofs.
    if ! command -v erofsfuse >/dev/null 2>&1; then
        log "installing erofsfuse (FUSE fallback for EROFS images)"
        $ROOT pacman -S --noconfirm --needed erofsfuse || {
            warn "could not install erofsfuse; EROFS system.img will not mount."
            warn "A reboot (into the installed kernel) also fixes this: erofs.ko autoloads."
            return 1
        }
    fi
    log "erofsfuse present — mount.erofs fallback ready"
}

init_waydroid() {
    if is_fork; then
        stage_fork_images || return 1
        ensure_erofs_mountable || return 1
        if [[ -f /var/lib/waydroid/waydroid.cfg ]]; then
            log "waydroid already initialized (images_path=$(grep -m1 '^images_path' /var/lib/waydroid/waydroid.cfg | cut -d= -f2- | tr -d ' '))"
        else
            log "running waydroid init -f (uses staged images)"
            $ROOT waydroid init -f || return 1
        fi
        # GPU gate: tests the vendor image on this GPU, then installs it.
        # Writes nvidia_* keys + vendor_ota into waydroid.cfg. Idempotent
        # ("already gated ... not gating again").
        if ! grep -q '^nvidia_driver_mode' /var/lib/waydroid/waydroid.cfg 2>/dev/null; then
            log "running waydroid-nvidia-setup"
            $ROOT waydroid-nvidia-setup || warn "waydroid-nvidia-setup failed — check its log"
        else
            log "nvidia vendor already configured"
        fi
    else
        if [[ -f /var/lib/waydroid/waydroid.cfg ]]; then
            log "waydroid already initialized"
        else
            log "running waydroid init -s GAPPS (archpc-style GAPPS image)"
            $ROOT waydroid init -s GAPPS || $ROOT waydroid init || return 1
        fi
        ensure_erofs_mountable || true   # stock images are ext4; cheap check anyway
    fi
}

# ---------------------------------------------------------------------------
# 3. cfg reconciliation (archpc parity + fork 404 repair)
# ---------------------------------------------------------------------------
reconcile_cfg() {
    local cfg=/var/lib/waydroid/waydroid.cfg
    [[ -f "$cfg" ]] || { warn "no waydroid.cfg — run init first"; return 1; }

    local cur want changes=0
    cur=$(grep '^suspend_action' "$cfg" | cut -d= -f2- | tr -d ' ')
    [[ "$cur" == "freeze" ]] || changes=1
    cur=$(grep '^background_start' "$cfg" | cut -d= -f2- | tr -d ' ')
    [[ "$cur" == "true" ]] || changes=1

    # fork only: vendor_ota pointing at a pruned GitHub release breaks every
    # `waydroid upgrade`; the same JSON ships inside the package.
    local vurl packaged
    vurl=$(grep '^vendor_ota' "$cfg" | cut -d= -f2- | tr -d ' ')
    if [[ "$vurl" == https://github.com/* ]] && ! curl -sfIL --max-time 15 -o /dev/null "$vurl" 2>/dev/null; then
        packaged=$(ls /usr/lib/waydroid-nvidia/vendor/*vendor-ota*.json 2>/dev/null | head -1)
        if [[ -n "$packaged" ]]; then
            log "vendor_ota URL 404s -> switching to packaged file://$packaged"
            changes=1
        else
            warn "vendor_ota 404s and no packaged JSON found — 'waydroid upgrade' will fail on vendor"
        fi
    fi

    if (( changes == 0 )); then
        log "cfg already reconciled (suspend_action=freeze, background_start=true)"
        return 0
    fi
    log "reconciling $cfg"
    sed -e 's/^suspend_action *=.*/suspend_action = freeze/' \
        -e 's/^background_start *=.*/background_start = true/' \
        "$cfg" > /tmp/waydroid.cfg.$$
    # append keys the fork may not write at all
    grep -q '^suspend_action'    "$cfg" || printf 'suspend_action = freeze\n' >> /tmp/waydroid.cfg.$$
    grep -q '^background_start'  "$cfg" || printf 'background_start = true\n'  >> /tmp/waydroid.cfg.$$
    if [[ -n "$packaged" ]]; then
        sed -i "s|^vendor_ota *=.*|vendor_ota = file://$packaged|" /tmp/waydroid.cfg.$$
    fi
    $ROOT tee "$cfg" < /tmp/waydroid.cfg.$$ >/dev/null
    rm -f /tmp/waydroid.cfg.$$
    log "cfg: suspend_action=freeze, background_start=true$([[ -n "${packaged:-}" ]] && echo ', vendor_ota=file://')"
}

# ---------------------------------------------------------------------------
# 4. Hyprland snippets (marker-guarded append into custom/)
# ---------------------------------------------------------------------------
inject_snippet() {
    local file="$1" marker="$2" src="$3"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    if grep -qF "$marker" "$file"; then
        log "$(basename "$file"): snippet already present"
        return 0
    fi
    printf '\n' >> "$file"
    cat "$src" >> "$file"
    log "$(basename "$file"): snippet added"
}

install_hyprland_snippets() {
    inject_snippet "$CUSTOM_DIR/execs.lua"    "waydroid-autostart"  "$SNIPPET_SRC/execs-snippet.lua"
    inject_snippet "$CUSTOM_DIR/rules.lua"    "waydroid-rules"      "$SNIPPET_SRC/rules-snippet.lua"
    inject_snippet "$CUSTOM_DIR/keybinds.lua" "waydroid-keybinds"   "$SNIPPET_SRC/keybinds-snippet.lua"
}

# ---------------------------------------------------------------------------
# 5. Session + props + desktop entries
# ---------------------------------------------------------------------------
waydroid_running() { waydroid status 2>/dev/null | grep -q "Session:.*RUNNING"; }

start_session() {
    if waydroid_running; then
        log "session already running"
        return 0
    fi
    local wl="${WAYLAND_DISPLAY:-}"
    if [[ -z "$wl" ]]; then
        wl=$(ls "/run/user/$TARGET_UID" 2>/dev/null | grep -m1 '^wayland-[0-9]*$' || true)
    fi
    if [[ -z "$wl" ]]; then
        warn "no Wayland socket found — start it from a graphical session:"
        warn "  waydroid session start"
        return 1
    fi
    log "starting session on WAYLAND_DISPLAY=$wl"
    run_as_target env WAYLAND_DISPLAY="$wl" waydroid session start &
    local i
    for i in $(seq 1 30); do
        waydroid_running && { log "session running"; return 0; }
        sleep 2
    done
    warn "session did not reach RUNNING — check: waydroid log"
    return 1
}

enable_multi_windows() {
    is_fork || return 0
    if ! waydroid_running; then
        warn "session not running: run later -> waydroid prop set persist.waydroid.multi_windows true"
        return 0
    fi
    local cur
    cur=$(run_as_target waydroid prop get persist.waydroid.multi_windows 2>/dev/null | tail -1)
    if [[ "$cur" == "true" ]]; then
        log "multi_windows already true"
    else
        run_as_target waydroid prop set persist.waydroid.multi_windows true >/dev/null 2>&1 \
            && log "multi_windows=true (one desktop window per Android app)" \
            || warn "could not set multi_windows prop"
    fi
}

gen_desktop_entries() {
    if ! waydroid_running; then
        warn "session not running — desktop entries generated on first session start"
        return 0
    fi
    local gen="$TARGET_HOME/.config/quickshell/end4-pC/scripts/waydroid-desktop-gen.sh"
    if [[ -x "$gen" ]]; then
        run_as_target "$gen" >/dev/null 2>&1 && log "desktop entries regenerated via waydroid-desktop-gen.sh" || true
    fi
    local n
    n=$(ls "$TARGET_HOME/.local/share/applications" 2>/dev/null | grep -c '^waydroid\.' || true)
    log "desktop entries in ~/.local/share/applications: $n"
}

# ---------------------------------------------------------------------------
# 6. Verify
# ---------------------------------------------------------------------------
verify() {
    local fail=0
    if waydroid_running; then
        log "verify: session RUNNING"
    else
        warn "verify: session NOT running"; fail=1
    fi
    local apps
    apps=$(timeout 40 waydroid app list 2>/dev/null | grep -c '^packageName:' || true)
    if (( apps > 0 )); then
        log "verify: $apps apps listed"
    else
        warn "verify: no apps visible (Android still booting? first boot after image swap takes minutes)"
        fail=1
    fi
    if timeout 40 waydroid app list 2>/dev/null | grep -q "com.android.vending"; then
        log "verify: Google Play Store present (GAPPS)"
    else
        warn "verify: Play Store missing — image may not be GAPPS"
    fi
    return $fail
}

# ---------------------------------------------------------------------------
main() {
    log "target: $TARGET_USER ($TARGET_HOME)"
    install_package   || { warn "package step failed"; exit 1; }
    init_waydroid     || { warn "init step failed";    exit 1; }
    reconcile_cfg     || { warn "cfg step failed";     exit 1; }
    install_hyprland_snippets
    start_session     || true       # warn only: no Wayland in headless runs
    enable_multi_windows
    gen_desktop_entries
    echo ""
    if verify; then
        log "done — Waydroid ready (like archpc). Hyprland autostart/rules/keybinds installed."
        log "note: 'waydroid session start' runs on login; edit ~/.config/hypr/custom/ to change it."
    else
        warn "finished with verification failures (see above)"
        exit 1
    fi
}

main "$@"
