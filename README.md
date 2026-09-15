# NixOS Flake Configuration

Unified NixOS flake for my desktop and laptop, using an ephemeral root (impermanence) setup with BTRFS and LUKS full-disk encryption.

## Structure

```
├── flake.nix                         # Flake entry point, defines both host configurations
├── common/
│   ├── system.nix                    # Shared system config (boot, locale, audio, users, networking)
│   ├── home.nix                      # Shared home-manager config (bash, stateVersion)
│   ├── persist.nix                   # Impermanence: directories/files that survive reboot
│   ├── wipe.nix                      # Initrd service that rolls back BTRFS root to blank snapshot on boot
│   └── devcontainer.nix              # Isolated systemd-nspawn container for dev work (PyCharm)
├── hosts/
│   ├── desktop/
│   │   ├── configuration.nix         # Desktop host config (AMD GPU, Bluetooth, SDDM, WiFi tuning)
│   │   ├── hardware-configuration.nix # Auto-generated hardware config (AMD CPU, NVMe, BTRFS)
│   │   ├── drivemounts.nix           # LUKS-encrypted secondary drives (Patriot, Crucial, 3TB)
│   │   ├── gamingcontainer.nix       # Isolated gaming container (Steam, VR, gamescope)
│   │   └── home.nix                  # Desktop-specific home packages (Signal)
│   └── laptop/
│       ├── configuration.nix         # Laptop host config (Intel GPU, sleep/hibernate, libvirt, printing)
│       ├── hardware-configuration.nix # Auto-generated hardware config (Intel CPU, Thunderbolt, Optane)
│       └── home.nix                  # Laptop-specific home packages (LibreOffice, Anki)
```

## Hosts

- **isaac-dining-desktop** — AMD desktop with Lanzaboote (secure boot), secondary encrypted drives, and isolated gaming/development containers.
- **isaac-laptop** — Intel laptop with hibernate support, libvirt/QEMU, and CUPS printing.

## Isolated Containers

Both containers use `systemd-nspawn` via NixOS `containers.*` with private user namespaces, isolated networking, and GPU passthrough.

### Dev Container (`dev-sandbox`)

Defined in `common/devcontainer.nix`. Runs PyCharm in an isolated environment for untrusted or messy projects.

**How it works:**

1. A systemd-nspawn container is created with a private network (`10.0.1.1` ↔ `10.0.1.2`), NAT'd to the host via `wlan0`.
2. User namespaces remap the container user (`dev`, uid 1000) to a high host uid (`589824 + 1000`) for isolation.
3. GPU access is granted by bind-mounting `/dev/dri` and setting ACLs via udev rules on `renderD*` and `card*` devices.
4. The Wayland socket (`wayland-0`) is bind-mounted from the host user's runtime directory into the container with idmapped mount support.
5. Your project directory (`~/Projects`) is bind-mounted read-write into the container at `/home/dev/PycharmProjects`, and a persistent home is stored at `~/Containers/devSandbox/Home`.
6. The host script `launch-isolated-dev pycharm` starts the container and shells into it as the `dev` user, launching PyCharm with the `WLToolkit` and Vulkan rendering flags.

**Access from host:**

```bash
# Or via the desktop shortcut "PyCharm (Isolated)"
sudo launch-isolated-dev pycharm
```

Sudo is configured NOPASSWD for this script only, scoped to user `isaac`.

### Gaming Container (`game-sandbox`)

Defined in `hosts/desktop/gamingcontainer.nix`. Isolates gaming software (Steam, Heroic, WiVRn, ALVR, PrismLauncher) from the host.

**How it works:**

1. A systemd-nspawn container is created with a private network (`172.30.0.1` ↔ `172.30.0.2`) and a macvlan interface on `enp34s0` for LAN access (e.g. game servers, VR streaming).
2. User namespaces remap the `gaming` user (uid 1000) to host uid `524288 + 1000`.
3. GPU passthrough is the same as the dev container (`/dev/dri` bind + ACLs), plus 32-bit driver support for Steam/Proton.
4. A dedicated `snd-aloop` kernel module (index 31) creates a virtual ALSA loopback device. This is split between host and container:
   - **Host side**: PipeWire creates ALSA sink/source nodes on `hw:31` and routes them through loopback modules so game audio and mic input flow between the host's main audio stack and the container.
   - **Container side**: PipeWire exposes its own ALSA sink/source on `hw:31,1` so games see a normal audio device.
   - WirePlumber on the host ignores the loopback card to avoid conflicts.
5. Input device passthrough uses a udev-based approach:
   - Joystick/hidraw events are copied to `/dev/gaming_input/` and chowned to the container's mapped uid.
   - A `controller-linker` service watches `/dev/gaming_input` with `inotifywait` and symlinks hidraw devices into `/dev/` so they appear on the host too.
   - The container bind-mounts `/dev/gaming_input` as both itself and `/dev/input`.
6. A `gaming-container-renicer` host service continuously boosts priority (`nice -4` to `-11`) for gamescope, WiVRn, game threads, and PipeWire processes running under the container uid.
7. Game libraries from secondary drives (`/persist/mnt/3tb/Games`, `/persist/mnt/crucial/Games`, `/persist/mnt/patriot/Games`) are bind-mounted into the container. A persistent home is at `~/Containers/gameSandbox/Home/`.

**Access from host:**

```bash
# Or via desktop shortcuts: Steam (Isolated), Heroic (Isolated), WiVRn (Isolated), ALVR (Isolated)
sudo launch-isolated-gaming steam
sudo launch-isolated-gaming heroic
sudo launch-isolated-gaming wivrn-dashboard
sudo launch-isolated-gaming alvr_dashboard
sudo launch-isolated-gaming prismlauncher
```

### Security Model

- Both containers run with `--private-users` and `--system-call-filter` to restrict syscalls.
- The dev container blocks `@clock`, `@module`, `@reboot`, and `@swap` syscall groups.
- No container has direct access to host filesystems beyond explicitly bind-mounted paths.
- Sudo rules are scoped to specific scripts and users only.
