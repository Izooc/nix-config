{ config, pkgs, lib, ... }:

let
  containerName = "game-sandbox";
  hostIP = "172.30.0.1";
  guestIP = "172.30.0.2";
  hostUser = "isaac";
  hostUid = 1000;
  containerUser = "gaming";
  containerUid = 1000;
  
  privateUsersBase = 524288;
  containerMappedUid = privateUsersBase + containerUid;

  launchIsolatedGaming = pkgs.writeShellScriptBin "launch-isolated-gaming" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    CONTAINER="${containerName}"
    APP="''${1:-steam}"
    
    case "$APP" in
      steam|heroic|wivrn|wivrn-dashboard|alvr|alvr_dashboard|lsfg-vk-ui|prismlauncher) ;;
      *) echo "Error: Unauthorized application '$APP'"; exit 1 ;;
    esac

    echo "Starting container..."
    ${pkgs.systemd}/bin/systemctl start "container@$CONTAINER"

    echo "Launching $APP..."
    ${pkgs.systemd}/bin/machinectl shell --uid=${containerUser} "$CONTAINER" /bin/sh -lc "exec systemd-run --user --scope --collect /bin/sh -lc \"$APP\""
  '';
in
{
  boot.kernelModules = [ "uinput" "snd-aloop" ];
  boot.extraModprobeConfig = ''
    options snd-aloop index=31 pcm_substreams=2 id=GamingLoop
  '';

  security.rtkit.enable = true;
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_JOYSTICK}=="1", \
      RUN+="${pkgs.coreutils}/bin/cp -a $env{DEVNAME} /dev/gaming_input/%k", \
      RUN+="${pkgs.coreutils}/bin/chown ${toString containerMappedUid}:root /dev/gaming_input/%k"

    ACTION=="add", SUBSYSTEM=="hidraw", KERNELS=="*054C:*|*045E:*|*057E:*", \
      RUN+="${pkgs.coreutils}/bin/cp -a $env{DEVNAME} /dev/gaming_input/%k", \
      RUN+="${pkgs.coreutils}/bin/chown ${toString containerMappedUid}:root /dev/gaming_input/%k"

    ACTION=="remove", SUBSYSTEM=="input", KERNEL=="event*", RUN+="${pkgs.coreutils}/bin/rm -f /dev/gaming_input/%k"
    ACTION=="remove", SUBSYSTEM=="hidraw", KERNEL=="hidraw*", RUN+="${pkgs.coreutils}/bin/rm -f /dev/gaming_input/%k"

    SUBSYSTEM=="drm",  KERNEL=="renderD*", RUN+="${pkgs.acl}/bin/setfacl -m u:${toString containerMappedUid}:rw %N"
    SUBSYSTEM=="drm",  KERNEL=="card*",    RUN+="${pkgs.acl}/bin/setfacl -m u:${toString containerMappedUid}:rw %N"
    SUBSYSTEM=="misc", KERNEL=="uinput",   RUN+="${pkgs.acl}/bin/setfacl -m u:${toString containerMappedUid}:rw %N"

    SUBSYSTEM=="sound", KERNEL=="card31", ENV{ACP_IGNORE}="1", ENV{PULSE_IGNORE}="1", ENV{WIREPLUMBER_IGNORE}="1"
    SUBSYSTEM=="sound", KERNEL=="controlC31", ENV{ACP_IGNORE}="1", ENV{PULSE_IGNORE}="1", ENV{WIREPLUMBER_IGNORE}="1", RUN+="${pkgs.acl}/bin/setfacl -m u:${toString containerMappedUid}:rw %N"
    SUBSYSTEM=="sound", KERNEL=="pcmC31*", ENV{ACP_IGNORE}="1", ENV{PULSE_IGNORE}="1", ENV{WIREPLUMBER_IGNORE}="1", RUN+="${pkgs.acl}/bin/setfacl -m u:${toString containerMappedUid}:rw %N"
  '';

  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-+" ]; 
    externalInterface = "wlan0";
  };

  environment.systemPackages = with pkgs; [
    launchIsolatedGaming
    
    (makeDesktopItem {
      name = "Isolated Steam";
      desktopName = "Steam (Isolated)";
      exec = "sudo ${launchIsolatedGaming}/bin/launch-isolated-gaming steam";
      icon = "steam";
      terminal = false;
      categories = [ "Game" ];
    })
    (makeDesktopItem {
      name = "Isolated Heroic";
      desktopName = "Heroic Games Launcher (Isolated)";
      exec = "sudo ${launchIsolatedGaming}/bin/launch-isolated-gaming heroic";
      icon = "heroic";
      terminal = false;
      categories = [ "Game" ];
    })
    (makeDesktopItem {
      name = "Isolated WiVRn";
      desktopName = "WiVRn (Isolated)";
      exec = "sudo ${launchIsolatedGaming}/bin/launch-isolated-gaming wivrn-dashboard";
      icon = "wivrn";
      terminal = false;
      categories = [ "Game" ];
    })
    (makeDesktopItem {
      name = "Isolated ALVR";
      desktopName = "ALVR (Isolated)";
      exec = "sudo ${launchIsolatedGaming}/bin/launch-isolated-gaming alvr_dashboard";
      icon = "alvr";
      terminal = false;
      categories = [ "Game" ];
    })
    (makeDesktopItem {
      name = "Isolated PrismLauncher";
      desktopName = "PrismLauncher (Isolated)";
      exec = "sudo ${launchIsolatedGaming}/bin/launch-isolated-gaming prismlauncher";
      icon = "prismlauncher";
      terminal = false;
      categories = [ "Game" ];
    })
  ];

  security.sudo.extraRules = [{
    users = [ hostUser ];
    commands = [{ 
      command = "${launchIsolatedGaming}/bin/launch-isolated-gaming *";
      options = [ "NOPASSWD" ]; 
    }];
  }];

  systemd.services.gaming-container-renicer = {
    description = "Host-side renicer for gaming container processes";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "gaming-container-renicer" ''
        while true; do
          for cmd in "^gamescope" "^wivrn$"; do
            for pid in $(${pkgs.procps}/bin/pgrep -u ${toString containerMappedUid} "$cmd" 2>/dev/null); do
              ${pkgs.util-linux}/bin/renice -n -4 -p "$pid" >/dev/null 2>&1 || true
            done
          done
          
          for cmd in "^GameThread$"; do
            for pid in $(${pkgs.procps}/bin/pgrep -u ${toString containerMappedUid} "$cmd" 2>/dev/null); do
              ${pkgs.util-linux}/bin/renice -n -5 -p "$pid" >/dev/null 2>&1 || true
            done
          done

          for cmd in "^pipewire$" "^pipewire-pulse$" "^wireplumber$"; do
            for pid in $(${pkgs.procps}/bin/pgrep -u ${toString containerMappedUid} "$cmd" 2>/dev/null); do
              ${pkgs.util-linux}/bin/renice -n -11 -p "$pid" >/dev/null 2>&1 || true
            done
          done
          
          sleep 3
        done
      '';
      Restart = "always";
    };
  };

  services.pipewire = {
    enable = true;
    wireplumber.extraConfig."99-host-ignore-aloop" = {
      "monitor.alsa.rules" = [
        {
          matches = [{ "device.name" = "~alsa_card.*snd_aloop.*"; }];
          actions = { update-props = { "device.disabled" = true; }; };
        }
      ];
    };
    extraConfig.pipewire."99-host-low-latency" = {
      "context.properties" = { 
        "default.clock.rate" = 48000;
        "default.clock.allowed-rates" = [ 48000 ];
        "default.clock.quantum" = 512; 
        "default.clock.min-quantum" = 512;
        "default.clock.max-quantum" = 1024;
      };
    };
  };

  home-manager.users.${hostUser} = {
    home.stateVersion = "25.05";

    xdg.configFile."pipewire/pipewire.conf.d/99-gaming-alsa-source.conf".text = ''
      context.objects = [
        {
          factory = adapter
          args = {
            factory.name           = api.alsa.pcm.source
            node.name              = "gaming_host_alsa_source"
            node.description       = "Gaming Container Source"
            media.class            = "Audio/Source"
            api.alsa.path          = "hw:31,0,0"
            api.alsa.disable-mmap  = true
            api.alsa.period-size   = 512
            api.alsa.headroom      = 1024
            audio.rate             = 48000
            audio.channels         = 2
            audio.format           = "S24LE"
            audio.position         = "FL,FR"
          }
        }
      ]
    '';

    xdg.configFile."pipewire/pipewire.conf.d/99-gaming-loopback.conf".text = ''
      context.modules = [
        {
          name = libpipewire-module-loopback
          args = {
            node.description = "Gaming Container Audio Bridge"
            capture.props = {
              target.object = "gaming_host_alsa_source"
            }
            playback.props = {
              media.class  = "Stream/Output/Audio"
              media.role   = "Game"
            }
          }
        }
      ]
    '';

    xdg.configFile."pipewire/pipewire.conf.d/99-gaming-alsa-sink.conf".text = ''
      context.objects = [
        {
          factory = adapter
          args = {
            factory.name           = api.alsa.pcm.sink
            node.name              = "gaming_host_alsa_sink"
            node.description       = "Gaming Container Mic Input"
            media.class            = "Audio/Sink"
            api.alsa.path          = "hw:31,0,1"
            api.alsa.disable-mmap  = true
            api.alsa.period-size   = 512
            api.alsa.headroom      = 1024
            audio.rate             = 48000
            audio.channels         = 2
            audio.format           = "S24LE"
            audio.position         = "FL,FR"
          }
        }
      ]
    '';

    xdg.configFile."pipewire/pipewire.conf.d/99-gaming-mic-loopback.conf".text = ''
      context.modules = [
        {
          name = libpipewire-module-loopback
          args = {
            node.description = "Gaming Container Mic Bridge"
            capture.props = {
              media.class = "Stream/Input/Audio"
            }
            playback.props = {
              target.object = "gaming_host_alsa_sink"
            }
          }
        }
      ]
    '';
  };

  systemd.services."container@${containerName}" = {
    serviceConfig.DeviceAllow = [ "char-input rwm" "char-hidraw rwm" ];
    preStart = ''
      mkdir -p /dev/gaming_input
    '';
  };

  containers.${containerName} = {
    autoStart = false;
    privateNetwork = true;
    
    hostAddress = hostIP;
    localAddress = guestIP;
    
    macvlans = [ "enp34s0" ];

    allowedDevices = [
      { node = "/dev/dri/renderD128"; modifier = "rw"; }
      { node = "/dev/dri/card1"; modifier = "rw"; }
      { node = "/dev/uinput"; modifier = "rw"; }
      { node = "/dev/snd/controlC31"; modifier = "rw"; }
      { node = "/dev/snd/pcmC31D1p"; modifier = "rw"; }
      { node = "/dev/snd/pcmC31D1c"; modifier = "rw"; }
    ];

    extraFlags = [
      "--private-users=${toString privateUsersBase}:65536"
      "--private-users-ownership=map"
      
      "--bind=/run/opengl-driver:/run/opengl-driver"
      "--bind=/run/opengl-driver-32:/run/opengl-driver-32"
      "--bind=/dev/dri:/dev/dri"
      "--bind=/run/user/${toString hostUid}/wayland-0:/tmp/wayland-host-0:idmap"
      
      "--bind=/dev/gaming_input:/dev/gaming_input"
      "--bind=/dev/gaming_input:/dev/input"
      
      "--bind=/dev/uinput:/dev/uinput"
      "--bind=/dev/snd/controlC31:/dev/snd/controlC31"
      "--bind=/dev/snd/pcmC31D1p:/dev/snd/pcmC31D1p"
      "--bind=/dev/snd/pcmC31D1c:/dev/snd/pcmC31D1c"
      
      "--bind=/persist/mnt/3tb/Games:/home/gaming/3tb/:idmap"
      "--bind=/persist/mnt/crucial/Games:/home/gaming/crucial/:idmap"
      "--bind=/persist/mnt/patriot/Games:/home/gaming/patriot/:idmap"
      "--bind=/home/isaac/Containers/gameSandbox/Home/:/home/gaming/:idmap"
      
      "--bind-ro=/etc/gamesandbox-machine-id:/etc/machine-id"
    ];

    config = { config, pkgs, lib, ... }: {
      system.stateVersion = "25.05";
      networking.useHostResolvConf = true;
      boot.kernel.sysctl = {
        "net.core.default_qdisc" = "fq_codel";
      };
      networking.interfaces."mv-enp34s0".useDHCP = true;

      networking.firewall.interfaces."mv-enp34s0".allowedTCPPortRanges = [ { from = 1; to = 65535; } ];
      networking.firewall.interfaces."mv-enp34s0".allowedUDPPortRanges = [ { from = 1; to = 65535; } ];

      i18n.defaultLocale = "en_GB.UTF-8";
      i18n.supportedLocales = [ "en_GB.UTF-8/UTF-8" ];

      hardware.graphics.enable = true;
      hardware.graphics.enable32Bit = true;
      
      security.rtkit.enable = false;

      users.users.${containerUser} = {
        isNormalUser = true;
        uid = containerUid;
        extraGroups = [ "video" "render" "audio" "input" ];
        linger = true; 
      };

      nixpkgs.config.allowUnfree = true;

      programs.steam = {
        enable = true;
        extest.enable = true; 
        remotePlay.openFirewall = true; 
	extraPackages = with pkgs; [
    	  xwayland
        ];
      };

      programs.alvr = {
        enable = true;
        openFirewall = true;
      };

      services.wivrn = {
        enable = true;
        openFirewall = true;
        highPriority = true; 
      };

      environment.systemPackages = with pkgs; [ 
        xwayland-satellite heroic inotify-tools lsfg-vk lsfg-vk-ui vulkan-tools prismlauncher
      ];

      programs.gamescope = {
        enable = true;
        package = pkgs.gamescope.overrideAttrs (_: {
          NIX_CFLAGS_COMPILE = ["-fno-fast-math"];
        });
      };

      systemd.services.controller-linker = {
        description = "Hotplug Controller Linker (Hidraw Only)";
        wantedBy = [ "multi-user.target" ];
        
        path = with pkgs; [ coreutils inotify-tools findutils ]; 
        serviceConfig = { Type = "simple"; Restart = "always"; };
        script = ''
          find /dev -maxdepth 1 -name "hidraw*" -type l ! -exec test -e {} \; -delete || true
          
          link_devs() {
            for dev in /dev/gaming_input/hidraw*; do
              [ -e "$dev" ] || continue
              base=$(basename "$dev")
              ln -sf "$dev" "/dev/$base"
            done
          }
          link_devs
          
          inotifywait -m -e create,delete,moved_to /dev/gaming_input | while read -r dir action file; do 
            if [[ "$action" == *"CREATE"* ]] || [[ "$action" == *"MOVED_TO"* ]]; then
              sleep 0.1 
              case "$file" in
                hidraw*) ln -sf "/dev/gaming_input/$file" "/dev/$file" ;;
              esac
            elif [[ "$action" == *"DELETE"* ]]; then
              case "$file" in
                hidraw*) rm -f "/dev/$file" ;;
              esac
            fi
          done
        '';
      };

      systemd.services.xwayland-satellite = {
        description = "Xwayland for container apps";
        wantedBy = [ "multi-user.target" ];
        after = [ "user@${toString containerUid}.service" ];
        requires = [ "user@${toString containerUid}.service" ];
        environment = { 
          WAYLAND_DISPLAY = "wayland-0";
          XDG_RUNTIME_DIR = "/run/user/${toString containerUid}";
          WLR_DRM_DEVICES = "/dev/dri/card1";
        };
        serviceConfig = {
          User = containerUser;
          ExecStartPre = [
            "+${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/mkdir -p /run/user/${toString containerUid} && ${pkgs.coreutils}/bin/touch /run/user/${toString containerUid}/wayland-0 && ${pkgs.util-linux}/bin/mountpoint -q /run/user/${toString containerUid}/wayland-0 || ${pkgs.util-linux}/bin/mount --bind /tmp/wayland-host-0 /run/user/${toString containerUid}/wayland-0'"
          ];
          ExecStart = "${pkgs.xwayland-satellite}/bin/xwayland-satellite :0";
          Restart = "on-failure";
        };
      };

      services.pipewire = {
        enable = true;
        pulse.enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        
        extraConfig.pipewire."99-container-low-latency" = {
          "context.properties" = { 
            "default.clock.rate" = 48000;
            "default.clock.allowed-rates" = [ 48000 ];
            "default.clock.quantum" = 512; 
            "default.clock.min-quantum" = 512;
            "default.clock.max-quantum" = 1024;
          };
        };
        
        extraConfig.pipewire."99-gaming-alsa-sink" = {
          "context.objects" = [{
            factory = "adapter";
            args = {
              "factory.name" = "api.alsa.pcm.sink";
              "node.name" = "gaming_alsa_sink";
              "node.description" = "Gaming Container Sink";
              "media.class" = "Audio/Sink";
              "api.alsa.path" = "hw:31,1,0";
              "api.alsa.disable-mmap" = true;
              "api.alsa.period-size" = 512;
              "api.alsa.headroom" = 1024;
              "audio.rate" = 48000;
              "audio.channels" = 2;
              "audio.format" = "S24LE";
              "audio.position" = "FL,FR";
            };
          }];
        };
        
        extraConfig.pipewire."99-gaming-alsa-source" = {
          "context.objects" = [{
            factory = "adapter";
            args = {
              "factory.name" = "api.alsa.pcm.source";
              "node.name" = "gaming_alsa_source";
              "node.description" = "Gaming Container Microphone";
              "media.class" = "Audio/Source";
              "api.alsa.path" = "hw:31,1,1";
              "api.alsa.disable-mmap" = true;
              "api.alsa.period-size" = 512;
              "api.alsa.headroom" = 1024;
              "audio.rate" = 48000;
              "audio.channels" = 2;
              "audio.format" = "S24LE";
              "audio.position" = "FL,FR";
            };
          }];
        };

        wireplumber.extraConfig."99-ignore-aloop" = {
          "monitor.alsa.rules" = [
            {
              matches = [ { "device.name" = "~alsa_card.*"; } ];
              actions = { update-props = { "device.disabled" = true; }; };
            }
          ];
        };
      };

      environment.variables = { 
        WAYLAND_DISPLAY = "wayland-0"; 
        XDG_RUNTIME_DIR = "/run/user/${toString containerUid}";
        DISPLAY = ":0";
      };
    };
  };
}
