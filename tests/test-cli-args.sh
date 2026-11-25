#!/usr/bin/env bash
#
# test-cli-args.sh -- CLI contract tests for install.sh, install-system.sh,
# sync.sh. Runs no installers: install.sh is copied with its `main "$@"` line
# removed, and the other two scripts only exercise their argument parsing.
#
set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Keep every test away from the real user's config.
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/home/.config"
mkdir -p "$HOME"

pass=0
fail=0

ok()  { printf 'ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$1"; printf '       %s\n' "${2:-}"; fail=$((fail + 1)); }

# expect LABEL EXPECTED_STATUS NEEDLE COMMAND...
expect() {
    local label="$1" expected="$2" needle="$3"; shift 3
    local out status
    out=$("$@" 2>&1); status=$?
    if [[ $status -ne $expected ]]; then
        bad "$label" "status $status, expected $expected: $out"
    elif [[ -n "$needle" ]] && ! grep -qiF -- "$needle" <<<"$out"; then
        bad "$label" "output missing '$needle': $out"
    else
        ok "$label"
    fi
}

# A sandbox copy cannot deploy anything, so testing install.sh's parser is safe.
install_cli="$tmp/install.sh"
sed '/^main "\$@"$/d' "$root/install.sh" > "$install_cli"

# --- install.sh -------------------------------------------------------------
expect "install.sh --help documents flags" 0 "--offline" bash "$install_cli" --help
expect "install.sh --help documents target-user" 0 "--target-user" bash "$install_cli" --help
expect "install.sh --help documents exit codes" 0 "exit" bash "$install_cli" --help
expect "install.sh rejects unknown flags" 2 "unknown" bash "$install_cli" --bogus
expect "install.sh rejects invalid --vnc-mode" 2 "mirror" bash "$install_cli" --vnc-mode=bogus
expect "install.sh rejects invalid --vnc-audio" 2 "sunshine" bash "$install_cli" --vnc-audio=bogus
expect "install.sh rejects invalid --vnc-autologin" 2 "0 or 1" bash "$install_cli" --vnc-autologin=maybe
expect "install.sh rejects missing --wheelhouse value" 2 "value" bash "$install_cli" --wheelhouse
expect "install.sh rejects unknown --target-user" 2 "unknown user" bash "$install_cli" --target-user=no-such-user-xyz
expect "install.sh accepts --opt value form before --help" 0 "Usage" bash "$install_cli" --vnc-mode mirror --help
expect "install.sh rejects invalid binary env var" 2 "0 or 1" env APP_THEMING=maybe bash "$install_cli"
expect "install.sh rejects missing wheelhouse directory" 2 "does not exist" env OFFLINE_WHEELHOUSE=/no/such/dir bash "$install_cli"

# --- install-system.sh ------------------------------------------------------
expect "install-system.sh --help documents flags" 0 "--dry-run" bash "$root/install-system.sh" --help
expect "install-system.sh rejects unknown flags" 2 "unknown" bash "$root/install-system.sh" --bogus
expect "install-system.sh --dry-run changes nothing" 0 "dry" bash "$root/install-system.sh" --dry-run
expect "install-system.sh --dry-run lists --extra-pkg" 0 "end4pc-test-pkg" \
    bash "$root/install-system.sh" --dry-run --extra-pkg=end4pc-test-pkg

# --- sync.sh ----------------------------------------------------------------
expect "sync.sh --help documents exit codes" 0 "exit" bash "$root/sync.sh" --help
expect "sync.sh --help documents --user NAME form" 0 "--user NAME" bash "$root/sync.sh" --help
expect "sync.sh rejects unknown flags" 2 "unknown" bash "$root/sync.sh" --bogus
expect "sync.sh rejects missing --user value" 2 "value" bash "$root/sync.sh" --user
expect "sync.sh rejects unknown --user" 2 "unknown user" bash "$root/sync.sh" --user=no-such-user-xyz
expect "sync.sh accepts --user NAME two-token form" 0 "Usage" bash "$root/sync.sh" --user root --help

# No test may have written into the fake home.
if [[ -d "$HOME/.config" ]]; then
    bad "no filesystem writes" "$HOME/.config was created"
else
    ok "no filesystem writes"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
