#!/usr/bin/env bash
# Installs a builder release for the setup-builder action. Reads VERSION, REPOSITORY, PINNED_SHA256
# and INSTALL_NINJA from the environment, and writes to the files GitHub Actions provides.
set -euo pipefail

fail() {
    echo "::error::$1"
    exit 1
}

[ -n "${VERSION:-}" ] || fail "setup-builder needs a version"

case "$RUNNER_OS" in
    Windows) host=win32 ext=zip exe=builder.exe ;;
    Linux) host=linux ext=tar.gz exe=builder ;;
    *) fail "builder has no release for $RUNNER_OS" ;;
esac

# On Windows the runner's paths are native; bash works on its own spelling of them, and later steps,
# which may run in PowerShell, need the native one.
native() {
    if [ "$RUNNER_OS" = Windows ]; then cygpath -w "$1"; else printf '%s\n' "$1"; fi
}
posix() {
    if [ "$RUNNER_OS" = Windows ]; then cygpath -u "$1"; else printf '%s\n' "$1"; fi
}

name="builder-$VERSION-$host"
archive="$name.$ext"
# Builder releases are tagged builder-<version>, apart from the action's own v<major> tags.
url="https://github.com/$REPOSITORY/releases/download/builder-$VERSION/$archive"
root="$(posix "$RUNNER_TOOL_CACHE")/builder/$VERSION"
dir="$root/$name"

# A self-hosted runner keeps its tool cache, so a release already extracted there is used as it is.
if [ ! -x "$dir/$exe" ]; then
    work="$(mktemp -d "$(posix "$RUNNER_TEMP")/setup-builder.XXXXXX")"
    trap 'rm -rf "$work"' EXIT
    echo "Downloading $url"
    curl -fsSL --retry 3 -o "$work/$archive" "$url" || fail "cannot download $url"
    if [ -n "${PINNED_SHA256:-}" ]; then
        expected="$PINNED_SHA256"
    else
        curl -fsSL --retry 3 -o "$work/$archive.sha256" "$url.sha256" || fail "cannot download $url.sha256"
        expected="$(cut -d ' ' -f 1 "$work/$archive.sha256")"
    fi
    actual="$(sha256sum "$work/$archive" | cut -d ' ' -f 1)"
    [ "${actual,,}" = "${expected,,}" ] || fail "$archive has SHA-256 $actual, expected $expected"

    mkdir -p "$work/content"
    if [ "$ext" = zip ]; then
        unzip -q "$work/$archive" -d "$work/content"
    else
        tar -xzf "$work/$archive" -C "$work/content"
    fi
    [ -x "$work/content/$name/$exe" ] || fail "$archive holds no $name/$exe"
    mkdir -p "$root"
    rm -rf "$dir"
    mv "$work/content/$name" "$dir"
fi

reported="$("$dir/$exe" --version)"
echo "Installed $reported"

if [ "$RUNNER_OS" = Linux ] && [ "${INSTALL_NINJA:-true}" = true ] && ! command -v ninja > /dev/null; then
    echo "Installing Ninja"
    sudo apt-get update -qq
    sudo apt-get install -y -qq ninja-build
fi

cache_dir="${BUILDER_CACHE_DIR:-$(native "$(posix "$RUNNER_TEMP")/builder-cache")}"
mkdir -p "$(posix "$cache_dir")"

native "$dir" >> "$GITHUB_PATH"
echo "BUILDER_CACHE_DIR=$cache_dir" >> "$GITHUB_ENV"
{
    echo "path=$(native "$dir")"
    echo "version=${reported#builder }"
    echo "cache-dir=$cache_dir"
} >> "$GITHUB_OUTPUT"
