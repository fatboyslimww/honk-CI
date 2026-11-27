# NSY G68-PLUS board support

Out-of-tree build support for the **NSY G68-PLUS** (RK3568 router/NAS
board). The firmware source remains the upstream
`VIKINGYFY/immortalwrt@owrt` tree; `Scripts/apply-nsy-g68.sh` copies these
files in and registers the device at build time.

Reference implementation:
<https://github.com/iiibeloved/istoreos-hybrid-g68>

## Hardware assumptions

- Rockchip RK3568, eMMC boot, NVMe on PCIe
- RTL8367S five-port switch through the mainline `rtl8365mb` DSA driver
  (`lan1`-`lan4` + `wan`)
- CPU port on `gmac0` (RGMII); `gmac1` is SGMII/XPCS
- ADC recovery key and GPIO power LED
- U-Boot boot-mode register for long-press-reset MaskROM entry

## Files and destinations

| Source | Installed into the cloned OpenWrt tree |
|---|---|
| `kernel-dts/rk3568-nsy-g68-plus.dts` | `target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/` |
| `kernel-patches/913-9999-ethernet-stmmac-dwmac-rk-Disable-Auto-Nego-for-1000.patch` | `target/linux/rockchip/patches-6.18/` |
| `uboot/rk3568-nsy-g68-plus.dts` | `package/boot/uboot-rockchip/src/arch/arm/dts/` |
| `uboot/rk3568-nsy-g68-plus-u-boot.dtsi` | `package/boot/uboot-rockchip/src/arch/arm/dts/` |
| `uboot/nsy-g68-plus-rk3568_defconfig` | `package/boot/uboot-rockchip/src/configs/` |

The script also adds the U-Boot target and image device to the upstream
Makefiles, and inserts the `nsy,g68-plus` interface/MAC cases into the
upstream Rockchip `02_network`. A separate `02_network_g68` file is
deliberately not installed: the upstream script would first assign `eth0`
to unknown boards, leaving a stale `lan.device` entry in `board.json`.

## Version assumptions

The board files are prepared against:

- Rockchip target `KERNEL_PATCHVER:=6.18`
- `uboot-rockchip` `PKG_VERSION:=2026.10`

Both are hard guards in `Scripts/apply-nsy-g68.sh`. A version bump must be
re-reviewed; it is not a best-effort build. The Makefile edits are also
anchored and fail immediately if an expected upstream line disappears.

## Deliberately not carried from the reference repository

- **910/911/915 SGMII/XPCS/combphy patches**: the pinned upstream tree
  already contains the corresponding support.
- **A DTB Makefile patch**: upstream `Image/BuildDTB` compiles
  `DEVICE_DTS` directly under `DEVICE_DTS_DIR=$(DTS_DIR)/rockchip`.
- **A boot-mode overlay**: the U-Boot defconfig carries the validated
  `CONFIG_ROCKCHIP_BOOT_MODE_REG` value directly.

## Verification status

Checked in this repository:

- `apply-nsy-g68.sh` is idempotent against a mock upstream tree; every
  Makefile block and both `02_network` cases appear exactly once, and the
  edited network script still passes `sh -n`.
- `gmake nsy-g68-plus-rk3568_defconfig` succeeds against U-Boot 2026.10.
- The 913 dwmac-rk patch applies cleanly to the pinned Linux 6.18 source.
- The RK3568 DTS labels used here exist in the pinned upstream tree, and
  the RTL8367S port is covered by upstream `rtl8365mb`.

Not yet verified by a complete CI image build or on hardware. The following
need real-device confirmation:

- physical `lan1`-`lan4` / `wan` port order and RTL8367S port mapping
- PCIe split, reset GPIO polarity, and NVMe enumeration
- SGMII/XPCS link behavior on the 2.5G-capable port at 1000M
- reset/ADC key MaskROM entry and the power LED
