{
  lib,
  callPackage,
  symlinkJoin,
  makeDesktopItem,
  wineWow64Packages,
  winePackage ? wineWow64Packages.stagingFull,
}:

let
  wine = winePackage;
  common = callPackage ./common.nix { inherit wine; };
  installer = callPackage ./install.nix { inherit common wine; };
  launcher = callPackage ./inventor.nix { inherit common installer wine; };
  desktop = makeDesktopItem {
    name = "inventor";
    desktopName = "Autodesk Inventor (experimental)";
    comment = "Mechanical CAD through Wine; compatibility not yet established";
    exec = "${launcher}/bin/inventor run %F";
    icon = "applications-engineering";
    categories = [
      "Graphics"
      "Engineering"
    ];
    terminal = false;
  };
in
symlinkJoin {
  name = "inventor-0.1.0";
  paths = [
    launcher
    installer
    desktop
  ];
  passthru = {
    inherit
      wine
      common
      installer
      launcher
      ;
  };
  meta = {
    description = "Experimental Autodesk Inventor installer and launcher with a pinned Wine environment";
    homepage = "https://github.com/lukasl-dev/inventor.nix";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "inventor";
  };
}
