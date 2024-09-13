{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    (flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          odin = pkgs.callPackage ./nix/odin.nix {
            MacOSX-SDK = pkgs.darwin.apple_sdk;
            inherit (pkgs.darwin) Security;
          };
        in
        {
          packages.default = pkgs.stdenv.mkDerivation rec {
            pname = "myapp";
            version = "0.1";
            src = ./src;

            nativeBuildInputs = [ odin ];

            buildPhase = ''
              odin build $src -out:${pname}
              mkdir -p $out/bin
              mv ${pname} $out/bin/
            '';
          };

          checks.default = pkgs.runCommandLocal "odin-test"
            {
              src = ./src;
              nativeBuildInputs = [ odin ];
            } ''
            odin test $src & touch $out
          '';

          devShells.default =
            let
              ols = pkgs.ols.overrideAttrs (finalAttrs: previousAttrs: {
                buildInputs = [ odin ];
                env.ODIN_ROOT = "${odin}/share";
              });
            in
            pkgs.mkShell
              {
                packages = [
                  odin
                  ols
                ];

                env.ODIN_ROOT = "${odin}/share";
              };
        }
      )
    );
}
