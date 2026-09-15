{ config, pkgs, lib, ... }:

{
  networking.hostName = "isaac-laptop";

  boot.plymouth.enable = true;
  boot.consoleLogLevel = 0;
  boot.kernelParams = [
    "quiet" "udev.log_level=3"
    "i915.force_probe=!9a49" "xe.force_probe=9a49"
  ];
  boot.resumeDevice = "/dev/mapper/optane";
  boot.initrd.systemd.enable = true;

  services.fwupd.enable = true;
  services.thermald.enable = true;

  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
  ];
  environment.sessionVariables = { LIBVA_DRIVER_NAME = "iHD"; };

  services.logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "1h";
  };

  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  virtualisation.libvirtd.qemu.swtpm.enable = true;

  systemd.services.modem-manager.enable = false;

  hardware.bluetooth.settings = {
    General = {
      Experimental = true;
    };
  };

  services.displayManager.plasma-login-manager.enable = true;

  services.printing = {
    enable = true;
    cups-pdf.enable = true;
    drivers = with pkgs; [
      cups-filters
      cups-browsed
    ];
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  users.users.isaac.extraGroups = [ "libvirtd" ];

  environment.systemPackages = with pkgs; [
    vim
    kdePackages.kcharselect
  ];

  environment.persistence."/persist" = {
    directories = [
      "/etc/nixos-containers"
    ];
  };
}
