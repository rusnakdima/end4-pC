#!/usr/bin/env bash
#
# sync.sh -- push this checkout into the live config of the current user.
#
# The shell never runs from this repo: it runs from
# ~/.config/quickshell/end4-pC, and Hyprland reads ~/.config/hypr. An edit
# here is invisible until it is copied across, which is why this exists --
# the same job install.sh does, but for a working tree instead of a fresh
# install, and without touching the parts of the live config that belong to
# the running system rather than to this checkout.
#
# Full option list and exit codes: ./sync.sh --help
# Common examples:
#   ./sync.sh --dry-run --check
#   ./sync.sh --keybinds-only --no-reload
#   ./sync.sh --user NAME --no-reload
#
# User edits win: files the user changed in the live tree are saved into
# <qs_dest>/.sync/user/ and restored on top of a fresh deploy. A timestamped
# copy of every such file is also kept in <qs_dest>/.sync/backups/.
#
set -uo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -c compares by checksum, so a file whose content already matches is left
# alone even when its timestamp differs -- several live files are owned by root
# from an old install, and touching those would only produce permission errors.
# --no-times keeps rsync from rewriting timestamps for the same reason.
rsync_flags=(-a -c --no-times --delete --itemize-changes)

PROG=${0##*/}
VERSION=dev

usage() {
    cat <<'EOF'
Usage: sync.sh [OPTIONS]

Push this checkout into the live config of the current (or selected) user.
Run install.sh first; the deployed trees must already exist.

Options:
  -h, --help           Show this help and exit.
  --version            Print version and exit.
  -n, --dry-run        Show what would change, write nothing, reload nothing.
  --no-reload          Skip `hyprctl reload`.
  --check              Run tests/qml-compile-check.sh first; abort on failure.
  --force              Sync even while the session is locked (dangerous: a
                       hot-reload can kill the lock screen).
  --keybinds-only      Skip the tree sync; only regenerate the keybind Lua
                       files and the command bridge, then reload.
  --user NAME          Target NAME's config instead of the detected user.
  --user=NAME          Same, single-token form.
  --sddm               Also deploy the SDDM greeter and register it as the
                       current theme (opt-in: rewrites /etc/sddm.conf.d).
  --reload-sddm        With a TTY, ask to restart SDDM after --sddm. This ends
                       active graphical sessions; opt-in.
  --                   Stop option parsing.

User edits in the live tree are saved to <qs_dest>/.sync/user/ and restored
after each deploy; timestamped copies live in <qs_dest>/.sync/backups/.

Exit status:
  0  sync complete (also used when a locked session stopped the sync)
  1  sync finished with problems, or --check found compile errors
  2  invalid command line, unknown user, or missing deployment directory
EOF
}

die() { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 2; }
need_value() { [[ $# -ge 2 ]] || die "$1 needs a value"; }

dry_run=0
do_reload=1
do_check=0
force=0
keybinds_only=0
do_sddm=0
reload_sddm=0
target_user_override=""
while (($#)); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --version) printf 'end4-pC sync %s\n' "$VERSION"; exit 0 ;;
        --dry-run|-n) dry_run=1 ;;
        --no-reload)  do_reload=0 ;;
        --check)      do_check=1 ;;
        --force)      force=1 ;;
        --keybinds-only) keybinds_only=1 ;;
        --sddm) do_sddm=1 ;;
        --reload-sddm) reload_sddm=1 ;;
        --user=*) target_user_override="${1#*=}" ;;
        --user) need_value "$@"; target_user_override="$2"; shift ;;
        --) shift; break ;;
        -*) die "unknown option: $1 (try --help)" ;;
        *) die "unexpected argument: $1 (try --help)" ;;
    esac
    shift
done

if [[ -n "$target_user_override" ]] \
   && ! getent passwd "$target_user_override" >/dev/null 2>&1; then
    die "unknown user: $target_user_override"
fi

