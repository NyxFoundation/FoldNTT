# Reproducible artifact image for ntt-fpga-z3.
# Pins the whole open-source verification toolchain (yosys, SymbiYosys,
# yices, iverilog, z3, uv/python) via Nix so `proposed/run_all.sh` and the
# full-transform / generator simulations reproduce every claim in the paper.
#
#   docker build -t ntt-fpga-z3 .
#   docker run --rm ntt-fpga-z3            # runs the whole suite
#   docker run --rm -it ntt-fpga-z3 bash   # interactive
#
# The image bakes a Nix profile so no network is needed at run time.
FROM nixos/nix:2.24.9

# Enable flakes/nix-command for reproducible `nix profile`.
RUN mkdir -p /etc/nix && \
    printf 'experimental-features = nix-command flakes\nfilter-syscalls = false\n' \
      >> /etc/nix/nix.conf

# Pin nixpkgs to a specific tarball for a reproducible toolchain and install
# with nix-env (profile install would need --impure inside the builder).
ARG NIXPKGS_REV=nixos-unstable
RUN nix-env --install --attr \
      yosys sby yices iverilog z3 uv python3 gcc-unwrapped git bash coreutils \
      -f "https://github.com/NixOS/nixpkgs/archive/${NIXPKGS_REV}.tar.gz" && \
    nix-collect-garbage -d

# Copy the repository (with its pinned cfntt_ref submodule already checked out).
WORKDIR /work
COPY . /work

# Use the Nix-provided CPython (no managed-python download at run time) and
# warm the z3-solver environment so scripts run offline.
COPY docker-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    /usr/local/bin/entrypoint.sh uv run --with z3-solver python3 -c "import z3; print('z3', z3.get_version_string())"
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default: run the complete proof/audit/sim suite for both inventions.
CMD ["bash", "-lc", "proposed/run_all.sh && uv run proposed/fullcore/run_stream.py && uv run proposed/generator/kred_gen.py && uv run proposed/generator/gen_check.py"]
