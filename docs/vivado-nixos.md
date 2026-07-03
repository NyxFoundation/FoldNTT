# Vivado on NixOS — setup for the whole-core PnR numbers

Vivado is the blocker for the reviewer-grade LUT/FF/DSP/BRAM/Fmax numbers
(paper §8). It is a proprietary, dynamically-linked binary that does **not**
run as-is on NixOS (no `/lib64/ld-linux…`, no FHS). Below are three working
approaches, easiest first. AMD/Xilinx **Vivado ML Standard is free** and
includes the Artix-7 devices CFNTT targets — no paid license needed for this.

Target part: an Artix-7 to match CFNTT (e.g. `xc7a200tfbg484-1`, or whatever
the CFNTT paper used — confirm from it). Flow: synth → place → route →
`report_utilization` + `report_timing_summary`.

---

## Option A — `buildFHSEnv` wrapper (recommended, fully declarative)

NixOS can conjure an FHS sandbox with the libraries Vivado's installer and
runtime expect. Put this in a file and enter it; run the AMD installer once
inside, then Vivado runs inside the same env.

`vivado-fhs.nix`:

```nix
{ pkgs ? import <nixpkgs> {} }:
(pkgs.buildFHSEnv {
  name = "vivado-env";
  targetPkgs = p: with p; [
    # installer + runtime deps Vivado dlopen's
    ncurses5 zlib libuuid xorg.libX11 xorg.libXext xorg.libXrender
    xorg.libXtst xorg.libXi xorg.libxcb gtk2 glib gcc-unwrapped.lib
    fontconfig freetype expat coreutils gnused gnugrep which
    graphviz libGL nss nspr
  ];
  # Vivado needs a big /tmp and writable $HOME
  runScript = "bash";
}).env
```

```sh
nix-shell vivado-fhs.nix
# inside the FHS shell, one-time install (after downloading the AMD unified
# installer .bin from xilinx.com — free account):
chmod +x FPGAs_AdaptiveSoCs_Unified_*.bin && ./FPGAs_AdaptiveSoCs_Unified_*.bin
# then, in later sessions:
nix-shell vivado-fhs.nix --run 'source /tools/Xilinx/Vivado/2024.2/settings64.sh && vivado -mode batch -source pnr.tcl'
```

Notes: install to a path you own (e.g. `~/Xilinx`) to avoid needing root;
point `settings64.sh` there. `ncurses5`/`ncurses6` mismatch is the usual
first error — `ncurses5` above fixes the classic `libtinfo.so.5` failure.

## Option B — community flake (`nix-community/vivado-nix` style)

Several community flakes package the FHS + desktop entry. If you use flakes:

```sh
# example — check the flake's own README for the exact attr/version
nix run github:<community>/vivado-nix#vivado -- -mode batch -source pnr.tcl
```

These essentially automate Option A (FHS + `settings64.sh` sourcing) and add
a `.desktop` launcher. Good if you want the GUI; for CI/batch, Option A or C
is leaner. (Verify the flake is current before relying on it — Vivado
versions move quarterly.)

## Option C — Docker/OCI with an FHS base (best for CI / a clean number)

For a reproducible PnR run decoupled from the host, use an Ubuntu-based
image (Vivado's supported OS) and run it via Docker on NixOS (which we
already have — see the artifact `Dockerfile`). AMD publishes install docs for
headless Ubuntu; the image caches the install so PnR is one `docker run`.
This is the cleanest way to put an Fmax number in the paper that a reviewer
can reproduce without a NixOS host.

---

## Open-source pre-check (no Vivado, do this first)

Before committing to Vivado, get a *first* timing/area estimate from the open
flow — it needs no license and runs in the existing Nix shell, and tells us
whether `fold7` closes timing on the ROM path and whether the K-RED adder
chains regress the critical path:

```sh
nix shell nixpkgs#yosys nixpkgs#nextpnr-xilinx nixpkgs#prjxray --command bash -lc '
  yosys -p "read_verilog proposed/kred/modular_mul_kred.v; \
            synth_xilinx -flatten -family xc7 -top modular_mul_kred; \
            write_json mmk.json"
  # nextpnr-xilinx needs a prjxray chipdb for the target part; see its README
'
```

`synth_xilinx` alone already gives **LUT/DSP/BRAM** estimates (via
`report_utilization`-like `stat`), which is enough for a directional per-module
table; `nextpnr-xilinx` adds Fmax if a chipdb is available. This is the
recommended next concrete step — it produces a real (if not vendor-official)
number now, and de-risks the Vivado setup.

## What to report in the paper

Per module (multiplier, butterfly, ROM) and — once the FSM reconstruction is
finished (§8) — whole-core: **LUT, FF, DSP48, BRAM, and Fmax**, reference vs
proposed, on the same Artix-7 part and Vivado version, with the exact part
number and tool version in the caption. Keep the yosys generic-cell numbers
(already in `evaluation.md`) as the technology-independent view alongside.

## Concrete next steps (in order)

1. `synth_xilinx` per module now (Option "pre-check") → first LUT/DSP/BRAM
   table; confirms fold7/K-RED timing direction. **No license, runs today.**
2. Finish the banked-FSM reconstruction (`proposed/fullcore/fsm_recon.v`) so
   a whole synthesizable core exists.
3. Vivado via Option A (or C for CI) on `xc7a200t` → official
   LUT/FF/DSP/BRAM/Fmax, v1 vs v2, for the camera-ready.