# Resolve the target the same way install.sh does, so a sync started under
# sudo still updates the invoking user's config instead of /root.
resolve_target_home() {
    local user home
    if [[ $(id -u) -eq 0 ]]; then
        if [[ -n "${SUDO_USER:-}" ]]; then
            user="$SUDO_USER"
            home=$(eval echo "~$user")
        else
            local -a candidates=()
            mapfile -t candidates < <(find /home -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
            if ((${#candidates[@]} == 0)); then
                echo "sync.sh: cannot detect target user (root without SUDO_USER, no /home user)" >&2
                exit 2
            fi
            user="${candidates[0]}"
            home="/home/$user"
        fi
    else
        user=$(id -un)
        home="$HOME"
    fi
    TARGET_USER="$user"
    TARGET_HOME="$home"
}
resolve_target_home
if [[ -n "$target_user_override" ]]; then
    TARGET_USER="$target_user_override"
    TARGET_HOME=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
    if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
        echo "sync.sh: unknown user: $TARGET_USER" >&2
        exit 2
    fi
fi
export TARGET_USER TARGET_HOME

config_home="$TARGET_HOME/.config"
qs_dest="$config_home/quickshell/end4-pC"
hypr_dest="$config_home/hypr"
sddm_hook="$config_home/ii-sddm-theme/sddm-wallpaper-sync.sh"
default_keybind_snippet="$src/defaults/hyprland/keybinds-snippet.lua"
custom_keybinds="$hypr_dest/custom/keybinds.lua"
# The live keybind Lua files and the quickshell command bridge are generated
# from the frozen catalog plus the optional user overlay. Every path below is
# derived from TARGET_USER/TARGET_HOME, never from a bare $HOME.
keybind_catalog="$src/defaults/hyprland/keybinds.json"
keybind_generator="$src/scripts/hyprland/generate_keybinds.py"
keybind_overlay="$hypr_dest/custom/keybind-overlay.json"
main_keybinds="$hypr_dest/hyprland/keybinds.lua"
commands_json="$qs_dest/state/generated-commands.json"
# Persistent user layer + safety backups, deliberately inside the deployed
# quickshell config but under a dot-directory rsync/QML both ignore.
sync_state="$qs_dest/.sync"
user_layer="$sync_state/user"
backups_dir="$sync_state/backups"

# Never write to a locked session. quickshell hot-reloads on every config
# file change, and reloading while the session-lock surface is up destroys
# that surface: Hyprland then shows its "lockscreen app died" screen and the
# session cannot be recovered without a relogin (incident: 2026-11-12, when
# a mid-lock sync bricked the DE). Read-only --dry-run is still allowed.
session_locked() {
    local st=""
    if command -v qs >/dev/null 2>&1; then
        # qs needs the compositor env to discover the running instance;
        # sync.sh is often run from bare/ssh shells or with sudo, so derive
        # the runtime dir from the TARGET user, not from root's id. The
        # mid-lock incident happened exactly that way.
        local runtime_dir="/run/user/$(id -u "$TARGET_USER" 2>/dev/null || echo 0)"
        [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" ]] && runtime_dir="$XDG_RUNTIME_DIR"
        local signature="${HYPRLAND_INSTANCE_SIGNATURE:-}"
        if [[ -z "$signature" ]]; then
            local d
            for d in "$runtime_dir"/hypr/*; do
                [[ -d "$d" ]] && signature="$(basename "$d")"
            done
        fi
        local -a env_args=("WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}" "XDG_RUNTIME_DIR=$runtime_dir")
        [[ -n "$signature" ]] && env_args+=("HYPRLAND_INSTANCE_SIGNATURE=$signature")
        if [[ $(id -u) -eq 0 && "$TARGET_USER" != root ]] && command -v runuser >/dev/null 2>&1; then
            st=$(runuser -u "$TARGET_USER" -- env "${env_args[@]}" qs -c end4-pC ipc call lock status 2>/dev/null) || st=""
        else
            st=$(env "${env_args[@]}" qs -c end4-pC ipc call lock status 2>/dev/null) || st=""
        fi
    fi
    [[ "$st" == "locked" ]] && return 0
    pgrep -x hyprlock >/dev/null 2>&1 && return 0
    return 1
}
if [[ $force -eq 0 && $dry_run -eq 0 ]] && session_locked; then
    echo "sync.sh: the session is LOCKED -- nothing was copied, nothing reloaded."
    echo "         Touching the live config would hot-reload quickshell and kill"
    echo "         the lock screen (Hyprland 'lockscreen app died' screen)."
    echo "         Unlock the screen and run again, or pass --force to override."
    exit 0
fi

command -v rsync >/dev/null 2>&1 || { echo "sync.sh: rsync is required" >&2; exit 2; }
[[ -d "$qs_dest" ]]   || { echo "sync.sh: $qs_dest does not exist -- run install.sh first" >&2; exit 2; }
[[ -d "$hypr_dest" ]] || { echo "sync.sh: $hypr_dest does not exist -- run install.sh first" >&2; exit 2; }

# ---------------------------------------------------------------------------
# What stays on the live side
# ---------------------------------------------------------------------------

# The colour pipeline (matugen, applied through scripts/colors) rewrites these
# from the wallpaper; the copies in the repo are only as fresh as the last time
# the checkout was touched, so copying them back would silently revert the
# theme. shellOverrides carries local tuning (gaps, blur) that must not be
# overwritten. custom/, monitors.lua and profiles/ exist only in the live tree.
# hypridle.conf is generated: the shell writes it from config.json whenever an
# idle timeout changes and reconciles the file back to config.json, so the
# repo copy is a stale snapshot that would fight that reconciliation.
hypr_keep=(
    --exclude='/custom/'
    --exclude='/monitors.lua'
    --exclude='/profiles/'
    # hypridle.conf is generated by the shell from config.json.
    --exclude='/hypridle.conf'
)

# Development artifacts that have no business in the deployed tree. .git is
# excluded because install.sh copied the whole checkout once and the live tree
# therefore carries a stale 57M repository: without this every commit would
# push object files into the config and the verification pass would then
# report them as unsynced forever. .sync/ is our own user layer/backups.
qs_keep=(
    --exclude='/dots/'
    --exclude='/.omp/'
    --exclude='/file:/'
    --exclude='/.git/'
    --exclude='/verification_complete.txt'
    --exclude='/.backup-*/'
    --exclude='/.sync/'
    # state/generated-commands.json is written by generate_keybind_lua(); it is
    # runtime output, not part of the checkout, so --delete must not eat it.
    --exclude='/state/'
    --exclude='__pycache__/'
)

# diff's --exclude takes a pattern relative to the root and no leading slash,
# so the same exclusions are spelled out again for the verification pass.
qs_diff_keep=(--exclude=dots --exclude=.omp --exclude='file:'
              --exclude=.git --exclude=verification_complete.txt --exclude='.backup-*'
              --exclude=.sync --exclude=state --exclude=__pycache__)
hypr_diff_keep=(--exclude=custom --exclude=monitors.lua --exclude=profiles
                --exclude=shellOverrides --exclude=colors.lua --exclude=colors.conf
                --exclude=hypridle.conf --exclude=hyprland.lua --exclude=hyprland
                --exclude=hyprlock --exclude=hyprlock.conf
                --exclude='hyprlock.conf.*' --exclude=scripts)

# ---------------------------------------------------------------------------
# install.sh writes into the deployed copy of a few scripts, so the checkout
# never equals the live tree for those. patch_form() reproduces exactly what
# install.sh writes, which lets the sync compare like with like:
#
#   1. QUICKSHELL_CONFIG_NAME "ii" (upstream's name) -> this config's name
#   2. the SDDM wallpaper hook appended after the switch() call
#
# See install.sh:126 (name) and install.sh:606 (SDDM hook).
# ------------------------------------------------------------------------

patch_form() {
    local f="$1" hook=""
    [[ "$f" == */scripts/colors/switchwall.sh ]] && hook="$sddm_hook"
    sed 's/QUICKSHELL_CONFIG_NAME="ii"/QUICKSHELL_CONFIG_NAME="end4-pC"/g' "$f" \
    | awk -v hook="$hook" '
        { buf[NR] = $0; if ($0 ~ /^    switch "\$imgpath"/) last = NR }
        END {
            for (i = 1; i <= NR; i++) {
                print buf[i]
                if (hook != "" && i == last) {
                    print ""
                    print "# SDDM wallpaper sync (installed by end4-pC install.sh)"
                    print "sudo -n " hook " &"
                }
            }
        }'
}

# Scripts install.sh patches, and the per-file skip list: a script is skipped
# only when the live copy already equals its patched form, so a real edit in
# the checkout still gets through while an untouched file is not rewritten and
# re-patched on every single run.
qs_patched=()
qs_rsync_skip=()
while IFS= read -r f; do
    rel="${f#"$src"/}"
    qs_patched+=("$rel")
    live="$qs_dest/$rel"
    # `awk '1'` on the live side only so the two streams are compared with the
    # same end-of-file style: patch_form() goes through awk, which always ends
    # the last line with a newline, and a checkout file that does not would
    # otherwise read as different on every single run.
    if [[ -f "$live" ]] && diff -q <(patch_form "$f") <(awk '1' "$live") >/dev/null 2>&1; then
        qs_rsync_skip+=(--exclude="/$rel")
    fi
done < <(grep -rl 'QUICKSHELL_CONFIG_NAME="ii"' "$src/scripts" --include='*.sh' 2>/dev/null | sort)

# They are always excluded from the plain diff below; verify_patched() checks
# them properly instead, against their patched form.
qs_diff_skip=()
for rel in ${qs_patched[@]+"${qs_patched[@]}"}; do
    qs_diff_skip+=(--exclude="$(basename "$rel")")
done

# Live files another user owns cannot be updated: rsync would have to chmod or
# chgrp them, which fails with EPERM and takes the whole transfer down (exit 23)
# even when the content already matches. Skipping them keeps a clean sync clean;
# the verification pass still compares their content, so a root-owned file that
# genuinely needs changing still shows up as out of sync.
root_owned_note=()
collect_root_owned() {
    local dest="$1" prefix="$2" live rel
    local -n out="$3"
    # Root can always chmod/chown, so there is no EPERM risk to avoid. The old
    # `! -user $(id -u)` check flagged every target-user file when sync.sh ran
    # as root, silently excluded the whole tree, and printed a misleading
    # "owned by root" warning with a chown suggestion.
    [[ $(id -u) -eq 0 ]] && return 0
    while IFS= read -r live; do
        [[ -n "$live" ]] || continue
        rel="${live#"$prefix"/}"
        out+=(--exclude="/$rel")
        root_owned_note+=("$prefix/$rel")
    done < <(find "$dest" -type f -not -user "$(id -u)" 2>/dev/null)
}
qs_root_owned=()
hypr_root_owned=()
collect_root_owned "$qs_dest"   "$qs_dest"   qs_root_owned
collect_root_owned "$hypr_dest" "$hypr_dest" hypr_root_owned

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

fail=0

# rsync one tree, then print only what actually changed. itemize-changes emits
# ">f... path" for a transfer, "*deleting path" for a removal, "cd... path" for
# a directory; everything else is a no-op and is dropped from the report.
# Pass --no-delete as the first argument for trees that own live-only files:
# the hypr tree must never have files erased by a --delete pass.
sync_tree() {
    local label="$1"; shift
    local no_delete=0
    if [[ "${1:-}" == "--no-delete" ]]; then no_delete=1; shift; fi
    local log err rc changes
    log=$(mktemp) err=$(mktemp)

    # rsync has no `--no-delete`; build the flag list without --delete for
    # trees whose live side owns files the checkout does not carry.
    local -a flags=()
    local flag
    for flag in "${rsync_flags[@]}"; do
        if [[ $no_delete -eq 1 && "$flag" == "--delete" ]]; then continue; fi
        flags+=("$flag")
    done
    [[ $dry_run -eq 1 ]] && flags+=(-n)

    rsync "${flags[@]}" "$@" >"$log" 2>"$err"
    rc=$?

    echo "== $label =="
    # With --itemize-changes rsync prints nothing for a file it left alone, so
    # every line here is a real change: a transfer, a deletion, or a pure
    # attribute update (">f" / "*deleting" / a leading "." for perms/owner).
    changes=$(sed -E 's/^\*deleting /deleted /; s/^>f[^ ]* /copied  /; s/^cd[^ ]* /mkdir  /; s/^cL[^ ]* /link   /; s/^\.[a-zA-Z][^ ]* /updated /' "$log")
    if [[ -n "$changes" ]]; then
        printf '%s\n' "$changes"
    else
        echo "       (no changes)"
    fi

    if [[ $rc -ne 0 ]]; then
        echo "  !! rsync exited $rc:" >&2
        sed 's/^/       /' "$err" | head -25 >&2
        fail=1
    fi

    rm -f "$log" "$err"
}

verify_tree() {
    local label="$1"; shift
    local leftovers
    leftovers=$(diff -rq "$@" 2>&1 || true)
    if [[ -n "$leftovers" ]]; then
        echo "!! $label is NOT in sync:" >&2
        printf '%s\n' "$leftovers" | sed 's/^/       /' >&2
        fail=1
    else
        echo "OK  $label matches the checkout"
    fi
}

# The install-patched scripts cannot be compared with a plain diff, so each one
# is checked against what it is supposed to look like after install.sh ran.
verify_patched() {
    local rel live bad=0
    for rel in ${qs_patched[@]+"${qs_patched[@]}"}; do
        live="$qs_dest/$rel"
        if [[ ! -f "$live" ]] || ! diff -q <(patch_form "$src/$rel") <(awk '1' "$live") >/dev/null 2>&1; then
            echo "!! $rel is NOT in sync (expected its install-patched form):" >&2
            diff -u <(patch_form "$src/$rel") <(awk '1' "$live") 2>&1 | sed 's/^/       /' | head -30 >&2
            bad=1
        fi
    done
    if [[ $bad -eq 0 ]]; then
        echo "OK  ${#qs_patched[@]} install-patched scripts match their patched form"
    else
        fail=1
    fi
}

# Re-apply what install.sh writes, after a copy has replaced it.
deploy_patches() {
    local f
    while IFS= read -r -d '' f; do
        if grep -q 'QUICKSHELL_CONFIG_NAME="ii"' "$f" 2>/dev/null; then
            sed -i 's/QUICKSHELL_CONFIG_NAME="ii"/QUICKSHELL_CONFIG_NAME="end4-pC"/g' "$f"
            echo "patched QUICKSHELL_CONFIG_NAME in ${f#"$qs_dest"/}"
        fi
    done < <(find "$qs_dest/scripts" -type f -name '*.sh' -print0 2>/dev/null)

    # install.sh:606 -- refresh the SDDM greeter wallpaper after switch().
    local switchwall="$qs_dest/scripts/colors/switchwall.sh" line tmp mode
    if [[ -f "$switchwall" ]] && ! grep -q 'sddm-wallpaper-sync.sh' "$switchwall"; then
        line=$(grep -nF '    switch "$imgpath' "$switchwall" | tail -1 | cut -d: -f1)
        if [[ -n "$line" ]]; then
            tmp=$(mktemp); mode=$(stat -c '%a' "$switchwall")
            head -n "$line" "$switchwall" > "$tmp"
            printf '\n# SDDM wallpaper sync (installed by end4-pC install.sh)\nsudo -n %s &\n' "$sddm_hook" >> "$tmp"
            tail -n +"$((line + 1))" "$switchwall" >> "$tmp"
            mv "$tmp" "$switchwall"; chmod "$mode" "$switchwall"
            echo "reinstalled the SDDM wallpaper hook in scripts/colors/switchwall.sh"
        else
            echo "!! switch() call not found; SDDM wallpaper hook was not installed" >&2
            fail=1
        fi
    fi

    # install.sh:242 -- qsConfig drives every `qs -c $qsConfig` call in the
    # Hyprland config, so it must never end up as upstream's "ii".
    for f in "$hypr_dest/hyprland/env.lua" "$hypr_dest/hyprland/variables.lua"; do
        if [[ -f "$f" ]] && grep -q 'hl\.env("qsConfig", "ii")' "$f"; then
            sed -i 's/hl\.env("qsConfig", "ii")/hl.env("qsConfig", "end4-pC")/' "$f"
            echo "patched qsConfig in ${f#"$hypr_dest"/}"
        fi
    done
}

# ---------------------------------------------------------------------------
# User layer: keep the user's own edits, never lose them to a fresh deploy.
#
# A file is only a "user edit" if it differs from the project AND it changed
# since the last sync (per .sync/manifest). A plain project update -- live is
# exactly what we deployed last time but the checkout now differs -- is NOT a
# user edit, so it is allowed through. The layer is persistent; the manifest
# is rewritten after every successful deploy so the next run can tell the two
# apart. A timestamped backup is kept for every file saved.
# ---------------------------------------------------------------------------

manifest="$sync_state/manifest"

# Raw bytes, not `awk '1'` -- awk would mangle binary assets (fonts, sounds,
# images) into fake differences. Only the install-patched scripts are compared
# through awk so their EOF-newline style matches patch_form()'s output.
is_patched() {
    local rel="$1" p
    for p in ${qs_patched[@]+"${qs_patched[@]}"}; do
        [[ "$p" == "$rel" ]] && return 0
    done
    return 1
}

raw_sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
stream_sha() { sha256sum 2>/dev/null | awk '{print $1}'; }

live_sha() {
    local ns="$1" rel="$2" live="$3"
    if [[ "$ns" == "quickshell" ]] && is_patched "$rel"; then
        awk '1' "$live" | stream_sha
    else
        raw_sha "$live"
    fi
}

project_sha_of() {
    local ns="$1" rel="$2" srcfile="$3"
    [[ -f "$srcfile" ]] || return 1
    if [[ "$ns" == "quickshell" ]] && is_patched "$rel"; then
        patch_form "$srcfile" | awk '1' | stream_sha
    else
        raw_sha "$srcfile"
    fi
}

declare -A MAN_LIVE=() MAN_PROJ=()
load_manifest() {
    MAN_LIVE=(); MAN_PROJ=()
    [[ -f "$manifest" ]] || return 0
    local k lv pv
    while IFS=$'\t' read -r k lv pv; do
        [[ -n "$k" ]] || continue
        MAN_LIVE["$k"]="$lv"
        MAN_PROJ["$k"]="$pv"
    done < "$manifest"
}

write_manifest() {
    [[ $dry_run -eq 1 ]] && return 0
    local tmp rel live srcfile lv pv
    tmp=$(mktemp)
    while IFS= read -r -d '' live; do
        rel="${live#"$qs_dest"/}"
        [[ "$rel" == .sync/* ]] && continue
        # A stale .git copy left by an old install is not user config.
        [[ "$rel" == .git/* ]] && continue
        [[ -f "$live" ]] || continue
        srcfile="$src/$rel"
        pv=$(project_sha_of "quickshell" "$rel" "$srcfile" 2>/dev/null || true)
        lv=$(live_sha "quickshell" "$rel" "$live")
        printf 'quickshell/%s\t%s\t%s\n' "$rel" "$lv" "$pv" >> "$tmp"
    done < <(find "$qs_dest" -type f -not -path "$qs_dest/.sync/*" -print0 2>/dev/null)
    if [[ -d "$src/dots/.config/hypr" ]]; then
        while IFS= read -r -d '' live; do
            rel="${live#"$hypr_dest"/}"
            [[ -f "$live" ]] || continue
            srcfile="$src/dots/.config/hypr/$rel"
            pv=$(project_sha_of "hypr" "$rel" "$srcfile" 2>/dev/null || true)
            lv=$(live_sha "hypr" "$rel" "$live")
            printf 'hypr/%s\t%s\t%s\n' "$rel" "$lv" "$pv" >> "$tmp"
        done < <(find "$hypr_dest" -type f -print0 2>/dev/null)
    fi
    mv -f "$tmp" "$manifest"
}

# Return 0 when the live file is a genuine user edit.
is_user_edit() {
    local ns="$1" rel="$2" live="$3" project_sha="$4"
    # sync.sh is the sync tool itself, never user config.
    if [[ "$ns" == "quickshell" && "$rel" == "sync.sh" ]]; then return 1; fi
    local key="$ns/$rel" lv prev_live
    [[ -n "$project_sha" ]] || return 1
    lv=$(live_sha "$ns" "$rel" "$live")
    [[ "$lv" == "$project_sha" ]] && return 1
    prev_live="${MAN_LIVE[$key]:-}"
    if [[ -n "$prev_live" ]]; then
        # Live still equals what we deployed last time: the user did not
        # touch it, so let a newer project version replace it.
        [[ "$lv" == "$prev_live" ]] && return 1
        return 0
    fi
    # No baseline yet (first run): be conservative and keep the live copy.
    return 0
}

# Extend the persistent user layer with new edits and keep a timestamped copy.
snapshot_user_edits() {
    [[ $dry_run -eq 1 ]] && return 0
    load_manifest
    mkdir -p "$user_layer" "$backups_dir"
    local stamp rel live srcfile project_sha saved_count=0 lv
    local ns f key
    stamp=$(date +%Y%m%d-%H%M%S)
    : > "$sync_state/last-user-edits.txt"

    # Drop layer entries that are no longer edits (user reverted, or the
    # project caught up), otherwise a stale layer would overwrite a fix.
    for ns in quickshell hypr; do
        [[ -d "$user_layer/$ns" ]] || continue
        while IFS= read -r -d '' f; do
            rel="${f#"$user_layer/$ns"/}"
            [[ "$rel" == .git/* ]] && { rm -f "$f"; continue; }
            if [[ "$ns" == "quickshell" ]]; then live="$qs_dest/$rel"; else live="$hypr_dest/$rel"; fi
            if [[ ! -f "$live" ]]; then rm -f "$f"; continue; fi
            if [[ "$ns" == "quickshell" ]]; then project_sha=$(project_sha_of "quickshell" "$rel" "$src/$rel" 2>/dev/null || true)
            else project_sha=$(project_sha_of "hypr" "$rel" "$src/dots/.config/hypr/$rel" 2>/dev/null || true); fi
            # Keep a known edit as long as live still differs from the project.
            # The manifest cannot be used here: after a restore it records the
            # user's own bytes as the baseline, so is_user_edit would report
            # "no change" and we would drop the edit on the second run.
            lv=$(live_sha "$ns" "$rel" "$live")
            if [[ -n "$project_sha" && "$lv" == "$project_sha" ]]; then rm -f "$f"; fi
        done < <(find "$user_layer/$ns" -type f -print0 2>/dev/null)
    done

    # New edits in the quickshell tree.
    while IFS= read -r -d '' live; do
        rel="${live#"$qs_dest"/}"
        [[ "$rel" == .sync/* ]] && continue
        [[ "$rel" == .git/* ]] && continue
        [[ -r "$live" ]] || continue
        srcfile="$src/$rel"
        [[ -f "$srcfile" ]] || continue
        project_sha=$(project_sha_of "quickshell" "$rel" "$srcfile")
        is_user_edit "quickshell" "$rel" "$live" "$project_sha" || continue
        key="quickshell/$rel"
        [[ -f "$user_layer/$key" ]] && continue   # already a known edit
        mkdir -p "$user_layer/quickshell/$(dirname "$rel")" \
                 "$backups_dir/$stamp/quickshell/$(dirname "$rel")"
        cp -p "$live" "$user_layer/quickshell/$rel"
        cp -p "$live" "$backups_dir/$stamp/quickshell/$rel"
        echo "$key" >> "$sync_state/last-user-edits.txt"
        saved_count=$((saved_count + 1))
    done < <(find "$qs_dest" -type f -not -path "$qs_dest/.sync/*" -print0 2>/dev/null)

    # New edits in the hypr tree (only where the project ships a baseline).
    if [[ -d "$src/dots/.config/hypr" ]]; then
        while IFS= read -r -d '' live; do
            rel="${live#"$hypr_dest"/}"
            [[ -r "$live" ]] || continue
            srcfile="$src/dots/.config/hypr/$rel"
            [[ -f "$srcfile" ]] || continue
            project_sha=$(project_sha_of "hypr" "$rel" "$srcfile")
            is_user_edit "hypr" "$rel" "$live" "$project_sha" || continue
            key="hypr/$rel"
            [[ -f "$user_layer/$key" ]] && continue   # already a known edit
            mkdir -p "$user_layer/hypr/$(dirname "$rel")" \
                     "$backups_dir/$stamp/hypr/$(dirname "$rel")"
            cp -p "$live" "$user_layer/hypr/$rel"
            cp -p "$live" "$backups_dir/$stamp/hypr/$rel"
            echo "$key" >> "$sync_state/last-user-edits.txt"
            saved_count=$((saved_count + 1))
        done < <(find "$hypr_dest" -type f -print0 2>/dev/null)
    fi

    if [[ $saved_count -gt 0 ]]; then
        echo "== user edits =="
        echo "       saved $saved_count file(s) to .sync/user/ and .sync/backups/$stamp/"
    fi
}

# Put the saved user edits back on top of the freshly deployed files.
restore_user_edits() {
    [[ $dry_run -eq 1 ]] && return 0
    local ns rel live f
    for ns in quickshell hypr; do
        [[ -d "$user_layer/$ns" ]] || continue
        while IFS= read -r -d '' f; do
            rel="${f#"$user_layer/$ns"/}"
            if [[ "$ns" == "quickshell" ]]; then live="$qs_dest/$rel"; else live="$hypr_dest/$rel"; fi
            mkdir -p "$(dirname "$live")"
            cp -p "$f" "$live"
            echo "  restored user edit: $ns/$rel"
        done < <(find "$user_layer/$ns" -type f -print0 2>/dev/null)
    done
}

# ---------------------------------------------------------------------------
# Keybind blocks. The theme's default binds are injected into the user-owned
# custom/keybinds.lua behind markers. Every -- >>> ... -- <<< block in the
# snippet is managed: refreshed in place when the project changes, appended
# when missing. Everything outside the markers (the user's own binds, the
# waydroid block, the panel-managed block) is never touched. This replaces the
# old append-only, four-hardcoded-marker logic, which could never update an
# existing install and ignored the image-preview window-rule block entirely.
# ---------------------------------------------------------------------------

declare -a kb_starts=() kb_ends=() kb_blocks=()
read_keybind_blocks() {
    kb_starts=(); kb_ends=(); kb_blocks=()
    [[ -f "$default_keybind_snippet" ]] || return 0
    local line start="" block=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$start" && "$line" == "-- >>> "* ]]; then
            start="$line"
            block="$line"
        elif [[ -n "$start" ]]; then
            block+=$'\n'"$line"
            if [[ "$line" == "-- <<<"* ]]; then
                kb_starts+=("$start")
                kb_ends+=("$line")
                kb_blocks+=("$block")
                start=""
            fi
        fi
    done < "$default_keybind_snippet"
}

# Replace one marker block in a file. Return 0 = replaced, 2 = already
# identical, 1 = error (start marker without a matching end marker).
replace_managed_block() {
    local file="$1" start="$2" end="$3" replacement="$4"
    local tmp
    tmp=$(mktemp)
    if MSTART="$start" MEND="$end" REPL="$replacement" awk '
        BEGIN {
            inside = 0; done = 0
            MSTART = ENVIRON["MSTART"]; MEND = ENVIRON["MEND"]; REPL = ENVIRON["REPL"]
        }
        {
            if (!done && index($0, MSTART) == 1) {
                inside = 1
                printf "%s\n", REPL
                next
            }
            if (inside) {
                if (index($0, MEND) == 1) { inside = 0; done = 1 }
                next
            }
            print
        }
        END { exit inside ? 2 : 0 }
    ' "$file" > "$tmp"; then
        if cmp -s "$file" "$tmp"; then
            rm -f "$tmp"
            return 2
        fi
        cat "$tmp" > "$file"
        rm -f "$tmp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# Pre-generator marker injector, kept only as documentation of the old format.
# The generated custom/keybinds.lua already reproduces every managed block, so
# this is a no-op: calling it on the generated path would duplicate them.
install_keybind_defaults() {
    return 0
    [[ -f "$default_keybind_snippet" ]] || return 0
    mkdir -p "$(dirname "$custom_keybinds")"
    touch "$custom_keybinds"
    read_keybind_blocks

    local i rc added=0 refreshed=0 unchanged=0 failed=0
    local start end block label
    echo "== default keybinds =="
    for i in "${!kb_starts[@]}"; do
        start="${kb_starts[$i]}"; end="${kb_ends[$i]}"; block="${kb_blocks[$i]}"
        label="${start#-- >>> }"
        if grep -qF -- "$start" "$custom_keybinds"; then
            replace_managed_block "$custom_keybinds" "$start" "$end" "$block"
            rc=$?
            case $rc in
                0) printf '  refreshed: %s\n' "$label"; refreshed=$((refreshed + 1)) ;;
                2) unchanged=$((unchanged + 1)) ;;
                *) printf '  !! could not refresh: %s\n' "$label" >&2; failed=$((failed + 1)) ;;
            esac
        else
            printf '\n%s\n' "$block" >> "$custom_keybinds"
            printf '  added: %s\n' "$label"
            added=$((added + 1))
        fi
    done
    printf '  keybind blocks: %d added, %d refreshed, %d unchanged\n' \
        "$added" "$refreshed" "$unchanged"
    [[ $failed -eq 0 ]] || fail=1
}

# Dry-run counterpart: report what the real run would add/refresh.
keybind_report() {
    [[ -f "$default_keybind_snippet" ]] || return 0
    read_keybind_blocks
    local i start label added=0 present=0
    echo "== default keybinds =="
    for i in "${!kb_starts[@]}"; do
        start="${kb_starts[$i]}"; label="${start#-- >>> }"
        if grep -qF -- "$start" "$custom_keybinds" 2>/dev/null; then
            present=$((present + 1))
        else
            printf '  would add: %s\n' "$label"
            added=$((added + 1))
        fi
    done
    printf '  keybind blocks: %d would be added, %d present (all refreshed on a real run)\n' \
        "$added" "$present"
}

# ---------------------------------------------------------------------------
# Generated keybind Lua.
#
# The frozen catalog plus the optional user overlay are now the single source
# of truth for both keybinds.lua files and for the quickshell command bridge.
# The generator rewrites those files wholesale, so install_keybind_defaults()
# (the old marker injector) must NOT run on this path: the generated
# custom/keybinds.lua already reproduces every managed block and appending the
# old blocks again would duplicate them.
# ---------------------------------------------------------------------------

keybind_gen_report() {
    echo "== generated keybind lua (dry run) =="
    echo "       catalog: $keybind_catalog"
    if [[ -f "$keybind_overlay" ]]; then
        echo "       overlay: $keybind_overlay (would be applied)"
    else
        echo "       overlay: none ($keybind_overlay not present)"
    fi
    echo "       would write: $main_keybinds"
    echo "       would write: $custom_keybinds"
    echo "       would write: $commands_json"
}

generate_keybind_lua() {
    if [[ $dry_run -eq 1 ]]; then
        keybind_gen_report
        return 0
    fi

    if [[ ! -f "$keybind_catalog" || ! -f "$keybind_generator" ]]; then
        echo "sync.sh: keybind catalog or generator is missing; nothing generated" >&2
        fail=1
        return 1
    fi

    local -a gen_cmd=(python3 "$keybind_generator"
                      --catalog "$keybind_catalog"
                      --main-out "$main_keybinds"
                      --custom-out "$custom_keybinds"
                      --commands-out "$commands_json")
    # The overlay is strictly opt-in: only feed it to the generator when the
    # user actually has one. The generator never writes back to it.
    local overlay_note="none (defaults only)"
    if [[ -f "$keybind_overlay" ]]; then
        gen_cmd+=(--overlay "$keybind_overlay")
        overlay_note="$keybind_overlay (applied, never modified)"
    fi

    mkdir -p "$(dirname "$main_keybinds")" "$(dirname "$custom_keybinds")" \
             "$(dirname "$commands_json")"

    echo "== generated keybind lua =="
    echo "       catalog: $keybind_catalog"
    echo "       overlay: $overlay_note"

    local out rc
    out=$("${gen_cmd[@]}" 2>&1); rc=$?
    [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/       /'
    if [[ $rc -ne 0 ]]; then
        echo "  !! keybind generator exited $rc" >&2
        fail=1
        return 1
    fi

    # A sync started under sudo must leave the generated files (and the dir
    # holding the bridge JSON) owned by the target user -- same pattern as
    # install.sh's `chown "$TARGET_USER:" "$dest" 2>/dev/null || true`.
    if [[ $(id -u) -eq 0 ]]; then
        chown "$TARGET_USER:" "$(dirname "$commands_json")" "$commands_json" \
              "$main_keybinds" "$custom_keybinds" 2>/dev/null || true
    fi
    echo "OK  generated: ${main_keybinds#"$TARGET_HOME"/}, ${custom_keybinds#"$TARGET_HOME"/}, ${commands_json#"$TARGET_HOME"/}"
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

if [[ $do_check -eq 1 && $dry_run -eq 0 ]]; then
    echo "== qml-compile-check =="
    if ! "$src/tests/qml-compile-check.sh"; then
        echo "sync.sh: the QML does not compile, nothing was copied" >&2
        exit 1
    fi
fi

echo "target: $TARGET_USER ($TARGET_HOME)"
[[ $dry_run -eq 1 ]] && echo "-- dry run: nothing will be written --"

if [[ $keybinds_only -eq 0 ]]; then
    # Snapshot user edits BEFORE rsync --delete can overwrite them.
    snapshot_user_edits

    sync_tree "quickshell ($qs_dest)" \
        "${qs_keep[@]}" \
        ${qs_rsync_skip[@]+"${qs_rsync_skip[@]}"} \
        ${qs_root_owned[@]+"${qs_root_owned[@]}"} \
        "$src/" "$qs_dest/"

    # Keep-awake inhibitor unit: systemd owns its lifetime, so a shell reload
    # or crash can never leave an idle-inhibitor lock behind.
    if [[ $dry_run -eq 0 ]]; then
        install -Dm644 "$src/systemd/user/end4pc-keep-awake.service" \
            "$config_home/systemd/user/end4pc-keep-awake.service"
    fi

    # Lock screen watchdog: the themed lock is the only lock client, and this
    # guard restarts the shell after a crash until the theme lock is secure.
    # Enable through default.target.wants so it also works when sync runs for
    # another user (no `systemctl --user` session required to enable it).
    if [[ $dry_run -eq 0 ]]; then
        guard_bin="$TARGET_HOME/.local/bin/end4pc-lock-guard"
        guard_unit="$config_home/systemd/user/end4pc-lock-guard.service"
        guard_want="$config_home/systemd/user/default.target.wants/end4pc-lock-guard.service"
        install -Dm755 "$src/scripts/lock/end4pc-lock-guard" "$guard_bin"
        install -Dm644 "$src/systemd/user/end4pc-lock-guard.service" "$guard_unit"
        mkdir -p "$(dirname "$guard_want")"
        ln -sfn ../end4pc-lock-guard.service "$guard_want"
        if [[ $(id -u) -eq 0 ]]; then
            chown "$TARGET_USER:" "$guard_bin" "$guard_unit" "$guard_want" 2>/dev/null || true
        fi
    fi

    if [[ $dry_run -eq 0 ]]; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi

    # dots/ is vendored and git-ignored, so a checkout that never carried it
    # (or lost it) must not turn the whole sync into a failure. The hypr tree
    # is synced WITHOUT --delete: live-only files (hyprland.lua, colors.lua,
    # monitors.lua, hypridle.conf) are never erased.
    if [[ -d "$src/dots/.config/hypr" ]]; then
        sync_tree "hyprland ($hypr_dest)" --no-delete \
            "${hypr_keep[@]}" \
            ${hypr_root_owned[@]+"${hypr_root_owned[@]}"} \
            "$src/dots/.config/hypr/" "$hypr_dest/"
    else
        echo "== hyprland ($hypr_dest) =="
        echo "       skipped: dots/.config/hypr is not in this checkout"
    fi

    # User edits win: put them back on top of the fresh deploy.
    restore_user_edits

    # After both copies, so nothing a copy just brought in is left unpatched.
    if [[ $dry_run -eq 0 ]]; then
        deploy_patches
    fi

    # Files restored from the user layer are expected to differ from the
    # checkout, so exclude them from the drift check (they were reported above).
    verify_user_qs_skip=()
    verify_user_hypr_skip=()
    for ns in quickshell hypr; do
        [[ -d "$user_layer/$ns" ]] || continue
        while IFS= read -r -d '' f; do
            rel="${f#"$user_layer/$ns"/}"
            if [[ "$ns" == "quickshell" ]]; then
                verify_user_qs_skip+=(--exclude="$(basename "$rel")")
            else
                verify_user_hypr_skip+=(--exclude="$(basename "$rel")")
            fi
        done < <(find "$user_layer/$ns" -type f -print0 2>/dev/null)
    done

    verify_tree "quickshell" "$src" "$qs_dest" \
        "${qs_diff_keep[@]}" ${qs_diff_skip[@]+"${qs_diff_skip[@]}"} \
        ${verify_user_qs_skip[@]+"${verify_user_qs_skip[@]}"}
    verify_patched
    if [[ -d "$src/dots/.config/hypr" ]]; then
        verify_tree "hyprland" "$src/dots/.config/hypr" "$hypr_dest" \
            "${hypr_diff_keep[@]}" \
            ${verify_user_hypr_skip[@]+"${verify_user_hypr_skip[@]}"}
    fi
else
    echo "== tree sync skipped (--keybinds-only) =="
fi

# Regenerate the live keybind Lua from the frozen catalog + user overlay. This
# runs after deploy/restore (so a restored user edit cannot shadow it) and in
# --keybinds-only mode too. install_keybind_defaults() is deliberately NOT
# called: the generated custom/keybinds.lua already carries every managed
# block, and the old injected-block path would duplicate them.
generate_keybind_lua

# Record the deployed state so the next run can tell a user edit from a
# project update. Written after generation so the manifest's baseline is the
# generated bytes. Skipped in --keybinds-only mode, which never deploys trees.
if [[ $dry_run -eq 0 && $keybinds_only -eq 0 ]]; then
    write_manifest
fi

# Colour output is owned by the runtime, not by this sync -- say so rather than
# leaving the reader to wonder why a few files still differ.
echo "kept on the live side (by design):"
echo "  hyprland/colors.lua, hyprlock/colors.conf  -- regenerated from the wallpaper"
echo "  hyprland/shellOverrides/                   -- local gaps/blur tuning"
echo "  hypridle.conf                              -- generated from config.json by the shell"
echo "  custom/, monitors.lua, profiles/           -- live-only, never in the repo"
echo "  ${#qs_rsync_skip[@]} scripts unchanged since install.sh patched them"

if [[ ${#root_owned_note[@]} -gt 0 ]]; then
    echo "not synced -- owned by another user (content is compared anyway):"
    printf '  %s\n' "${root_owned_note[@]}"
    echo "  To let this script update them in future:"
    echo "    sudo chown -R $TARGET_USER:$TARGET_USER \"$hypr_dest\" \"$qs_dest\""
fi

if [[ -f "$qs_dest/scripts/colors/switchwall.sh" ]] \
   && grep -q 'sddm-wallpaper-sync.sh' "$qs_dest/scripts/colors/switchwall.sh" \
   && [[ ! -f "$sddm_hook" ]]; then
    echo "note: scripts/colors/switchwall.sh calls $sddm_hook"
    echo "      but that file does not exist, so the greeter wallpaper sync is dead."
    echo "      Re-run ./install.sh (or drop the hook from switchwall.sh)."
fi

if [[ $dry_run -eq 1 ]]; then
    echo "-- dry run finished --"
    exit $fail
fi

# Greeter deployment is opt-in: syncing the desktop theme must not silently
# rewrite a system config. The helper merges the drop-in and never clobbers
# unrelated SDDM keys.
if [[ $do_sddm -eq 1 ]]; then
    echo "== SDDM greeter =="
    local_args=()
    [[ $reload_sddm -eq 1 ]] && local_args+=(--reload-sddm)
    env END4PC_SOURCE_DIR="$src" \
        END4PC_TARGET_HOME="$TARGET_HOME" \
        END4PC_TARGET_USER="$TARGET_USER" \
        "$src/scripts/sddm/deploy-theme.sh" "${local_args[@]}" \
        || { echo "  !! SDDM deployment failed" >&2; fail=1; }
fi

if [[ $do_reload -eq 1 ]]; then
    if command -v hyprctl >/dev/null 2>&1; then
        echo "== hyprctl reload =="
        hyprctl reload >/dev/null 2>&1 || { echo "  !! reload failed" >&2; fail=1; }
        sleep 0.5
        ce=$(hyprctl configerrors 2>&1)
        if [[ -n "${ce// /}" ]]; then
            echo "!! Hyprland reports config errors:" >&2
            printf '%s\n' "$ce" | sed 's/^/       /' >&2
            fail=1
        else
            echo "OK  hyprctl configerrors is empty"
        fi
    else
        echo "!! hyprctl not found; run \`hyprctl reload\` yourself" >&2
        fail=1
    fi

    # Hyprland reloading is not enough: the QML files are read by the running
    # shell. Reload it through IPC, never by killing the process.
    env END4PC_TARGET_HOME="$TARGET_HOME" \
        END4PC_TARGET_USER="$TARGET_USER" \
        "$src/scripts/hyprland/reload-shell.sh" \
        || { echo "  !! shell reload failed" >&2; fail=1; }
fi

if command -v qs >/dev/null 2>&1 && qs -c end4-pC ipc show >/dev/null 2>&1; then
    echo "OK  quickshell is running and reachable as -c end4-pC"
elif [[ $fail -eq 0 ]]; then
    echo "note: quickshell is not running (QML is picked up on next start)"
fi

if [[ $fail -eq 0 ]]; then
    echo "sync complete"
else
    echo "sync finished with problems -- see above" >&2
fi
exit $fail
