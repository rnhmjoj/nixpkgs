# This is a simple distributed test involving a topology with two separate
# virtual networks - the "inside" and the "outside" - with a client and a
# server on the inside network, a server on the outside network, and a router
# connected to both that performs Network Address Translation for the client.
import ./make-test-python.nix
  ({ pkgs, lib, withFirewall ? false, withConntrackHelpers ? false, ... }:
  let
    unit = if withFirewall then "firewall" else "nat";

    getAddr = node: ifname: (pkgs.lib.head
      node.config.networking.interfaces.${ifname}.ipv4.addresses).address;

    routerBase =
      lib.mkMerge [
        { virtualisation.vlans = [ 2 1 ];
          networking.firewall.enable = withFirewall;
          networking.nat.internalIPs = [ "192.168.1.0/24" ];
          networking.nat.externalInterface = "eth1";
          networking.nat.forwardPorts = lib.singleton
            { destination = "192.168.1.2:80";
              loopbackIPs = [ "192.168.2.3" ];
              proto = "tcp"; sourcePort = 80;
            };
        }
        (lib.optionalAttrs withConntrackHelpers {
          networking.firewall.connectionTrackingModules = [ "ftp" ];
          networking.firewall.autoLoadConntrackHelpers = true;
        })
      ];
  in
  {
    name = "nat" + (if withFirewall then "WithFirewall" else "Standalone")
                 + (lib.optionalString withConntrackHelpers "withConntrackHelpers");
    meta = with pkgs.stdenv.lib.maintainers; {
      maintainers = [ eelco rob ];
    };

    nodes =
      { client =
          { pkgs, nodes, ... }:
          lib.mkMerge [
            { virtualisation.vlans = [ 1 ];
              networking.defaultGateway = getAddr nodes.router "eth2";
            }
            (lib.optionalAttrs withConntrackHelpers {
              networking.firewall.connectionTrackingModules = [ "ftp" ];
              networking.firewall.autoLoadConntrackHelpers = true;
            })
          ];

        router =
        { ... }: lib.mkMerge [
          routerBase
          { networking.nat.enable = true; }
        ];

        routerDummyNoNat =
        { ... }: lib.mkMerge [
          routerBase
          { networking.nat.enable = false; }
        ];

        server =
          { ... }:
          { virtualisation.vlans = [ 2 ];
            networking.firewall.enable = false;
            services.httpd.enable = true;
            services.httpd.adminAddr = "foo@example.org";
            services.vsftpd.enable = true;
            services.vsftpd.anonymousUser = true;
          };

        insideServer =
          { nodes, ... }:
          { virtualisation.vlans = [ 1 ];
            networking.defaultGateway = getAddr nodes.router "eth2";
            networking.firewall.enable = false;
            services.nginx.enable = true;
            services.nginx.virtualHosts.router = {
              locations."/".extraConfig = "return 200 $remote_addr;";
            };
          };
      };

    testScript =
      { nodes, ... }: let
        routerDummyNoNatClosure =
          nodes.routerDummyNoNat.config.system.build.toplevel;
        routerClosure = nodes.router.config.system.build.toplevel;
      in ''
        client.start()
        router.start()
        server.start()
        insideServer.start()

        with subtest("The router should have access to the server."):
            server.wait_for_unit("network.target")
            server.wait_for_unit("httpd")
            router.wait_for_unit("network.target")
            router.succeed("curl --fail http://server/ >&2")

        with subtest("The client should be also able to connect via the NAT router."):
            router.wait_for_unit("${unit}")
            client.wait_for_unit("network.target")
            client.succeed("curl --fail http://server/ >&2")
            client.succeed("ping -c 1 server >&2")

        with subtest("Passive FTP works."):
            server.wait_for_unit("vsftpd")
            server.succeed("echo Hello World > /home/ftp/foo.txt")
            client.succeed("curl -v ftp://server/foo.txt >&2")

        with subtest("Test whether active FTP works."):
            client.${if withConntrackHelpers
                       then "succeed"
                       else "fail"}("curl -v -P - ftp://server/foo.txt >&2")

        with subtest("ICMP works."):
            client.succeed("ping -c 1 router >&2")
            router.succeed("ping -c 1 client >&2")

        with subtest("If we turn off NAT, the client shouldn't be able to reach the server."):
            router.succeed(
                "${routerDummyNoNatClosure}/bin/switch-to-configuration test 2>&1"
            )
            client.fail("curl --fail --connect-timeout 5 http://server/ >&2")
            client.fail("ping -c 1 server >&2")

        with subtest("Make sure that reloading the NAT job works."):
            router.succeed(
                "${routerClosure}/bin/switch-to-configuration test 2>&1"
            )
            # FIXME: this should not be necessary, but nat.service is not
            # started because network.target is not triggered. See:
            # (https://github.com/NixOS/nixpkgs/issues/16230#issuecomment-226408359)
            ${if (!withFirewall)
                then ''router.succeed("systemctl start nat.service")''
                else "pass"}
            client.succeed("curl --fail http://server/ >&2")
            client.succeed("ping -c 1 server >&2")

        with subtest("Port forwarding: the server can access the inside server"):
            insideServer.wait_for_unit("network.target")
            insideServer.wait_for_unit("nginx")
            server.wait_for_unit("network.target")
            remote_addr = server.succeed("curl --fail http://router/")

            assert (
                remote_addr == "${getAddr nodes.server "eth1"}"
            ), f"""
            The IP address seen by the inside server ($remote_addr) does
            not match the real server address.

            router address: ${getAddr nodes.router "eth1"}
            server address: ${getAddr nodes.server "eth1"}
            $remote_addr: {remote_addr}
            """

        with subtest("Loopback: the client can access the inside server"):
            insideServer.wait_for_unit("network.target")
            insideServer.wait_for_unit("nginx")
            client.wait_for_unit("network.target")
            remote_addr = client.succeed("curl --fail http://router/")

            assert (
                remote_addr == "${getAddr nodes.client "eth1"}"
            ), f"""
            The IP address seen by the inside server ($remote_addr) does
            not match the real client address.

            router address: ${getAddr nodes.router "eth1"}
            client address: ${getAddr nodes.client "eth1"}
            $remote_addr: {remote_addr}
            """
      '';
  })
