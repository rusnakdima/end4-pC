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
# Usage:
#   ./sync.sh              sync both trees, reload Hyprland, verify
#   ./sync.sh --dry-run    show what would change, change nothing
#   ./sync.sh --no-reload  skip `hyprctl reload`
#   ./sync.sh --check      run tests/qml-compile-check.sh first, abort on failure
#
set -uo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
qs_dest="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/end4-pC"
hypr_dest="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
sddm_hook="$HOME/.config/ii-sddm-theme/sddm-wallpaper-sync.sh"

# -c compares by checksum, so a file whose content already matches is left
# alone even when its timestamp differs -- several live files are owned by root
# from an old install, and touching those would only produce permission errors.
# --no-times keeps rsync from rewriting timestamps for the same reason.
rsync_flags=(-a -c --no-times --delete --itemize-changes)

dry_run=0
do_reload=1
do_check=0
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) dry_run=1 ;;
        --no-reload)  do_reload=0 ;;
        --check)      do_check=1 ;;
        -h|--help)    sed -n '2,16p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "sync.sh: unknown option: $arg" >&2; exit 2 ;;
    esac
done

command -v rsync >/dev/null 2>&1 || { echo "sync.sh: rsync is required" >&2; exit 2; }
[[ -d "$qs_dest" ]]   || { echo "sync.sh: $qs_dest does not exist -- run install.sh first" >&2; exit 2; }
[[ -d "$hypr_dest" ]] || { echo "sync.sh: $hypr_dest does not exist -- run install.sh first" >&2; exit 2; }

# ---------------------------------------------------------------------------
# What stays on the live side
# ----------------------------------------------------------------

# The colour pipeline (matugen, applied through scripts/colors) rewrites these
# from the wallpaper; the copies in the repo are only as fresh as the last time
# the checkout was touched, so copying them back would silently revert the
# theme. shellOverrides carries local tuning (gaps, blur) that must not be
# overwritten. custom/, monitors.lua and profiles/ exist only in the live tree.
hypr_keep=(
    --exclude='/custom/'
    --exclude='/monitors.lua'
    --exclude='/profiles/'
    --exclude='/hyprland/shellOverrides/'
    --exclude='/hyprland/colors.lua'
    --exclude='/hyprlock/colors.conf'
)

# Development artifacts that have no business in the deployed tree. .git is
# excluded because install.sh copied the whole checkout once and the live tree
# therefore carries a stale 57M repository: without this every commit would
# push object files into the config and the verification pass would then
# report them as unsynced forever.
qs_keep=(
    --exclude='/dots/'
    --exclude='/.omp/'
    --exclude='/file:/'
    --exclude='/.git/'
    --exclude='/verification_complete.txt'
    --exclude='__pycache__/'
)

# diff's --exclude takes a pattern relative to the root and no leading slash,
# so the same exclusions are spelled out again for the verification pass.
qs_diff_keep=(--exclude=dots --exclude=.omp --exclude='file:'
              --exclude=.git --exclude=verification_complete.txt --exclude=__pycache__)
hypr_diff_keep=(--exclude=custom --exclude=monitors.lua --exclude=profiles
                --exclude=shellOverrides --exclude=colors.lua --exclude=colors.conf)

# ---------------------------------------------------------------------------
# install.sh writes into the deployed copy of a few scripts, so the checkout
# never equals the live tree for those. patch_form() reproduces exactly what
# install.sh writes, which lets the sync compare like with like:
#
#   1. QUICKSHELL_CONFIG_NAME "ii" (upstream's name) -> this config's name
#   2. the SDDM wallpaper hook appended after the switch() call
#
# See install.sh:126 (name) and install.sh:502 (SDDM hook).
# ----------------------------------------------------------------

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
# only when the live copy already equals its patched form, so a real edit in the
# checkout still gets through while an untouched file is not rewritten and
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
# ----------------------------------------------------------------

fail=0

# rsync one tree, then print only what actually changed. itemize-changes emits
# ">f... path" for a transfer, "*deleting path" for a removal, "cd... path" for
# a directory; everything else is a no-op and is dropped from the report.
sync_tree() {
    local label="$1"; shift
    local log err rc changes
    log=$(mktemp) err=$(mktemp)

    local -a flags=("${rsync_flags[@]}")
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
        # Show the real reason, not just a pattern this script happens to look
        # for -- the common case here is "chgrp ... Operation not permitted".
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

    # install.sh:502 -- refresh the SDDM greeter wallpaper after switch().
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

    # install.sh:202 -- qsConfig drives every `qs -c $qsConfig` call in the
    # Hyprland config, so it must never end up as upstream's "ii".
    for f in "$hypr_dest/hyprland/env.lua" "$hypr_dest/hyprland/variables.lua"; do
        if [[ -f "$f" ]] && grep -q 'hl\.env("qsConfig", "ii")' "$f"; then
            sed -i 's/hl\.env("qsConfig", "ii")/hl.env("qsConfig", "end4-pC")/' "$f"
            echo "patched qsConfig in ${f#"$hypr_dest"/}"
        fi
    done
}

# ---------------------------------------------------------------------------
# Run
# ----------------------------------------------------------------

if [[ $do_check -eq 1 && $dry_run -eq 0 ]]; then
    echo "== qml-compile-check =="
    if ! "$src/tests/qml-compile-check.sh"; then
        echo "sync.sh: the QML does not compile, nothing was copied" >&2
        exit 1
    fi
fi

[[ $dry_run -eq 1 ]] && echo "-- dry run: nothing will be written --"

sync_tree "quickshell ($qs_dest)" \
    "${qs_keep[@]}" \
    ${qs_rsync_skip[@]+"${qs_rsync_skip[@]}"} \
    ${qs_root_owned[@]+"${qs_root_owned[@]}"} \
    "$src/" "$qs_dest/"

sync_tree "hyprland ($hypr_dest)" \
    "${hypr_keep[@]}" \
    ${hypr_root_owned[@]+"${hypr_root_owned[@]}"} \
    "$src/dots/.config/hypr/" "$hypr_dest/"

# After both copies, so nothing a copy just brought in is left unpatched.
if [[ $dry_run -eq 0 ]]; then
    deploy_patches
fi

verify_tree "quickshell" "$src" "$qs_dest" \
    "${qs_diff_keep[@]}" ${qs_diff_skip[@]+"${qs_diff_skip[@]}"}
verify_patched
verify_tree "hyprland" "$src/dots/.config/hypr" "$hypr_dest" "${hypr_diff_keep[@]}"

# Colour output is owned by the runtime, not by this sync -- say so rather than
# leaving the reader to wonder why a few files still differ.
echo "kept on the live side (by design):"
echo "  hyprland/colors.lua, hyprlock/colors.conf  -- regenerated from the wallpaper"
echo "  hyprland/shellOverrides/                   -- local gaps/blur tuning"
echo "  custom/, monitors.lua, profiles/           -- live-only, never in the repo"
echo "  ${#qs_rsync_skip[@]} scripts unchanged since install.sh patched them"

if [[ ${#root_owned_note[@]} -gt 0 ]]; then
    echo "not synced -- owned by root (content is compared anyway):"
    printf '  %s\n' "${root_owned_note[@]}"
    echo "  To let this script update them in future:"
    echo "    sudo chown -R $USER:$USER \"$hypr_dest\" \"$qs_dest\""
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
