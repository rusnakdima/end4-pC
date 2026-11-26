# end4-pC Peek — fish integration
# Install: source this file from ~/.config/fish/config.fish
# Provided by the theme repo (features/peek/fish.fish).

# Quickshell is launched with an explicit -p config path, so `qs ipc` must be
# given the same path or it looks for a non-existent "default" config.
set -g -x end4pc_qs_config_path /home/dmitriy/.config/quickshell/end4-pC

function peek -d 'Preview a file or selected text in the shell'
    set -l text_mode 0
    set -l values
    for arg in $argv
        switch $arg
            case --text -t
                set text_mode 1
            case -h --help
                echo "Usage: peek <path>...  |  peek --text <text>"
                return 0
            case '*'
                set -a values $arg
        end
    end
    if test (count $values) -eq 0
        echo "peek: no path or text given" >&2
        return 1
    end
    if not command -v qs >/dev/null
        echo "peek: qs (quickshell) not found on PATH" >&2
        return 1
    end
    set -l cfg "$end4pc_qs_config_path"
    if test -z "$cfg"; or test ! -f "$cfg/shell.qml"
        echo "peek: end4-pC Quickshell config not found at '$cfg'" >&2
        return 1
    end
    if test $text_mode -eq 1
        command qs ipc -p "$cfg" call peek openText "$values"
    else
        for path in $values
            command qs ipc -p "$cfg" call peek openPath "$path"
        end
    end
    if test $status -ne 0
        echo "peek: could not reach Quickshell (is it running?)" >&2
        return 1
    end
end
