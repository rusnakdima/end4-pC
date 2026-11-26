#!/usr/bin/env bash
# Offline checks for the Peek fish/nvim snippets, installer and docs.
# Run with: bash tests/test_peek_integrations.sh

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

failures=0
check() {
    local needle="$1" file="$2" label="$3"
    if grep -Fq -- "$needle" "$file"; then
        printf '  OK   %s\n' "$label"
    else
        printf '  FAIL %s (missing: %s)\n' "$label" "$needle"
        failures=$((failures + 1))
    fi
}

fish_snippet=features/peek/fish.fish
nvim_snippet=features/peek/nvim-keymaps.lua
installer=install.sh
readme=README.md

for file in "$fish_snippet" "$nvim_snippet"; do
    if [[ -f "$file" ]]; then
        printf '  OK   %s exists\n' "$file"
    else
        printf '  FAIL %s missing\n' "$file"
        failures=$((failures + 1))
    fi
done

check 'call peek openPath' "$fish_snippet" 'fish sends a path via peek openPath'
check '"$end4pc_qs_config_path"' "$fish_snippet" 'fish uses the explicit Quickshell config path'
check 'openText' "$fish_snippet" 'fish defines openText'
check 'function peek' "$fish_snippet" 'fish defines the peek function'
check '--text' "$fish_snippet" 'fish accepts selected text with --text'

check '"n", "<leader>p"' "$nvim_snippet" 'nvim normal-mode leader-p mapping'
check '"v", "<leader>p"' "$nvim_snippet" 'nvim visual-mode leader-p mapping'
check '%:p' "$nvim_snippet" 'nvim mapping sends the current file path'
check 'getregion' "$nvim_snippet" 'nvim mapping reads the visual selection'
check 'openText' "$nvim_snippet" 'nvim mapping sends selected text'
check 'nvim_create_user_command("Peek"' "$nvim_snippet" 'nvim defines the Peek command'

check 'install_peek_configs()' "$installer" 'installer defines install_peek_configs'
check 'conf.d/peek.fish' "$installer" 'installer deploys the fish snippet'
check 'nvim-keymaps.lua' "$installer" 'installer deploys the nvim keymaps'
check 'end4-pC peek keymaps' "$installer" 'installer uses the peek keymaps marker'
check '    install_peek_configs' "$installer" 'installer calls install_peek_configs'

function_body=$(awk '/^install_peek_configs\(\) \{/{flag=1} flag{print} flag && /^\}/{flag=0}' "$installer")
if printf '%s\n' "$function_body" | grep -Fq -- 'grep -qF "$marker"'; then
    printf '  OK   installer guards against duplicate keymap blocks\n'
else
    printf '  FAIL installer must grep for the marker before appending\n'
    failures=$((failures + 1))
fi

check 'Alt+Space' "$readme" 'README documents Alt+Space'
check 'PRIMARY' "$readme" 'README documents PRIMARY selection'
check 'clipboard' "$readme" 'README documents clipboard behaviour'
check 'nvim' "$readme" 'README documents nvim editing'
check 'swappy' "$readme" 'README documents swappy for images'

if [[ $failures -gt 0 ]]; then
    printf '%d Peek integration check(s) failed\n' "$failures"
    exit 1
fi
printf 'Peek integration checks passed\n'
