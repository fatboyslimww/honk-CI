#!/bin/sh
# SPDX-License-Identifier: MIT
#
# upstream-check.sh - does the upstream tree still look like the one our
# build-time edits assume?
#
# The firmware is built from VIKINGYFY/immortalwrt, unmodified. Everything this
# repo changes is applied by Scripts/Handles.sh / Settings.sh at build time and
# is guarded by a pattern (a line we expect to find). When upstream renames or
# removes that line, the sed silently stops matching and the image is built with
# upstream's default instead of ours -- no error, just a different firmware.
#
# This script is the tripwire. Run it against a fresh clone:
#
#   upstream-check.sh /path/to/immortalwrt
#
# Exit 0 = every anchor found, 1 = something to fix, 2 = bad usage.

set -u
TREE="${1:-}"
[ -n "$TREE" ] || { echo "usage: $0 <upstream tree>" >&2; exit 2; }
[ -d "$TREE" ] || { echo "no such tree: $TREE" >&2; exit 2; }

fails=0
ok()   { printf '  %-58s %s\n' "$1" "ok"; }
bad()  { printf '  %-58s %s\n' "$1" "MISSING"; fails=$((fails + 1)); }
have() { grep -qE "$2" "$TREE/$1" 2>/dev/null; }

echo "== anchors used by Scripts/Handles.sh =="

# X86 GPU/DRM trim: these three patterns are the ones the sed rewrites.
if have target/linux/x86/Makefile 'DEFAULT_PACKAGES.*video-support'; then
	ok "x86 Makefile: video-support in DEFAULT_PACKAGES"
else
	bad "x86 Makefile: video-support in DEFAULT_PACKAGES"
fi
if have target/linux/x86/Makefile 'i915-firmware-dmc'; then
	ok "x86 Makefile: i915-firmware-dmc"
else
	bad "x86 Makefile: i915-firmware-dmc"
