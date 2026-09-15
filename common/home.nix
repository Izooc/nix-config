{ config, pkgs, ... }:

{
  home.username = "isaac";
  home.homeDirectory = "/home/isaac";

  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  home.stateVersion = "25.05";
}
