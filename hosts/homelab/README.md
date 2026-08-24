# homelab

Old laptop with usb HDD enclose used as main server.

## Hardware

MSI GL62M 7RD laptop:

- **CPU**: Intel Core i5-7300HQ (4 cores/4 threads, 2.50GHz)
- **RAM**: 16GB
- **GPU**: Intel HD Graphics 630 (iGPU) + NVIDIA GeForce GTX 1050 Mobile
- **Boot disk**: 256GB Samsung SATA SSD (`zroot`, single-disk ZFS pool)
- **Storage**: 4x 12TB HGST enterprise drives (HUH721212ALE601, USB attached),
  in two 2-disk ZFS mirrors (`zdata`, `zbackup`)