fi
found_mk=0
for mk in "$TREE"/target/linux/x86/image/*.mk; do
	[ -f "$mk" ] || continue
	grep -q 'kmod-drm-i915' "$mk" && found_mk=1
done
[ "$found_mk" = 1 ] && ok "x86 image/*.mk: kmod-drm-i915" || bad "x86 image/*.mk: kmod-drm-i915"

# firewall4: the line we flip on the eBPF targets. Its *value* differs by
# branch on purpose: owrt ships 1 (kernel flowtable is the acceleration path),
# main ships 0 (those images accelerate with qca-nss/ECM, not with the nft
# flowtable). What must never disappear is the line itself, because that is what
# Handles.sh flips for X86/ROCKCHIP and what the IPQ guard reports.
F4=package/network/config/firewall4/patches/002-default-enable-fullcone.patch
if have "$F4" '^\+[[:space:]]*option[[:space:]]+flow_offloading[[:space:]]+[01]'; then
	val=$(grep -oE 'option[[:space:]]+flow_offloading[[:space:]]+[01]' "$TREE/$F4" 2>/dev/null | head -1 | awk '{print $NF}')
	ok "firewall4 patch: flow_offloading $val"
else
	bad "firewall4 patch: flow_offloading (line absent)"
fi
if have "$F4" '^\+[[:space:]]*option[[:space:]]+flow_offloading_hw[[:space:]]+[01]'; then
	val=$(grep -oE 'option[[:space:]]+flow_offloading_hw[[:space:]]+[01]' "$TREE/$F4" 2>/dev/null | head -1 | awk '{print $NF}')
	ok "firewall4 patch: flow_offloading_hw $val"
else
	bad "firewall4 patch: flow_offloading_hw (line absent)"
fi

# target.mk: kmod-nft-offload removal + odhcpd handover.
have include/target.mk '^[[:space:]]*kmod-nft-offload' \
	&& ok "include/target.mk: kmod-nft-offload" \
	|| bad "include/target.mk: kmod-nft-offload"
have include/target.mk '^[[:space:]]*odhcpd-ipv6only' \
	&& ok "include/target.mk: odhcpd-ipv6only" \
	|| bad "include/target.mk: odhcpd-ipv6only"

# dnsmasq/odhcpd handover.
have package/network/services/dnsmasq/files/dhcp.conf '^config[[:space:]]+dhcp[[:space:]]+lan$' \
	&& ok "dnsmasq dhcp.conf: config dhcp lan" \
	|| bad "dnsmasq dhcp.conf: config dhcp lan"
have package/network/services/odhcpd/files/odhcpd.defaults 'dhcp\.odhcpd\.maindhcp=' \
	&& ok "odhcpd.defaults: maindhcp" \
	|| bad "odhcpd.defaults: maindhcp"

# hostapd support symbols: qualcommbe builds flip these to
# "default y if TARGET_qualcommbe" (kmod-ath12k depends on all three and the
# MU-EDCA patch needs CONFIG_IEEE80211AX). Upstream must still have them as
# "default n", otherwise Handles.sh would be rewriting something that changed.
for sym in DRIVER_11AC_SUPPORT DRIVER_11AX_SUPPORT DRIVER_11BE_SUPPORT; do
	if have package/network/services/hostapd/Config.in "^config ${sym}$" &&
		grep -A3 "^config ${sym}$" "$TREE/package/network/services/hostapd/Config.in" 2>/dev/null | grep -qE '^[[:space:]]*default n$'; then
		ok "hostapd Config.in: $sym default n"
	else
		bad "hostapd Config.in: $sym default n"
	fi
done

echo "== anchors used by Scripts/apply-nsy-g68.sh =="

# Version guards in the board script.
have target/linux/rockchip/Makefile '^KERNEL_PATCHVER:=6\.18$' \
	&& ok "rockchip Makefile: KERNEL_PATCHVER 6.18" \
	|| bad "rockchip Makefile: KERNEL_PATCHVER 6.18"
have package/boot/uboot-rockchip/Makefile '^PKG_VERSION:=2026\.10$' \
	&& ok "uboot-rockchip Makefile: PKG_VERSION 2026.10" \
	|| bad "uboot-rockchip Makefile: PKG_VERSION 2026.10"

# Makefile insertion anchors.
have package/boot/uboot-rockchip/Makefile '^define U-Boot/nanopi-r5c-rk3568$' \
	&& ok "uboot-rockchip Makefile: nanopi-r5c-rk3568 block" \
	|| bad "uboot-rockchip Makefile: nanopi-r5c-rk3568 block"
have package/boot/uboot-rockchip/Makefile '^  mrkaio-m68s-rk3568 \\$' \
	&& ok "uboot-rockchip Makefile: mrkaio-m68s-rk3568 target" \
	|| bad "uboot-rockchip Makefile: mrkaio-m68s-rk3568 target"
have target/linux/rockchip/image/armv8.mk '^define Device/rk3568$' \
	&& ok "rockchip armv8.mk: Device/rk3568 template" \
	|| bad "rockchip armv8.mk: Device/rk3568 template"

# 02_network function and first-case anchors.
NETWORK_BD=target/linux/rockchip/armv8/base-files/etc/board.d/02_network
have "$NETWORK_BD" '^rockchip_setup_interfaces\(\)$' \
	&& ok "rockchip 02_network: setup_interfaces" \
	|| bad "rockchip 02_network: setup_interfaces"
have "$NETWORK_BD" '^rockchip_setup_macs\(\)$' \
	&& ok "rockchip 02_network: setup_macs" \
	|| bad "rockchip 02_network: setup_macs"
have "$NETWORK_BD" '^[[:space:]]+9tripod,x3568-v4\|\\$' \
	&& ok "rockchip 02_network: interface case anchor" \
	|| bad "rockchip 02_network: interface case anchor"
have "$NETWORK_BD" '^[[:space:]]+rumu3f,fine-3399\|\\$' \
	&& ok "rockchip 02_network: MAC case anchor" \
	|| bad "rockchip 02_network: MAC case anchor"

echo
if [ "$fails" = 0 ]; then
	echo "RESULT: upstream still matches every build-time anchor"
	exit 0
fi
echo "RESULT: $fails anchor(s) missing -- Scripts/Handles.sh needs updating before the next build"
exit 1
