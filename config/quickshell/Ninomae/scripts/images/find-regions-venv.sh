#!/usr/bin/env bash
# find_regions.py with the shell's venv (it has OpenCV). One thread: importing OpenCV otherwise starts a
# thread per core, ~1.5 s of CPU each time the screenshot tool opens, for the same result
here="$(dirname -- "$(readlink -f -- "$0")")"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
exec "${NINOMAE_SHELL_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}/bin/python3" "$here/find_regions.py" "$@"
