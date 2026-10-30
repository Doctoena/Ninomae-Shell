#!/usr/bin/env bash
# Builds Ninomae.Blobs and installs it to ~/.local/lib/qt6/qml/Ninomae/Blobs.
# Needs: sudo dnf install qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtshadertools-devel
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build="${XDG_CACHE_HOME:-$HOME/.cache}/ninomae-blobs-build"
dest="$HOME/.local/lib/qt6/qml/Ninomae/Blobs"
# A build folder set up from another source path (the dotfiles were moved) makes cmake refuse to
# run, which silently left an old build installed: start that one over
if [[ -f "$build/CMakeCache.txt" ]] && ! grep -qxF "CMAKE_HOME_DIRECTORY:INTERNAL=$here" "$build/CMakeCache.txt"; then
    rm -rf "$build"
fi
cmake -S "$here" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$build"
mkdir -p "$dest"
# Install each file under a temporary name, then rename it into place. Copying over the .so
# in place corrupts it inside a running Quickshell (it crashed when the installer rebuilt it);
# a rename leaves the running copy intact and new starts get the new build.
for f in "$build"/qml/Ninomae/Blobs/{qmldir,*.qmltypes,*.so}; do
    tmp="$dest/.$(basename "$f").new"
    cp "$f" "$tmp"
    mv -f "$tmp" "$dest/$(basename "$f")"
done
# What it was built against, so ensure-built.sh knows when Qt or the sources change
"$here/ensure-built.sh" --stamp >"$dest/.built-against"
printf 'Installed Ninomae.Blobs to %s\n' "$dest"
