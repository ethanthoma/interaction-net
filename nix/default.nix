{ pkgs
, odin
,
}:
pkgs.stdenv.mkDerivation
rec {
  pname = "inio";
  version = "0.1";
  src = ../src;

  nativeBuildInputs = [ odin ];

  buildPhase = ''
    odin build $src -show-timings -out:${pname} -microarch:native -no-bounds-check -o:speed
    mkdir -p $out/bin
    mv ${pname} $out/bin/
  '';

  doCheck = true;

  checkPhase = ''
    odin test $src
  '';

  meta = with pkgs.lib;
    {
      description = "Interaction Net compiler and runtime in Odin";
      platforms = platforms.all;
    };
}
