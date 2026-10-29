#!/usr/bin/env bash
#
# Generates a qmldir tree that mirrors the virtual "qs" module Quickshell
# builds at runtime.
#
# Quickshell maps directories of the config onto module names:
#
#   modules/common/widgets  ->  qs.modules.common.widgets
#   modules/ii/bar          ->  qs.modules.ii.bar
#   services/ai             ->  qs.services.ai
#
# Those modules only exist while a shell is running, so qmllint cannot
# resolve them and cannot type check anything that uses them. Writing the
# equivalent qmldir files into a separate directory gives the type checker
# the same view of the config that the shell has.
#
# Usage: gen-qs-modules.sh <output-directory>
#
set -euo pipefail

OUT="${1:?usage: gen-qs-modules.sh <output-directory>}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rm -rf "$OUT"
mkdir -p "$OUT/qs"

# The root module. Quickshell itself provides qs.config from its own
# installation; the config only needs the namespace to exist.
printf 'module qs\n' > "$OUT/qs/qmldir"

# Write the qmldir for one directory of the config.
# $1: directory below the config root, e.g. modules/ii/bar
# $2: the module name it stands for, e.g. qs.modules.ii.bar
write_qmldir() {
    local dir="$1" module="$2"
    local target="$OUT/qs/${dir}"
    mkdir -p "$target"

    {
        echo "module $module"
        local file base
        for file in "$SRC/$dir"/*.qml; do
            [[ -e "$file" ]] || continue
            base="$(basename "$file" .qml)"
            # The component files stay in the config, the generated tree only
            # links to them, so there is exactly one copy of the source.
            ln -sf "$file" "$target/$base.qml"
            if grep -q "pragma Singleton" "$file"; then
                echo "singleton $base $base.qml"
            else
                echo "$base $base.qml"
            fi
        done
    } > "$target/qmldir"
}

# Map a config directory onto its module name.
#   modules/<a>/<b>  ->  qs.modules.<a>.<b>
#   services/<a>     ->  qs.services.<a>
module_name_for() {
    local dir="$1"
    case "$dir" in
        modules)  echo "qs.modules" ;;
        services) echo "qs.services" ;;
        modules/*)
            echo "qs.modules.${dir#modules/}" | tr '/' '.' ;;
        services/*)
            echo "qs.services.${dir#services/}" | tr '/' '.' ;;
        *)        echo "" ;;
    esac
}

for root in modules services; do
    [[ -d "$SRC/$root" ]] || continue
    while IFS= read -r dir; do
        module="$(module_name_for "$dir")"
        [[ -n "$module" ]] || continue
        write_qmldir "$dir" "$module"
    done < <(find "$SRC/$root" -type d | sed "s|^$SRC/||" | sort)
done

echo "$OUT"
