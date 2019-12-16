{ pkgs ? import <nixpkgs> {} }:

rec {
  disko = pkgs.callPackage ./lib {
    path = toString ./.;
  };

  install = pkgs.callPackage ./lib/default.nix {
    inherit disko;
  };

}
