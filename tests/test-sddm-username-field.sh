#!/usr/bin/env bash
# Contract test: the ii greeter keeps a user dropdown with an "Other user"
# option, and selecting it reveals a username field above the password field.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
THEME="$ROOT/sddm/ii-sddm-theme/Components"
BUTTON="$THEME/UserButton.qml"
INPUT="$THEME/Input.qml"
LOGIN="$THEME/InputLogin.qml"

# 1. Dropdown exists and exposes the selectUser-compatible API plus the
#    "Other user" sentinel.
[[ -f "$BUTTON" ]] || fail 'UserButton.qml does not exist'
for token in 'currentText' 'selectionChanged' 'signal accepted' 'otherUserIndex' 'isOtherUser'; do
    grep -q -- "$token" "$BUTTON" || fail "UserButton.qml missing: $token"
done
grep -q 'qsTr("Other user")' "$BUTTON" || fail 'no "Other user" option in the dropdown'
grep -q 'model: userModel.count + 1' "$BUTTON" || fail 'dropdown does not append a row past userModel'
grep -q '257' "$BUTTON" || fail 'dropdown does not read name role 257'
grep -q '260' "$BUTTON" || fail 'dropdown does not read icon role 260'
grep -q 'ava-violet-2x.png' "$BUTTON" || fail 'device avatar patch lost'

# 2. Input.qml still uses the dropdown under the existing id; the free-text
#    replacement is gone.
grep -q 'UserButton {' "$INPUT" || fail 'Input.qml does not instantiate UserButton'
grep -q 'id: selectUser' "$INPUT" || fail 'Input.qml lost id: selectUser'
if grep -q 'UsernameField' "$INPUT"; then fail 'Input.qml still uses UsernameField'; fi
grep -q 'onSelectionChanged' "$INPUT" || fail 'selection does not update focus'
grep -q 'focusActiveUserField' "$INPUT" || fail 'selection does not focus the active field'

# 3. Username field lives above the password field and is gated on the
#    "Other user" selection (not on userModel.count).
grep -q 'id: usernameFieldWrap' "$LOGIN" || fail 'no username field wrapper in InputLogin.qml'
grep -q 'visible: selectUser.isOtherUser' "$LOGIN" || fail 'username field is not gated on Other user'
grep -q 'ColumnLayout' "$LOGIN" || fail 'password row is not stacked under a username field'
grep -q 'id: usernameField' "$LOGIN" || fail 'no username TextField'
if grep -q 'visible: userModel.count' "$LOGIN"; then
    fail 'username field is gated on userModel.count'
fi
grep -q 'Keys.onReturnPressed' "$LOGIN" || fail 'Enter in username field is not handled'
grep -q 'password.forceActiveFocus()' "$LOGIN" || fail 'Enter does not move focus to password'

# 4. Login argument is derived from the dropdown selection OR the typed
#    username, trimmed and lowercased when uppercase is disallowed.
grep -q 'typedUsername: usernameField.text.trim()' "$LOGIN" ||
    fail 'typed username is not trimmed'
grep -q 'rawUsername: selectUser.isOtherUser ? typedUsername : selectUser.currentText.trim()' "$LOGIN" ||
    fail 'login username is not chosen from Other user vs dropdown selection'
grep -q 'AllowUppercaseLettersInUsernames == "false"' "$LOGIN" || fail 'uppercase rule removed'
grep -q 'rawUsername.toLowerCase()' "$LOGIN" || fail 'username is not lowercased when required'
login_calls="$(grep -c 'sddm.login(' "$LOGIN" || true)"
[[ "$login_calls" -ge 2 ]] || fail "expected >=2 sddm.login calls, got $login_calls"
if grep -n 'sddm.login(' "$LOGIN" | grep -v 'sddm.login(effectiveUsername,' >/dev/null; then
    fail 'a sddm.login call does not pass effectiveUsername first'
fi

# 5. Both login paths reject an empty username, and failure clears the
#    typed field so a stale name cannot be reused.
empty_guards="$(grep -c 'effectiveUsername !== "" && password.text !== ""' "$LOGIN" || true)"
[[ "$empty_guards" -ge 2 ]] || fail "expected empty-username guard on both login paths, got $empty_guards"
grep -q 'usernameField.text = ""' "$LOGIN" || fail 'login failure does not clear the typed username'

# 6. Syntax check.
if command -v qmllint >/dev/null 2>&1; then
    for f in "$BUTTON" "$INPUT" "$LOGIN"; do
        out="$(qmllint "$f" 2>&1)" || fail "qmllint failed for $f: $out"
    done
fi

echo 'PASS: Other-user dropdown and username-field contract'
