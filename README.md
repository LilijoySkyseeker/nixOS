# Liljoy's NixOS Dotfiles

## Structure Guide

All configuration starts with [flake.nix](./flake.nix)

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
easier and imported in the main
[configuration.nix](./hosts/homelab/configuration.nix) file.

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
formatting.

Then it progresses to the shared profiles by importing
[default.nix](./profiles/default.nix) or others

```bash
NixOS
└── profiles
    ├── default.nix
    ├── PC.nix
    └── server.nix
```

## Hosts

### **homelab** (Main Server)

### **thinkpad** (Main Laptop)

#### Hardware

- Chasis: ThinkPad P1 Gen 3, Lenovo
- CPU: Core i7-10750H 6x, Intel
- GPU: Quadro T1000 4GB Max-Q, NVIDIA
- RAM: 16 GB (1x16GB) DDR4
- SSD1: 500 GB M.2, Samsung 970 EVO Plus
- SSD2: 256 GB M.2, INTEL SSDPEKKW256G8L
- Display: 15" 1080p 60Hz

### **torrent** (Main Desktop)

#### Hardware

- CPU: Ryzen 7 9800x3D 8x, AMD
- GPU: RX 7900XTX 24 GB, XFX SPEEDSTER MERC 310
- RAM: 96 GB (2x48GB) DDR5 6000MHz CL30, CORSAIR VENGEANCE
- SSD: 4 TB M.2, SAMSUNG 990 PRO
- Motherboard: X870 ATX LGA 1718, GIGABYTE AORUS ELITE ICE
- CPU Cooler: NH-D15 G2, Noctua
- Thermal Paste: PTM 7950
- Power Supply: 1000W ATX 80 PLUS PLATINUM, Super Flower Leadex VI
- Case: Torrent Black Solid, Fractal Design
- Monitors: 3x 27" 4K 60Hz, Dell S2721QS
- Keyboard (Gaming): WOOTING TWO HE
- Keyboard (Work): faux fox keyboard v4, fingerpunch
- Mouse: MM710 PMW3389, Cooler Master
- Headphones: WH-1000XM4 (Wired), Sony
- Speakers: A5+, Audioengine
- Microphone: AT2020, Audio-Technica
- Interface: RC-505MKII, BOSS

### **legion** (Secondary Laptop/Desktop)

#### Hardware

- Chasis: Legion Y540-15IRH, Lenovo
- CPU: Core i7-9750H 6x, Intel
- GPU: RTX 2060 6GB, NVIDIA
- RAM: 32 GB (2x16GB) DDR4
- SSD1: 512 GB M.2
- HHD1: 1 TB 2.5" SATA
- Display: 17" 1080p 144Hz
- Mouse: MM710 PMW3389, Cooler Master

### **isoimage** (USB Installer)
