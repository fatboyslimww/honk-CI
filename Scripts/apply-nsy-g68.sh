#!/bin/bash
# SPDX-License-Identifier: MIT
#
# apply-nsy-g68.sh - add NSY G68-PLUS build support to the cloned OpenWrt tree.
#
# The firmware source is upstream immortalwrt, cloned fresh by WRT-CORE.yml.
# This script only runs for WRT_CONFIG=ROCKCHIP and is deliberately fail-hard:
# every Makefile edit is anchored on a line that exists in the pinned upstream
# tree (rockchip 6.18 + U-Boot 2026.10). If an anchor disappears, the build
# stops here instead of silently producing an image without the device.
#
# It is idempotent: re-running it overwrites the copied board files and only
# inserts the Makefile blocks that are still missing.
#
# Usage in CI:
#   GITHUB_WORKSPACE=/path/to/repo WRT_CONFIG=ROCKCHIP Scripts/apply-nsy-g68.sh

set -euo pipefail

CONFIG_NAME="${WRT_CONFIG:-}"
if [ "$CONFIG_NAME" != "ROCKCHIP" ]; then
	echo "apply-nsy-g68: WRT_CONFIG=${CONFIG_NAME:-<unset>} (ROCKCHIP only) -> skipped"
	exit 0
fi

: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE must be set}"

TREE="$GITHUB_WORKSPACE/wrt"
SRC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$SRC_ROOT/device/nsy-g68-plus"

die() {
	echo "!! apply-nsy-g68: $*" >&2
	exit 1
}

say() {
	echo "   $*"
}

[ -d "$TREE" ] || die "upstream tree not found: $TREE"
[ -d "$DEV" ] || die "board files not found: $DEV"

ROCKCHIP_MK="$TREE/target/linux/rockchip/Makefile"
UBOOT_MK="$TREE/package/boot/uboot-rockchip/Makefile"
IMAGE_MK="$TREE/target/linux/rockchip/image/armv8.mk"
NETWORK_BD="$TREE/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"

[ -f "$ROCKCHIP_MK" ] || die "missing $ROCKCHIP_MK"
[ -f "$UBOOT_MK" ] || die "missing $UBOOT_MK"
[ -f "$IMAGE_MK" ] || die "missing $IMAGE_MK"
[ -f "$NETWORK_BD" ] || die "missing $NETWORK_BD"

# Version guards. These are the two upstream versions the board files were
# prepared and compile-checked against; anything else needs a deliberate
# re-review, not a best-effort build.
grep -qx 'KERNEL_PATCHVER:=6.18' "$ROCKCHIP_MK" ||
	die "target/linux/rockchip is no longer 6.18 (KERNEL_PATCHVER anchor missing)"
grep -qx 'PKG_VERSION:=2026.10' "$UBOOT_MK" ||
	die "uboot-rockchip is no longer 2026.10 (PKG_VERSION anchor missing)"

install_file() {
	local src="$1" dst="$2" mode="${3:-0644}"
	[ -f "$src" ] || die "missing source file: $src"
	install -d "$(dirname "$dst")"
	install -m "$mode" "$src" "$dst"
	say "installed ${dst#"$TREE"/}"
}

insert_block_before() {
	local file="$1" anchor="$2" blockfile="$3" label="$4" section="${5:-}"
	local tmp rc

	grep -Fqx "$anchor" "$file" ||
		die "$label: anchor missing in ${file#"$TREE"/}: $anchor"
	if [ -n "$section" ]; then
		grep -Fqx "$section" "$file" ||
			die "$label: section missing in ${file#"$TREE"/}: $section"
	fi

	tmp=$(mktemp)
	SECTION="$section" ANCHOR="$anchor" BLOCKFILE="$blockfile" awk '
		BEGIN { done = 0; in_section = 0 }
		ENVIRON["SECTION"] != "" && $0 == ENVIRON["SECTION"] {
			in_section = 1
		}
		!done && (ENVIRON["SECTION"] == "" || in_section) &&
			$0 == ENVIRON["ANCHOR"] {
			while ((getline line < ENVIRON["BLOCKFILE"]) > 0)
				print line
			close(ENVIRON["BLOCKFILE"])
			done = 1
		}
		{ print }
		END { if (!done) exit 3 }
	' "$file" > "$tmp" || {
		rc=$?
		rm -f "$tmp"
		die "$label: block insertion failed (rc=$rc)"
	}

	# Keep the inode/permissions; do not mv a fresh file over the Makefile.
	cat "$tmp" > "$file"
	rm -f "$tmp"
	say "$label: inserted"
}

