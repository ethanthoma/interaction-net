{
  description = "Interaction Nets in Odin";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        odin = pkgs.callPackage ./nix/odin.nix {
          MacOSX-SDK = pkgs.darwin.apple_sdk;
          inherit (pkgs.darwin) Security;
        };
      in
      {
        packages.default = pkgs.callPackage ./nix { inherit odin; };

        devShells.default = pkgs.callPackage ./nix/shell.nix { inherit odin; };
      }
    ));
}
