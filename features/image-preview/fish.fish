# end4-pC Image Preview — fish integration
# Install: source this file from ~/.config/fish/config.fish
# Provided by the theme repo (features/image-preview/fish.fish).

# `img` is an alias for `ishow` so it works inside AND outside kitty.
abbr --add --force img ishow

function ishow -d 'Show an image inline (kitty graphics / chafa fallback / QML widget)'
    set -l widget 0
    set -l paths

    for arg in $argv
        switch $arg
            case -w --widget
                set widget 1
            case -h --help
                echo "Usage: ishow [--widget] <image>..."
                return 0
            case '*'
                set -a paths $arg
        end
    end

    if test (count $paths) -eq 0
        echo "ishow: no image path given" >&2
        return 1
    end

    # --widget pushes the path to the QuickShell Image Preview panel.
    if test $widget -eq 1
        for path in $paths
            command qs ipc call imagePreview openPath $path
        end
        return 0
    end

    if test -n "$KITTY_WINDOW_ID"; and command -v kitten >/dev/null
        kitten icat --transfer-mode=file $paths
    else if command -v chafa >/dev/null
        chafa --colors 256 --symbols braille $paths
    else
        echo "ishow: install chafa or run inside kitty" >&2
        return 1
    end
end
