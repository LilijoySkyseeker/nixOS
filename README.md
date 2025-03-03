# Lilijoy's NixOS Machines

## Structure Guide

All configuration starts with [flake.nix](./flake.nix#L22)

```bash
NixOS
└── flake.nix
```

where the inputs of the system, the different host configurations, and universal
variables are defined.

Then it progresses to each host with its base
[configuration.nix](./hosts/homelab/configuration.nix) (homelab as the example)

```bash
NixOS
└── hosts
    └── homelab
        └── configuration.nix
```

where the host specific configuration is held. Things like hostname, timezone,
system services, etc. Anything that only this hosts needs and is not shared is
defined here.

Some specific configuration is split into seperate files to make orginzation
easier and is imported in the main
[configuration.nix](./hosts/homelab/configuration.nix).

```bash
NixOS
└── hosts
    └── homelab
        ├── configuration.nix
        ├── disko.nix
        └── hardware-configuration.nix
```

In this case, the
[hardware-configuration.nix](./hosts/homelab/hardware-configuration.nix) which
is auto generated during system installation is left alone. Alongside that is
[disko.nix](./hosts/homelab/disko.nix) which manages disk partitioning and
formatting using [disko](https://github.com/nix-community/disko/).

Then it progresses to the shared profiles by importing
[default.nix](./profiles/default.nix) and one or more of the others.

```bash
NixOS
└── profiles
    ├── default.nix
    ├── PC.nix
    └── server.nix
```

These profiles contain the configuration that is shared with other hosts,
[default.nix](./profiles/default.nix) in particular contains configuration that
is shared universally amongst all hosts. The other profiles are based on the
role the host is taking.

These profiles and the individiul host
[configuration.nix](./hosts/homelab/configuration.nix) import modules and
services that have been split appart for orginzation.

```bash
NixOS
├── modules
│   ├── home-manager
│   │   ├── gnome.nix
│   │   ├── kde.nix
│   │   └── tooling.nix
│   └── nixos
│       ├── beets.nix
│       ├── copypartymount.nix
│       ├── gnome.nix
│       ├── kde.nix
│       ├── tooling.nix
│       ├── virtual-machines.nix
│       ├── winapps.nix
│       └── wooting.nix
└── services
    ├── copyparty.nix
    ├── factorio.nix
    ├── jellyfin.nix
    ├── minecraft.nix
    ├── nextcloud.nix
    ├── rss.nix
    ├── samba.nix
    └── webdav.nix
```

These are simply self contained collections of configuration for a specific
task. The [modules](./modules) are for local configuration. While
[services](./services) are for anything being served to LAN or WAN.

What's left is a section for custom packages, standalone files, and encrypted
secret managment with [sops-nix](https://github.com/Mic92/sops-nix).

```bash
NixOS
├── custom-packages
│   └── tpm-fido
│       └── package.nix
├── files
│   ├── ffkbV4.vil
│   ├── gruvbox-dark-rainbow.png
│   └── S2721Q.icm
├── secrets
│   └── secrets.yaml
└── .sops.yaml
```

## Hosts

## Iteresting Stuff
