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

- **isaac-dining-desktop** AMD Gaming desktop with Lanzaboote (secure boot), secondary encrypted drives and a gaming container to limit scope from games.
- **isaac-laptop** Latitude 5420, general config for day to day use on KDE.

## Isolated Containers

Both containers use `systemd-nspawn` via NixOS `containers.*` with private user namespaces, isolated networking, and GPU passthrough.

### Dev Container (`dev-sandbox`)

Defined in `common/devcontainer.nix`. Runs PyCharm in an isolated environment for untrusted or messy projects.

**How it works:**

1. A systemd-nspawn container is created with a private network (`10.0.1.1` ↔ `10.0.1.2`), NAT'd to the host via `wlan0`.
2. User namespaces remap the container user (`dev`, uid 1000) to a high host uid (`589824 + 1000`) for isolation.
3. GPU access is granted by bind-mounting `/dev/dri` and setting ACLs via udev rules on `renderD*` and `card*` devices, this enables H/W acceleration on PyCharm.
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

1. A systemd-nspawn container is created with a private network (`172.30.0.1` ↔ `172.30.0.2`) and a macvlan interface on `enp34s0` for LAN access (e.g. game servers, VR streaming). The macvlan sits on a dedicated, VR-only network segment, the container never touches the main LAN through my wifi.
2. User namespaces remap the `gaming` user (uid 1000) to host uid `524288 + 1000`.
3. GPU passthrough is the same as the dev container (`/dev/dri` bind + ACLs), plus 32-bit driver support for Steam/Proton.
4. A dedicated `snd-aloop` kernel module (index 31) creates a virtual ALSA loopback device. This is split between host and container:
   - **Host side**: PipeWire creates ALSA sink/source nodes on `hw:31` and routes them through loopback modules so game audio and mic input flow between the host's main audio stack and the container.
   - **Container side**: PipeWire exposes its own ALSA sink/source on `hw:31,1` so games see a normal audio device.
   - WirePlumber on the host ignores the loopback card to avoid conflicts.
   - This split is deliberate: the games never see the host's PipeWire graph. If we forwarded it, a malicious game could listen to the host microphone and every other audio stream with no access controls at all. With the loopback, access is bounded, muting "Gaming Container Mic Input" on the host truly cuts the container's mic, and the container can never hear other host audio. The tradeoff is minimal added latency.
5. Input device passthrough uses a udev-based approach:
   - Joystick/hidraw events are copied to `/dev/gaming_input/` on the host and chowned to the container's mapped uid.
   - A `controller-linker` service inside the container watches `/dev/gaming_input` with `inotifywait` and symlinks hidraw devices into `/dev/` as they appear.
   - The container bind-mounts `/dev/gaming_input` as both itself and `/dev/input`.
   - The whole `/dev/input` directory is never forwarded, because it contains the raw keyboard and mouse event nodes, handing that over would give every game a silent keylogger for the host session. Only controller nodes are exposed (joystick events plus vendor-filtered hidraw for Sony/Microsoft/Nintendo pads), and a path-scoped cgroup rule caps the container at exactly those `/dev/gaming_input/*` nodes.
6. `/dev/uinput` is passed so Steam Input's gyro/controller emulation can create virtual gamepads. This is the one deliberate input-injection surface and is kept only because gyro mapping requires it (see Security Model).
7. A `gaming-container-renicer` host service continuously boosts priority (`nice -4` to `-11`) for gamescope, WiVRn, game threads, and PipeWire processes running under the container uid.
8. Game libraries from secondary drives (`/persist/mnt/3tb/Games`, `/persist/mnt/crucial/Games`, `/persist/mnt/patriot/Games`) are bind-mounted into the container. A persistent home is at `~/Containers/gameSandbox/Home/`.

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

I run these as **containers, not VMs**, on purpose. GPU-passthrough VMs carry serious performance overhead, and anti-cheat systems (EAC, BattlEye, etc.) do not like VMs, so a shared-kernel `systemd-nspawn` container is the strongest isolation I'm willing to risk. That makes this **threat reduction, not a hard boundary**: the container shares the host kernel, and the GPU, Wayland socket, and uinput are explicitly granted.

What the sandbox does give you:

- `--private-users` user namespaces remap every container uid to an unprivileged host uid, container root is never host root, so there is no uid-0 path to the host.
- Per-device allowlists: `allowedDevices` pins the exact GPU, audio, and uinput nodes. The gaming container's controller access is additionally capped by a cgroup rule scoped to `/dev/gaming_input/*` rather than the whole input subsystem.
- `--system-call-filter` blocks dangerous syscall groups. The dev container drops `@clock`, `@module`, `@reboot`, and `@swap`.
- No host filesystem is reachable except the explicitly bind-mounted paths.
- Sudo is granted NOPASSWD for the single launch script only, scoped per user (a container compromise can't escalate the sudo surface).

Acknowledged tradeoffs:

- **`/dev/uinput`** keeps Steam Input's gyro mapping working but is a real keystroke-injection vector if the game itself is hostile. There is no other way to get gyro besides mapping on the host and passing it through, however steaminput is convenient, so it stays.
- **The host Wayland socket** is exposed so games render onto your desktop; a compromised game could read or synthesize input through the compositor.
- **Raw GPU access** (Vulkan/AMD driver) is a large attack surface and can be abused for DMA or driver exploits; unavoidable, could happen even with a VM passthrough unless using something like Venus to abstract calls.
- **Audio is bounded, not trusted**, the loopback split means the container can only hear what you deliberately route into its virtual card.
- **Anticheat-friendly by design**: no VM, no fake TPM, no kernel oddities games run on the real GPU driver the way a bare-metal install would. And since Linux anti-cheats (EAC, BattlEye) operate in user-space rather than as kernel modules, there is only so much they can realistically do. That also means the container is trivially *detectable*. `systemd-detect-virt`, `/run/systemd/container`, `uid_map`, and interface names give it away to any user-space check but mainstream anti-cheats don't enforce those checks today. If one ever starts, it's undefendable: the fingerprints are the isolation mechanisms themselves, and faking them would mean dropping the user namespaces that make the container safe in the first place. No circumvention is attempted; games that won't tolerate the container simply get played outside it or not at all as I have come to realise from gaming on Linux.

Realistic threat model: treat games in the container as "untrusted but not actively malicious." The win here is containing dependency chaos, update side-effects, anti-cheat tampering, and accidental host filesystem damage. Defending against a genuinely hostile game would require a VM which comes with the same or worse anti-cheat problems.
