{ lib, stdenv, fetchFromGitHub, fetchpatch, libcap, libev, libconfig, perl, tcp_wrappers, pcre2, nixosTests }:

stdenv.mkDerivation rec {
  pname = "sslh";
  version = "2.0-rc2";

  src = fetchFromGitHub {
    owner = "yrutschle";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-i9M9R7j8yk23/AaARDdEmwM+WpNsnnyexzKNOAZNFjA=";
  };

  patches = [
    # Fix IPv6 UDP connections
    (fetchpatch {
      url  = "https://github.com/yrutschle/sslh/pull/401.patch";
      hash = "sha256-ic1m98s7P0bejx1n5tvuoeoqCWtovjpvws8jRUppAfw=";
     })
  ];

  postPatch = "patchShebangs *.sh";

  buildInputs = [ libcap libev libconfig perl tcp_wrappers pcre2 ];

  makeFlags = [ "USELIBCAP=1" "USELIBWRAP=1" ];

  postInstall = ''
    # install all flavours
    install -p sslh-fork "$out/sbin/sslh-fork"
    install -p sslh-select "$out/sbin/sslh-select"
    install -p sslh-ev "$out/sbin/sslh-ev"
    ln -sf sslh-fork "$out/sbin/sslh"
  '';

  installFlags = [ "PREFIX=$(out)" ];

  hardeningDisable = [ "format" ];

  passthru.tests = {
    inherit (nixosTests) sslh;
  };

  meta = with lib; {
    description = "Applicative Protocol Multiplexer (e.g. share SSH and HTTPS on the same port)";
    license = licenses.gpl2Plus;
    homepage = "https://www.rutschle.net/tech/sslh/README.html";
    maintainers = with maintainers; [ koral fpletz ];
    platforms = platforms.all;
  };
}
