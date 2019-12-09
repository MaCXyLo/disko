with import <nixpkgs/lib> ({ body, config, pkgs, ... }:
with builtins;

let {

  body.config = config-f {};
  body.creation = creation-f {};
  body.mount = mount-f {};


  config-f = q: x: config.${x.type} q x;

  config.filesystem = q: x: {
    fileSystems.${x.mountpoint} = {
      device = q.device;
      fsType = x.format;
      ${if x ? options then "options" else null} = x.options;
    };
  };

  config.devices = q: x:
    foldl' recursiveUpdate {} (mapAttrsToList (name: config-f { device = "/dev/${name}"; }) x.content);

  config.luks = q: x: {
    boot.initrd.luks.devices.${x.name}.device = q.device;
  } // config-f { device = "/dev/mapper/${x.name}"; } x.content;

  config.lv = q: x:
    config-f { device = "/dev/mapper/${q.vgname}-${q.name}"; } x.content;

  config.lvm = q: x:
    foldl' recursiveUpdate {} (mapAttrsToList (name: config-f { inherit name; vgname = x.name; }) x.lvs);

  config.partition = q: x:
    config-f { device = q.device + toString q.index; } x.content;

  config.table = q: x:
    foldl' recursiveUpdate {} (imap (index: config-f (q // { inherit index; })) x.partitions);


  creation-f = q: x: creation.${x.type} q x;

  creation.filesystem = q: x: ''
    mkfs.${x.format} ${q.device}
  '';

  creation.devices = q: x: ''
    ${concatStrings (mapAttrsToList (name: creation-f { device = "/dev/${name}"; }) x.content)}
  '';

  creation.luks = q: x: ''
    cryptsetup -q luksFormat ${q.device} ${x.keyfile} ${toString (x.extraArgs or [])}
    cryptsetup luksOpen ${q.device} ${x.name} --key-file ${x.keyfile}
    ${creation-f { device = "/dev/mapper/${x.name}"; } x.content}
  '';

  creation.lv = q: x: ''
    lvcreate -L ${x.size} -n ${q.name} ${q.vgname}
    ${creation-f { device = "/dev/mapper/${q.vgname}-${q.name}"; } x.content}
  '';

  creation.lvm = q: x: ''
    pvcreate ${q.device}
    vgcreate ${x.name} ${q.device}
    ${concatStrings (mapAttrsToList (name: creation-f { inherit name; vgname = x.name; }) x.lvs)}
  '';

  creation.partition = q: x: ''
    parted -s ${q.device} mkpart ${x.part-type} ${x.fs-type or ""} ${x.start} ${x.end}
    ${optionalString (x.bootable or false) ''
      parted -s ${q.device} set ${toString q.index} boot on
    ''}
    ${creation-f { device = q.device + toString q.index; } x.content}
  '';

  creation.table = q: x: ''
    parted -s ${q.device} mklabel ${x.format}
    ${concatStrings (imap (index: creation-f (q // { inherit index; })) x.partitions)}
  '';


  mount-f = q: x: mount.${x.type} q x;

  mount.filesystem = q: x: {
      fs.${x.mountpoint} = ''
        if ! [ "$(mount | sed -n 's:\([^ ]\+\) on /mnt${x.mountpoint} .*:\1:p')" = ${q.device} ]; then
          mkdir -p /mnt${x.mountpoint}
          mount ${q.device} /mnt${x.mountpoint}
        fi
      '';
    };

  mount.devices = q: x: let
    z = foldl' recursiveUpdate {} (mapAttrsToList (name: mount-f { device = "/dev/${name}"; }) x.content);
    # attrValues returns values sorted by name.  This is important, because it
    # ensures that "/" is processed before "/foo" etc.
  in ''
    ${optionalString (hasAttr "luks" z) (concatStringsSep "\n" (attrValues z.luks))}
    ${optionalString (hasAttr "lvm" z) (concatStringsSep "\n" (attrValues z.lvm))}
    ${optionalString (hasAttr "fs" z) (concatStringsSep "\n" (attrValues z.fs))}
  '';

  mount.luks = q: x: (
    recursiveUpdate
    (mount-f { device = "/dev/mapper/${x.name}"; } x.content)
    {luks.${q.device} = ''
      cryptsetup luksOpen ${q.device} ${x.name} --key-file ${x.keyfile}
    '';}
  );

  mount.lv = q: x:
    mount-f { device = "/dev/mapper/${q.vgname}-${q.name}"; } x.content;

  mount.lvm = q: x: (
    recursiveUpdate
    (foldl' recursiveUpdate {} (mapAttrsToList (name: mount-f { inherit name; vgname = x.name; }) x.lvs))
    {lvm.${q.device} = ''
      vgchange -a y
    '';}
  );

  mount.partition = q: x:
    mount-f { device = q.device + toString q.index; } x.content;

  mount.table = q: x:
    foldl' recursiveUpdate {} (imap (index: mount-f (q // { inherit index; })) x.partitions);

};)
