{
  description =
    "FoldNTT — a verified, DSP-minimal NTT accelerator + a Vivado-free FPGA flow";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # openXC7 gives nextpnr-xilinx + the Artix-7 chipdb entirely in nix (no
    # Vivado, no vendor download).  Pin the 0.8.2 TAG: HEAD's flake currently
    # fails to evaluate ('nextpnr-xilinx' missing from its nixpkgs binding),
    # whereas 0.8.2 has a self-consistent flake.lock and builds.
    openxc7 = {
      url = "github:openXC7/toolchain-nix/0.8.2";
      # do not follow our nixpkgs — 0.8.2's own locked nixpkgs is what makes
      # it build; overriding it reintroduces the eval break.
    };
  };

  outputs = { self, nixpkgs, openxc7 }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      xc = openxc7.packages.${system};
      # Artix-7 xc7a100t — same family as CFNTT and Compact-FALCON.
      chipdb = "${xc.nextpnr-xilinx-chipdb.artix7}/xc7a100tcsg324.bin";
      np = "${xc.nextpnr-xilinx}/bin/nextpnr-xilinx";
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          xc.nextpnr-xilinx # openXC7 place & route
          pkgs.yosys # synthesis (synth_xilinx)
          pkgs.python3 # wrap.py, run_*.py
          pkgs.iverilog # functional sims
          pkgs.uv # PEP-723 z3 / math scripts
        ];
        # Wire the env the FPGA scripts read, so they run with no arguments:
        #   nix develop
        #   fpga/fmax.sh          # per-module post-route Fmax
        #   fpga/fmax_core.sh     # whole-core post-route Fmax
        shellHook = ''
          export NP=${np}
          export CHIPDB=${chipdb}
          export YOSYS=yosys
          echo "openXC7 flow ready:  NP + CHIPDB (xc7a100t) set."
          echo "  per-module Fmax:  fpga/fmax.sh"
          echo "  whole-core Fmax:  fpga/fmax_core.sh"
        '';
      };

      # Expose the pinned tools for scripting / CI without entering the shell:
      #   nix build .#nextpnr-xilinx   /   nix build .#artix7-chipdb
      packages.${system} = {
        nextpnr-xilinx = xc.nextpnr-xilinx;
        artix7-chipdb = xc.nextpnr-xilinx-chipdb.artix7;
      };
    };
}
