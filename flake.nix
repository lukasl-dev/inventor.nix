{
  description = "Experimental Autodesk Inventor installer and launcher for NixOS";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      perSystem =
        { pkgs, ... }:
        let
          inventor = pkgs.callPackage ./package.nix { };
        in
        {
          packages = {
            inherit inventor;
            default = inventor;
          };

          apps.default = {
            type = "app";
            program = "${inventor}/bin/inventor";
            meta.description = "Experiment with Autodesk Inventor through Wine";
          };

          formatter = pkgs.nixfmt-tree;

          devShells.default = pkgs.mkShell {
            packages = [
              inventor
              pkgs.nixfmt
              pkgs.shellcheck
              pkgs.python3
              pkgs.mypy
              pkgs.ruff
            ];
          };

          checks = {
            package = inventor;
            cli = pkgs.callPackage ./checks.nix { inherit inventor; };
          };
        };

      flake.overlays.default = final: _prev: {
        inventor = final.callPackage ./package.nix { };
      };
    };
}
