{ stdenv
# build deps
, meson
, ninja
, asciidoc
, docbook_xsl
, libxslt
, cmocka
, pkgconfig
, fetchFromGitHub
# runtime deps
, inih
, pango
, libxkbcommon
, icu
# backends
, freeimage
, libtiff
, libpng
, librsvg
, netsurf
, libheif
# window system
, x11Support ? true
  , libGLU ? null
, waylandSupport ? true
  , wayland ? null
}:

assert x11Support -> libGLU != null;
assert waylandSupport -> wayland != null;

let
  lib = stdenv.lib;

  windowSystem =
       if  x11Support &&  waylandSupport then "all"
  else if  x11Support && !waylandSupport then "x11"
  else if !x11Support &&  waylandSupport then "wayland"
  else throw ''
    Support for at least one window system (X11 or wayland)
    must be enabled.
  '';

in stdenv.mkDerivation rec {
  pname = "imv";
  version = "4.2.0";

  src = fetchFromGitHub {
    owner = "eXeC64";
    repo = "imv";
    rev = "v${version}";
    sha256 = "07pcpppmfvvj0czfvp1cyq03ha0jdj4whl13lzvw37q3vpxs5qqh";
  };

  nativeBuildInputs = [
    meson
    ninja
    asciidoc
    docbook_xsl
    libxslt
    cmocka
    pkgconfig
  ];

  mesonFlags = [ "-Dwindows=${windowSystem}" ];

  buildInputs = [
    inih
    pango
    libxkbcommon
    icu
    # backends
    freeimage
    libtiff
    libpng
    librsvg
    libheif
    netsurf.libnsgif
  ]
  ++ lib.optionals x11Support [ libGLU ]
  ++ lib.optionals waylandSupport [ wayland ];

  # The `bin/imv` script assumes imv-wayland or imv-x11 in PATH,
  # so we have to fix those to the binaries we installed into the /nix/store
  postFixup = lib.optionalString (windowSystem == "all") ''
    sed -i "s|\bimv-wayland\b|$out/bin/imv-wayland|" $out/bin/imv
    sed -i "s|\bimv-x11\b|$out/bin/imv-x11|" $out/bin/imv
  '';

  doCheck = true;

  meta = with lib; {
    description = "A command line image viewer for tiling window managers";
    homepage = "https://github.com/eXeC64/imv";
    license = licenses.gpl2;
    maintainers = with maintainers; [ rnhmjoj markus1189 ];
    platforms = platforms.all;
  };
}
