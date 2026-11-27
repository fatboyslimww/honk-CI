# CMCC PZ-L8 NSS build

Target: `cmcc_pz-l8` (`qualcommax/ipq50xx`, IPQ5018 + QCA8337 + QCN6122,
256 MB RAM).

## Why this is a separate workflow

The regular `QCA-NSS` workflow builds `VIKINGYFY/immortalwrt@main`. The PZ-L8
does have an upstream `cmcc_pz-l8` device profile, but the tree shipped by
`VIKINGYFY` still describes the external QCA8337 as a mainline DSA switch and
does not carry this board's required QSDK/NSS wiring. On this board the DSA
CPU tag is not understood by the NSS firmware, so packets are exceptioned to
the host CPU instead of being accelerated.

The working board integration is maintained by
`mufeng05/openwrt-cmcc-pz-l8-nss`, against **OpenWrt v25.12.5**:

- QCA8337 driven by `qca-ssdk`/swconfig instead of DSA;
- QSDK 14.0 NSS drivers, ECM and NSS firmware 12.5;
- ath11k NSS wifili offload for the IPQ5018 + QCN6122 radios;
- the 256 MB pbuf and reserved-memory tuning measured on this board.

`Scripts/apply-pz-l8.sh` pins that project at
`788ef90a59c9e1009507ba2d577738b71f9a1951` and runs its own `setup.sh`
against the exact OpenWrt v25.12.5 tag. We do not carry a fork of either tree.

## Package set

The image is intentionally small:

| area | selection |
|---|---|
| forwarding | `kmod-qca-nss-drv`, `kmod-qca-nss-dp`, `kmod-qca-nss-ecm`, `kmod-qca-ssdk`, `nss-firmware-ipq50xx` |
| WiFi | `ath11k-firmware-ipq5018-qcn6122`, `ipq-wifi-cmcc_pz-l8` |
| proxy | `honk`, `luci-app-honk`, `v2ray-geoip`, `v2ray-geosite` |
| UI | `luci-light` + Bootstrap; no package-manager, Docker, UPnP or extra proxy frontends |
| memory | `kmod-zram` + `zram-swap`, 64 MiB lzo swap |

There is no `dpd-fastpath`, `einat-ebpf`, `dpdfwd` or `router-*` package in this
image. Those belong to the X86/ROCKCHIP eBPF dataplane. On PZ-L8 the forwarding
plane is ECM → NSS and honk uses its stock upstream core.

## 256 MB memory handling

- The board integration reserves the NSS/WiFi memory and uses the pbuf tuning
  from the reference project (`/etc/sysctl.d/30-pzl8-min-free.conf` plus the
  `nss-offload` init script).
- `device/pz-l8/root/etc/uci-defaults/95-pz-l8-zram` enables a 64 MiB zram
  device with lzo. It is a safety net against OOM, not a substitute for RAM.
- The package set drops all unrelated daemons and proxy frontends.

## Flashing

The workflow publishes the same three useful image classes as the reference
project:

- `*-squashfs-sysupgrade.bin` — `sysupgrade -n` from an existing OpenWrt;
- `*-squashfs-factory.ubi` — forced `sysupgrade -n -F` from a vendor image;
- `*-uboot-recovery.fit` — the U-Boot web-recovery payload accepted by
  `192.168.10.10`;
- `*-uboot-recovery-116m.fit` — also writes the 110M partition table/MIBIB;
  only for converting a genuine A/B factory board, and riskier on power loss.

Default LAN address: `192.168.10.1`.

## CI

- Workflow: `.github/workflows/PZ-L8.yml`
- Manual dispatch can set `TEST=true` for a config-only run.
- It is also triggered by `Auto-Clean` completion, like the other build
  pipelines.
