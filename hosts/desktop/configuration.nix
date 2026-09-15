{ config, pkgs, lib, ... }:

{
  networking.hostName = "isaac-dining-desktop";

  boot.kernelParams = ["zswap.enabled=0"];
  boot.kernelModules = ["ntsync"];

  hardware.amdgpu.overdrive.enable = true;
  services.lact.enable = true;

  hardware.graphics.enable32Bit = true;

  hardware.enableRedistributableFirmware = true;
  boot.extraModprobeConfig = ''
    options mt7925e disable_aspm=y
  '';
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "vm.swappiness" = 10;
  };

  networking.networkmanager.wifi.backend = "iwd";
  networking.networkmanager.wifi.powersave = false;
  networking.networkmanager.wifi.macAddress = "preserve";

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="wl*", RUN+="${pkgs.iw}/bin/iw dev $name set power_save off"
  '';

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        ControllerMode = "dual";
        Experimental = true;
        FastConnectable = true;
      };
    };
    input = {
      General = {
        UserspaceHID = false;
      };
    };
  };

  services.displayManager.sddm.enable = true;
  services.printing.enable = true;

  users.users.isaac.extraGroups = [ "adbusers" ];

  hardware.uinput.enable = true;

  environment.systemPackages = with pkgs; [
    iw
  ];

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/iwd"
      "/etc/lact"
    ];
    files = [
      "/etc/gamesandbox-machine-id"
    ];
  };
}
