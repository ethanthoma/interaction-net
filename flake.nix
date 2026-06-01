{
  description = "Interaction Nets in Odin";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
  };

  outputs =
    inputs@{ flake-parts, devshell, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ devshell.flakeModule ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, ... }:
        {
          packages.default = pkgs.callPackage ./nix { };

          devshells.default = {
            packages = [
              pkgs.odin
              pkgs.ols
            ];

            env = [
              {
                name = "ODIN_ROOT";
                value = "${pkgs.odin}/share";
              }
            ];
          };
        };
    };
}
