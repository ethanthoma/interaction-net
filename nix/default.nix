{ pkgs
, odin
,
}:
pkgs.stdenv.mkDerivation
rec {
  pname = "inio";
  version = "0.1";
  src = ../.;

  nativeBuildInputs = [ odin ];

  buildPhase = ''
    odin build $src/src -show-timings -out:${pname} -microarch:native -no-bounds-check -o:speed
    mkdir -p $out/bin
    mv ${pname} $out/bin/

    cp -r $src/examples/ $out
  '';

  doCheck = true;

  checkPhase = ''
    odin test $src/src
  '';

  meta = with pkgs.lib;
    {
      description = "Interaction Net compiler and runtime in Odin";
      platforms = platforms.all;
    };
}
