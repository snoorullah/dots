# hypr-kdeconnect-fix (github:gfhdhytghd/hypr-kdeconnect-fix): user-level xdg-desktop-portal RemoteDesktop backend
# for KDE Connect / Deskflow on Hyprland. Built per its README "Dependencies" + "Build" (cmake, Qt6 Core/DBus,
# wayland-client + scanner, xkbcommon, libeis; libei for tests). The portal routing is chezmoi's portals.conf.
{ lib, stdenv, fetchFromGitHub, cmake, pkg-config, wayland-scanner, wayland, libxkbcommon, libei, kdePackages }:
stdenv.mkDerivation {
  pname = "hypr-kdeconnect-fix";
  version = "unstable-5fc9594";
  src = fetchFromGitHub {
    owner = "gfhdhytghd"; repo = "hypr-kdeconnect-fix";
    rev = "5fc959475177197f0aa953fcc42a3742e6648671";
    sha256 = "14rxy1ynac8l9n2zh86igjchjkifxib1ycq27hygqpn9q18gw5my";
  };
  nativeBuildInputs = [ cmake pkg-config wayland-scanner kdePackages.wrapQtAppsHook ];
  buildInputs = [ wayland libxkbcommon libei kdePackages.qtbase ];
  doCheck = true;
  preCheck = "export QT_QPA_PLATFORM=offscreen";
  meta = {
    homepage = "https://github.com/gfhdhytghd/hypr-kdeconnect-fix";
    description = "RemoteDesktop portal backend for KDE Connect and Deskflow on Hyprland";
    mainProgram = "hypr-kdeconnect-portal";
    platforms = lib.platforms.linux;
  };
}
