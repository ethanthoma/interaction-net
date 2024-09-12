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

                    odin =  pkgs.callPackage ./nix/odin.nix {
                        MacOSX-SDK = pkgs.darwin.apple_sdk;
                        inherit (pkgs.darwin) Security ;
                    }; 
                in
                    {
                    packages.default = pkgs.stdenv.mkDerivation rec {
                        pname = "myapp";
                        version = "0.1";
                        src = ./src;


                        nativeBuildInputs = [
                            odin
                        ];

                        buildPhase = ''
                            odin build .
                            mkdir -p $out/bin
                            mv src $out/bin/${pname}
                        '';
                    };

                    devShells.default = pkgs.mkShell {
                        packages = [
                            odin 
                        ];
                    };
                }
            )
        );
}
