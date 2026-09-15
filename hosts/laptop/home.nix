{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    libreoffice
  ];

  programs.anki.enable = true;
}
