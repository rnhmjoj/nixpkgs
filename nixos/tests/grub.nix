import ./make-test-python.nix ({ pkgs, ... }: {
  name = "grub";

  meta = with pkgs.stdenv.lib.maintainers; {
    maintainers = [ rnhmjoj ];
  };

  machine = { lib, ... }: {
    virtualisation.useBootLoader = true;

    boot.loader.timeout = null;
    boot.loader.grub = {
      enable = true;
      users.alice.password = "supersecret";

      # OCR is not accurate enough
      extraConfig = "serial; terminal_output serial";
    };
  };

  testScript = ''
    machine.start()

    # wait for grub screen
    machine.wait_for_console_text("GNU GRUB")

    # select "All configurations" to trigger login request
    machine.send_monitor_command("sendkey down")
    machine.send_monitor_command("sendkey ret")

    with subtest("Invalid credentials are rejected"):
        machine.wait_for_console_text("Enter username:")
        machine.send_chars("wronguser\n")
        machine.wait_for_console_text("Enter password:")
        machine.send_chars("wrongsecret\n")
        machine.wait_for_console_text("error: access denied.")

    # select "All configurations", again
    machine.send_monitor_command("sendkey down")
    machine.send_monitor_command("sendkey ret")

    with subtest("Valid credentials are accepted"):
        machine.wait_for_console_text("Enter username:")
        machine.send_chars("alice\n")
        machine.wait_for_console_text("Enter password:")
        machine.send_chars("supersecret\n\n")
        machine.wait_for_console_text("Linux version")

    with subtest("Machine boots correctly"):
        machine.wait_for_unit("multi-user.target")
  '';
})
