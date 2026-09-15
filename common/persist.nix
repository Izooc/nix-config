{ config, lib, pkgs, ... }:

{
  environment.persistence."/persist" = {
    directories = [
      "/etc/nixos"
      "/etc/NetworkManager/system-connections"
      "/var/lib/NetworkManager"
      "/var/lib/sbctl"
      "/var/db/sudo"
      "/var/lib/nixos"
      "/var/lib/flatpak"
      "/var/lib/bluetooth"
      "/var/lib/nixos-containers"
      "/var/lib/libvirt"
    ];

    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}