TMP_UBOOT_BLOCK=$(mktemp)
TMP_UBOOT_TARGET=$(mktemp)
TMP_IMAGE_BLOCK=$(mktemp)
trap 'rm -f "$TMP_UBOOT_BLOCK" "$TMP_UBOOT_TARGET" "$TMP_IMAGE_BLOCK"' EXIT

cat > "$TMP_UBOOT_BLOCK" <<'EOF'
define U-Boot/nsy-g68-plus-rk3568
  $(U-Boot/rk3568/Default)
  NAME:=NSY G68 PLUS
  BUILD_DEVICES:= \
    nsy_g68-plus
endef
EOF

printf '%s\n' '  nsy-g68-plus-rk3568 \' > "$TMP_UBOOT_TARGET"

cat > "$TMP_IMAGE_BLOCK" <<'EOF'
define Device/nsy_g68-plus
  $(Device/rk3568)
  DEVICE_VENDOR := NSY
  DEVICE_MODEL := G68-PLUS
  DEVICE_DTS := rk3568-nsy-g68-plus
  UBOOT_DEVICE_NAME := nsy-g68-plus-rk3568
  DEVICE_PACKAGES += kmod-dsa-realtek kmod-dsa-rtl8365mb \
    kmod-input-adc-keys kmod-nvme
endef
TARGET_DEVICES += nsy_g68-plus
EOF

echo "== NSY G68-PLUS: copying board files =="

install_file \
	"$DEV/kernel-dts/rk3568-nsy-g68-plus.dts" \
	"$TREE/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-nsy-g68-plus.dts"

install_file \
	"$DEV/uboot/rk3568-nsy-g68-plus.dts" \
	"$TREE/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-nsy-g68-plus.dts"

install_file \
	"$DEV/uboot/rk3568-nsy-g68-plus-u-boot.dtsi" \
	"$TREE/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-nsy-g68-plus-u-boot.dtsi"

install_file \
	"$DEV/uboot/nsy-g68-plus-rk3568_defconfig" \
	"$TREE/package/boot/uboot-rockchip/src/configs/nsy-g68-plus-rk3568_defconfig"

install_file \
	"$DEV/kernel-patches/913-9999-ethernet-stmmac-dwmac-rk-Disable-Auto-Nego-for-1000.patch" \
	"$TREE/target/linux/rockchip/patches-6.18/913-9999-ethernet-stmmac-dwmac-rk-Disable-Auto-Nego-for-1000.patch"

echo "== NSY G68-PLUS: registering board network mapping =="
#
# Do not install a second board.d script. Upstream 02_network first assigns
# eth0 as LAN for unknown boards; a later script can replace the interface
# ports, but the old "device" key remains in board.json. Add a board-specific
# case arm to the upstream switch instead, so G68 never inherits eth0.
grep -Fqx 'rockchip_setup_interfaces()' "$NETWORK_BD" ||
	die "board.d/02_network: rockchip_setup_interfaces() anchor missing"
grep -Fqx 'rockchip_setup_macs()' "$NETWORK_BD" ||
	die "board.d/02_network: rockchip_setup_macs() anchor missing"

TMP_NET_IFACE=$(mktemp)
TMP_NET_MAC=$(mktemp)
trap 'rm -f "$TMP_UBOOT_BLOCK" "$TMP_UBOOT_TARGET" "$TMP_IMAGE_BLOCK" "$TMP_NET_IFACE" "$TMP_NET_MAC"' EXIT

cat > "$TMP_NET_IFACE" <<'EOF'
	# NSY G68-PLUS: DSA ports lan1-lan4 / wan
	nsy,g68-plus)
		ucidef_set_interfaces_lan_wan 'lan1 lan2 lan3 lan4' 'wan'
		;;
EOF

cat > "$TMP_NET_MAC" <<'EOF'
	# NSY G68-PLUS: derive stable MACs from the eMMC CID
	nsy,g68-plus)
		wan_mac=$(macaddr_generate_from_mmc_cid mmcblk0)
		lan_mac=$(macaddr_add "$wan_mac" 1)
		;;
EOF

if grep -Fqx '	# NSY G68-PLUS: DSA ports lan1-lan4 / wan' "$NETWORK_BD"; then
	say "02_network: interface mapping already present"
else
	insert_block_before "$NETWORK_BD" \
		$'\t9tripod,x3568-v4|\\' \
		"$TMP_NET_IFACE" \
		"02_network interfaces"
fi

if grep -Fqx '	# NSY G68-PLUS: derive stable MACs from the eMMC CID' "$NETWORK_BD"; then
	say "02_network: MAC mapping already present"
