{
  imports = [ ./common.nix ];

  networking.hostName = "example-nixos-system";

  users.users.hello = {
    isNormalUser = true;
    password = "";
    uid = 1010;
  };
}
