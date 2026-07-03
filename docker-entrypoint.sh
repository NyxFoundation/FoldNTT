#!/usr/bin/env bash
# Resolve libstdc++ from the Nix store at run time (store paths are not
# stable across nixpkgs revs, so we glob instead of hardcoding) and make the
# pip-provided z3 wheel loadable, then run the given command.
set -euo pipefail
libdir="$(dirname "$(find /nix/store -maxdepth 3 -name 'libstdc++.so.6' 2>/dev/null | head -1)")"
export LD_LIBRARY_PATH="${libdir}:${LD_LIBRARY_PATH:-}"
export UV_PYTHON_PREFERENCE=only-system
export UV_PYTHON=/root/.nix-profile/bin/python3
exec "$@"
