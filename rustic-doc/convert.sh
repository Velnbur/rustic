#!/usr/bin/env bash

LUA_FILTER="$HOME/.local/bin/rustic-doc-filter.lua"

function get_toolchain {
    # check if rustup is installed
    if ! command -v rustup &> /dev/null; then
        local toolchain_file

        # check if `rust-toolchain.toml` file exists
        if [ -f "$PROJECT_ROOT/rust-toolchain.toml" ]; then
            toolchain_file="rust-toolchain.toml"
        elif [ -f "$PROJECT_ROOT/rust-toolchain" ]; then
            toolchain_file="rust-toolchain"
        else
           echo "Error: rust-toolchain{.toml} file not found" >&2
           return 1
        fi

        # get toolchain from `rust-toolchain{.toml}` file instead
        if [[ "$toolchain_file" == *".toml" ]]; then
            sed -nr 's/channel = "(.*)"/\1/p' "$toolchain_file" | head -n 1
        else
            cat "$toolchain_file" | head -n 1
        fi
    else
        rustup show | sed -nr 's/(.*) \(default\)/\1/p' | head -n 1
    fi
}

if [ "$1" = "" ] || [ "$1" = "--help"  ]; then
    MY_NAME="$(basename "$0")"
    echo "Usage:"
    echo "  $MY_NAME <library> [project-root]"
    echo "  $MY_NAME <docs src> <docs org dst> [project-root]"
    exit 0
fi

DOC_PATH="$1"
DEST_DIR="$2"
PROJECT_ROOT="$3"

if [ "$DEST_DIR" = "" ]; then
    LIBRARY="$1"
    TARGET="$(get_toolchain)"

    ## Users can change the location of the rustup directory
    RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
    ## Set
    DOC_PATH="$RUSTUP_HOME/toolchains/$TARGET/share/doc/rust/html/$LIBRARY"
    DEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/emacs/rustic-doc/$LIBRARY"

    echo "Generating org files in: $DEST_DIR"
fi

echo "destination dir: $DEST_DIR"
mkdir -p "$DEST_DIR" || exit 1
cd "$DOC_PATH" || exit 1

## Copy directory structure
fd . -td -x mkdir -p "$DEST_DIR/{}"

## Find redirect files (removes $DOC_PATH prefix)
ignore_file="$(mktemp)"
rg -l "<p>Redirecting to <a href=\"[^\"]*\"" "$DOC_PATH" | \
    awk -v PRE="$DOC_PATH" '
BEGIN { m = length(PRE)
        if (!match(PRE, /\/$/))
           m += 1 }
{ print substr($0, m+1) }
' \
    > "$ignore_file"

if [[ "$OSTYPE" == "darwin"* ]]; then
    cores=$(eval "sysctl -n hw.logicalcpu")
else
   cores=$(nproc)
fi
## Convert files
fd . \
    -ehtml \
    --ignore-file "$ignore_file" \
    -j"$cores" \
    -x pandoc '{}' \
    --lua-filter "$LUA_FILTER" \
    -o "$DEST_DIR/{.}.org"
