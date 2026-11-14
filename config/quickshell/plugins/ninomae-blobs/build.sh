#!/usr/bin/env bash
# Builds Ninomae.Blobs (and Ninomae.Particles, when Qt's GPU headers are there) into ~/.local/lib/qt6/qml/Ninomae.
# Needs: sudo dnf install qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtshadertools-devel qt6-qtbase-private-devel
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
# Install each file under a temporary name, then rename it into place. Copying over the .so
# in place corrupts it inside a running Quickshell (it crashed when the installer rebuilt it);
# a rename leaves the running copy intact and new starts get the new build.
for module in Blobs Particles; do
    [[ -f $build/qml/Ninomae/$module/qmldir ]] && compgen -G "$build/qml/Ninomae/$module/*.so" >/dev/null || continue
    to="$(dirname "$dest")/$module"
    mkdir -p "$to"
    for f in "$build"/qml/Ninomae/$module/{qmldir,*.qmltypes,*.so}; do
        tmp="$to/.$(basename "$f").new"
        cp "$f" "$tmp"
        mv -f "$tmp" "$to/$(basename "$f")"
    done
done
# What it was built against, so ensure-built.sh knows when Qt or the sources change
"$here/ensure-built.sh" --stamp >"$dest/.built-against"
printf 'Installed %s to %s\n' "$(cd "$(dirname "$dest")" && ls -d Blobs Particles 2>/dev/null | sed 's/^/Ninomae./' | paste -sd ' ')" "$(dirname "$dest")"
