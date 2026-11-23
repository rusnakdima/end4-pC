#!/usr/bin/env bash
# Contract test: the ii greeter accepts an arbitrary typed username and still
# works when userModel is empty.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
FIELD="$ROOT/sddm/ii-sddm-theme/Components/UsernameField.qml"
INPUT="$ROOT/sddm/ii-sddm-theme/Components/Input.qml"
LOGIN="$ROOT/sddm/ii-sddm-theme/Components/InputLogin.qml"

# 1. The component exists and exposes the selectUser-compatible API.
[[ -f "$FIELD" ]] || fail 'UsernameField.qml does not exist'
for token in 'currentText' 'currentIndex' 'selectionChanged' 'TextField'; do
    grep -q -- "$token" "$FIELD" || fail "UsernameField.qml missing: $token"
done

# 2. userModel roles: 257 = name, 260 = icon.
grep -q '257' "$FIELD" || fail 'UsernameField.qml does not read userModel name role 257'
grep -q '260' "$FIELD" || fail 'UsernameField.qml does not read userModel icon role 260'

# 3. Input.qml uses it under the existing id, and the old dropdown is gone.
grep -q 'UsernameField' "$INPUT" || fail 'Input.qml does not instantiate UsernameField'
grep -q 'id: selectUser' "$INPUT" || fail 'Input.qml lost id: selectUser'
if grep -q 'UserButton {' "$INPUT"; then fail 'Input.qml still instantiates UserButton'; fi

# 4. Every login path derives its first argument from selectUser.currentText.
grep -q 'readonly property string typedUser: selectUser.currentText.trim()' "$LOGIN" ||
    fail 'typed username is not trimmed in a single shared property'
login_calls="$(grep -c 'sddm.login(' "$LOGIN" || true)"
[[ "$login_calls" -ge 2 ]] || fail "expected >=2 sddm.login calls, got $login_calls"
if grep -n 'sddm.login(' "$LOGIN" | grep -v -E 'sddm\.login\((user|selectUser\.currentText),' >/dev/null; then
    fail 'a sddm.login call does not pass the typed username as its first argument'
fi
grep -q 'const user = ' "$LOGIN" || fail 'login argument is not derived from typedUser'

# 5. Username is trimmed on both login paths (count checked in 4).
# 6. Lowercase rule is still applied when uppercase letters are disallowed.
grep -q 'AllowUppercaseLettersInUsernames == "false"' "$LOGIN" || fail 'uppercase rule removed'
grep -q 'typedUser.toLowerCase()' "$LOGIN" || fail 'typed username is not lowercased'
# Login button must be enabled by the typed name, not by the model.
grep -q 'typedUser !== ""' "$LOGIN" || fail 'login button does not enable on typed username'

# 7. The field must stay usable with an empty userModel.
if grep -q 'userModel.count' "$FIELD"; then
    fail 'UsernameField.qml gates the field on userModel.count'
fi

echo 'PASS: typed-username greeter contract'
