{ config, pkgs, lib, ... }:

let
  containerName = "dev-sandbox";
  hostIP = "10.0.1.1";
  guestIP = "10.0.1.2";

  hostUser = "isaac";
  hostUid = 1000;

  containerUser = "dev";
  containerUid = 1000;

  privateUsersBase = 589824;
  privateUsersSize = 65536;
  containerMappedUid = privateUsersBase + containerUid;

  launchIsolatedDev = pkgs.writeShellScriptBin "launch-isolated-dev" ''
    #!/usr/bin/env bash
    set -euo pipefail

    CONTAINER="${containerName}"
    APP="''${1:-pycharm}"

    case "$APP" in
      pycharm) ;;
      *)
        echo "Error: Unauthorized application '$APP'"
        exit 1
        ;;
    esac

    echo "Starting container..."
    ${pkgs.systemd}/bin/systemctl start "container@$CONTAINER"

    echo "Launching $APP..."
    ${pkgs.systemd}/bin/machinectl shell --uid=${containerUser} "$CONTAINER" /bin/sh -lc "XDG_RUNTIME_DIR=/run/user/${toString containerUid} exec systemd-run --user --scope --collect /bin/sh -lc \"XDG_RUNTIME_DIR=/tmp exec $APP\""
  '';
in
{
  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-+" ];
    externalInterface = "wlan0";
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="renderD*", RUN+="${pkgs.acl}/bin/setfacl -m u:${toString containerMappedUid}:rw %N"
    SUBSYSTEM=="drm", KERNEL=="card*",    RUN+="${pkgs.acl}/bin/setfacl -m u:${toString containerMappedUid}:rw %N"
  '';

  environment.systemPackages = with pkgs; [
    launchIsolatedDev

    (makeDesktopItem {
      name = "Isolated PyCharm";
      desktopName = "PyCharm (Isolated)";
      exec = "sudo ${launchIsolatedDev}/bin/launch-isolated-dev pycharm";
      icon = "pycharm";
      terminal = false;
      categories = [ "Development" ];
    })
  ];

  security.sudo.extraRules = [{
    users = [ hostUser ];
    commands = [{
      command = "${launchIsolatedDev}/bin/launch-isolated-dev *";
      options = [ "NOPASSWD" ];
    }];
  }];

  containers.${containerName} = {
    autoStart = false;
    privateNetwork = true;

    hostAddress = hostIP;
    localAddress = guestIP;

    allowedDevices = [
      { node = "/dev/dri/renderD128"; modifier = "rw"; }
      { node = "/dev/dri/card0"; modifier = "rw"; }
      { node = "/dev/dri/card1"; modifier = "rw"; }
    ];

    extraFlags = [
      "--private-users=${toString privateUsersBase}:${toString privateUsersSize}"
      "--private-users-ownership=map"

      "--system-call-filter=~@clock,@module,@reboot,@swap"

      "--bind=/dev/dri"
      "--bind=/run/opengl-driver:/run/opengl-driver"
      "--bind=/run/user/${toString hostUid}/wayland-0:/tmp/wayland-0:idmap"

      "--bind=/home/isaac/Projects:/home/dev/PycharmProjects:idmap"

      "--bind=/home/isaac/Containers/devSandbox/Home:/home/dev:idmap"
    ];

    config = { config, pkgs, lib, ... }: {
      system.stateVersion = "26.05";

      networking.defaultGateway = hostIP;
      networking.useHostResolvConf = true;

      hardware.graphics.enable = true;

      users.users.${containerUser} = {
        isNormalUser = true;
        uid = containerUid;
        group = "users";
        extraGroups = [ "video" "render" ];
        linger = true;
      };

      nixpkgs.config.allowUnfreePredicate = pkg:
        builtins.elem (lib.getName pkg) [ "pycharm" ];

      fonts.enableDefaultPackages = true;
      fonts.packages = with pkgs; [
        noto-fonts
        jetbrains-mono
      ];

      environment.systemPackages = with pkgs; [
        (jetbrains.pycharm.override {
          vmopts = ''
            -Dawt.toolkit.name=WLToolkit
            -Dsun.java2d.vulkan=True
            -Dsun.java2d.vulkan.accelsd=true
            -Dsun.java2d.vulkan.deviceNumber=0
	    -Dsun.java2d.opengl=true
          '';
        })

        wayland-utils
        git
        busybox

        glmark2
        mesa-demos

        kdePackages.breeze-icons
        kdePackages.breeze-gtk
        kdePackages.breeze

        (python3.withPackages (ps: with ps; [
          pip
          virtualenv
        ]))

        librsvg
        shared-mime-info

        vulkan-loader
        vulkan-tools
        vulkan-validation-layers

        dig
      ];

      environment.sessionVariables = {
        WAYLAND_DISPLAY = "wayland-0";
        XDG_RUNTIME_DIR = "/tmp";

        NIXOS_OZONE_WL = "1";

        XCURSOR_THEME = "breeze_cursors";
        XCURSOR_SIZE = "24";

        GTK_THEME = "Breeze-Dark";
        GDK_PIXBUF_MODULE_FILE =
          "${pkgs.librsvg.out}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache";

        LD_LIBRARY_PATH = "${pkgs.vulkan-loader}/lib";
      };
    };
  };
}