else
	insert_block_before "$NETWORK_BD" \
		$'\trumu3f,fine-3399|\\' \
		"$TMP_NET_MAC" \
		"02_network MACs" \
		'rockchip_setup_macs()'
fi

echo "== NSY G68-PLUS: registering U-Boot target =="

if grep -q '^define U-Boot/nsy-g68-plus-rk3568$' "$UBOOT_MK"; then
	say "U-Boot/nsy-g68-plus-rk3568: already present"
else
	insert_block_before "$UBOOT_MK" \
		'define U-Boot/nanopi-r5c-rk3568' \
		"$TMP_UBOOT_BLOCK" \
		"U-Boot/nsy-g68-plus-rk3568"
fi

if grep -Fqx '  nsy-g68-plus-rk3568 \' "$UBOOT_MK"; then
	say "UBOOT_TARGETS: nsy-g68-plus-rk3568 already present"
else
	insert_block_before "$UBOOT_MK" \
		'  mrkaio-m68s-rk3568 \' \
		"$TMP_UBOOT_TARGET" \
		"UBOOT_TARGETS"
fi

echo "== NSY G68-PLUS: registering image device =="

if grep -Fqx 'define Device/nsy_g68-plus' "$IMAGE_MK"; then
	grep -Fqx 'TARGET_DEVICES += nsy_g68-plus' "$IMAGE_MK" ||
		die "partial image block in armv8.mk (define exists, TARGET_DEVICES line absent)"
	say "Device/nsy_g68-plus: already present"
else
	grep -Fqx 'define Device/rk3568' "$IMAGE_MK" ||
		die "Device/rk3568 template missing from armv8.mk"
	printf '\n' >> "$IMAGE_MK"
	cat "$TMP_IMAGE_BLOCK" >> "$IMAGE_MK"
	say "Device/nsy_g68-plus: appended"
fi

# Final assertions: a successful run must leave exactly one of each item.
grep -Fqx 'define U-Boot/nsy-g68-plus-rk3568' "$UBOOT_MK" ||
	die "U-Boot target block was not installed"
grep -Fqx '  nsy-g68-plus-rk3568 \' "$UBOOT_MK" ||
	die "UBOOT_TARGETS entry was not installed"
grep -Fqx 'define Device/nsy_g68-plus' "$IMAGE_MK" ||
	die "image device block was not installed"
grep -Fqx 'TARGET_DEVICES += nsy_g68-plus' "$IMAGE_MK" ||
	die "TARGET_DEVICES entry was not installed"
grep -Fqx '	# NSY G68-PLUS: DSA ports lan1-lan4 / wan' "$NETWORK_BD" ||
	die "02_network interface mapping was not installed"
grep -Fqx '	# NSY G68-PLUS: derive stable MACs from the eMMC CID' "$NETWORK_BD" ||
	die "02_network MAC mapping was not installed"
[ "$(grep -Fxc '	# NSY G68-PLUS: DSA ports lan1-lan4 / wan' "$NETWORK_BD")" -eq 1 ] ||
	die "02_network interface mapping is not unique"
[ "$(grep -Fxc '	# NSY G68-PLUS: derive stable MACs from the eMMC CID' "$NETWORK_BD")" -eq 1 ] ||
	die "02_network MAC mapping is not unique"
awk '
	/^rockchip_setup_interfaces\(\)$/ { section = "interfaces"; next }
	/^rockchip_setup_macs\(\)$/ { section = "macs"; next }
	/NSY G68-PLUS: DSA ports lan1-lan4 \/ wan/ && section == "interfaces" { iface = 1 }
	/NSY G68-PLUS: derive stable MACs from the eMMC CID/ && section == "macs" { macs = 1 }
	END { exit !(iface && macs) }
' "$NETWORK_BD" ||
	die "02_network NSY G68-PLUS cases are in the wrong functions"
sh -n "$NETWORK_BD" ||
	die "02_network no longer parses after the NSY G68-PLUS edits"

echo
echo "NSY G68-PLUS: build support applied"
echo "  kernel DTS : target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-nsy-g68-plus.dts"
echo "  kernel patch: target/linux/rockchip/patches-6.18/913-9999-ethernet-stmmac-dwmac-rk-Disable-Auto-Nego-for-1000.patch"
echo "  U-Boot     : u-boot-nsy-g68-plus-rk3568 (defconfig + DTS + dtsi)"
echo "  image      : nsy_g68-plus (DEVICE_DTS=rk3568-nsy-g68-plus)"
echo "  network    : 02_network / rockchip_setup_interfaces + rockchip_setup_macs"
