{
  description = "Unified NixOS Flake for Desktop and Laptop";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, impermanence, lanzaboote, ... }@inputs: {
    nixosConfigurations = {
      isaac-dining-desktop = nixpkgs.lib.nixosSystem {
        modules = [
          impermanence.nixosModules.impermanence
          lanzaboote.nixosModules.lanzaboote
          ./common/system.nix
          ./common/wipe.nix
          ./common/persist.nix
          ./common/devcontainer.nix
          ./hosts/desktop/configuration.nix
          ./hosts/desktop/hardware-configuration.nix
          ./hosts/desktop/drivemounts.nix
          ./hosts/desktop/gamingcontainer.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.isaac = {
              imports = [
                ./common/home.nix
                ./hosts/desktop/home.nix
              ];
            };
          }
          ({ pkgs, lib, ... }: {
            environment.systemPackages = [
              pkgs.e2fsprogs
            ];

            boot.loader.systemd-boot.enable = lib.mkForce false;

            boot.lanzaboote = {
              enable = true;
              pkiBundle = "/var/lib/sbctl";
            };
          })
        ];
      };

      isaac-laptop = nixpkgs.lib.nixosSystem {
        modules = [
          impermanence.nixosModules.impermanence
          ./common/system.nix
          ./common/wipe.nix
          ./common/persist.nix
          ./common/devcontainer.nix
          ./hosts/laptop/configuration.nix
          ./hosts/laptop/hardware-configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.isaac = {
              imports = [
                ./common/home.nix
                ./hosts/laptop/home.nix
              ];
            };
          }
        ];
      };
    };
  };
}
