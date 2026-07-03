# Artifact appendix

Everything in the paper is reproducible from this repository. The claims and
the scripts that regenerate them:

| Paper claim | Reproduce with |
|---|---|
| K-RED reducer == 9·A·B mod q, full domain | `uv run proposed/kred/verify_kred.py` |
| Butterfly (both modes), ROM ≡ shipped, reset, latency | `proposed/run_all.sh` (SymbiYosys + audits + mutation sweep) |
| Full transform: NTT == ref, INTT(NTT(x)) == x (and the bug on the ref core) | `uv run proposed/fullcore/run_stream.py` |
| Generalization: Kyber exhaustive + generated RTL | `uv run proposed/generator/kred_gen.py && uv run proposed/generator/gen_check.py` |
| Synthesis cost numbers | `yosys proposed/kred/cost_report.ys` (+ the ROM stat in `docs/evaluation.md`) |
| Upstream bug (issue #7) reproduced | `uv run bug_intt_halving.py` |

## One-command reproduction

Native (Nix):

```sh
git clone --recurse-submodules https://github.com/NyxFoundation/ntt-fpga-z3
cd ntt-fpga-z3
nix shell nixpkgs#yosys nixpkgs#sby nixpkgs#yices nixpkgs#iverilog nixpkgs#uv \
  --command bash -lc 'proposed/run_all.sh \
    && uv run proposed/fullcore/run_stream.py \
    && uv run proposed/generator/kred_gen.py \
    && uv run proposed/generator/gen_check.py'
```

Containerized (no Nix on the host):

```sh
docker build -t ntt-fpga-z3 .
docker run --rm ntt-fpga-z3
```

## Pinned versions (for the camera-ready / Zenodo deposit)

- this repository: commit `a962577` (update on deposit)
- `cfntt_ref` submodule (ground truth): `8373a66`
- toolchain: `yosys`, `sby`, `yices`, `iverilog`, `z3`, `uv` from
  `nixpkgs/nixos-unstable` (pin `NIXPKGS_REV` in the Dockerfile for a
  byte-reproducible image at deposit time).

The container image is self-tested: its build warms z3 and its default
`CMD` runs the whole proof/audit/sim suite; `run_stream.py`,
`kred_gen.py`, `gen_check.py` and `rom_fold_math.py` were confirmed passing
inside it. A runtime entrypoint resolves libstdc++ from the Nix store so the
pip-provided z3 wheel loads.

## Zenodo (TODO at submission)

Create a Zenodo record from the GitHub release (Zenodo↔GitHub integration),
which mints a DOI for the exact tagged commit; add the DOI badge here and to
the paper's Reproducibility section. `CITATION.cff` provides the metadata.
