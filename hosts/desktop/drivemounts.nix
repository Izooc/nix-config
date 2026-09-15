{ config, pkgs, ...}:
{
    environment.etc.crypttab = {
    enable = true;
    text = ''
      enc-patriot UUID=d27dfa3e-db96-4b5d-9890-760a7c660e05 /persist/keys/patriotKeyfile luks,discard
      enc-3tb UUID=5309a2ec-0445-4645-9190-6eef1a12f5eb /persist/keys/3tbKeyfile luks
      enc-crucial UUID=f9a0d8b4-90fb-44c3-a8ec-e06506c0f8d2 /persist/keys/crucialKeyfile luks,discard
    '';
    };

    fileSystems."/persist/mnt/patriot" =
     { device = "/dev/disk/by-uuid/6102e542-0321-4c1e-bafa-410b83e2e70b";
        fsType = "ext4";
        options = [ "nofail"];
     };

    fileSystems."/persist/mnt/crucial" =
     { device = "/dev/disk/by-uuid/a87ea836-f18f-4409-9ec4-f9773f1c8729";
        fsType = "ext4";
        options = [ "nofail"];
     };

    fileSystems."/persist/mnt/3tb" =
     { device = "/dev/disk/by-uuid/83907b6e-3e6b-47ba-891a-fe603b3ad762";
        fsType = "ext4";
        options = [ "nofail"];
     };
}
