#!/bin/bash
# Fail fast if the PZ-L8 seed loses the NSS, honk or zram pieces it needs.
set -euo pipefail

CONFIG=${1:-.config}
[ -f "$CONFIG" ] || {
	echo "!! verify-pz-l8: missing $CONFIG" >&2
	exit 1
}

missing=0
require() {
	if grep -qx "$1=y" "$CONFIG"; then
		echo "  ok    $1"
	else
		echo "  MISS  $1" >&2
		missing=1
	fi
}

for sym in \
	CONFIG_TARGET_qualcommax_ipq50xx_DEVICE_cmcc_pz-l8 \
	CONFIG_PACKAGE_kmod-qca-nss-drv \
	CONFIG_PACKAGE_kmod-qca-nss-dp \
	CONFIG_PACKAGE_kmod-qca-nss-ecm \
	CONFIG_PACKAGE_kmod-qca-ssdk \
	CONFIG_PACKAGE_nss-firmware-ipq50xx \
	CONFIG_NSS_FIRMWARE_VERSION_12_5 \
	CONFIG_NSS_DRV_WIFIOFFLOAD_ENABLE \
	CONFIG_PACKAGE_ath11k-firmware-ipq5018-qcn6122 \
	CONFIG_PACKAGE_ipq-wifi-cmcc_pz-l8 \
	CONFIG_PACKAGE_honk \
	CONFIG_PACKAGE_luci-app-honk \
	CONFIG_PACKAGE_v2ray-geoip \
	CONFIG_PACKAGE_v2ray-geosite \
	CONFIG_PACKAGE_kmod-zram \
	CONFIG_PACKAGE_zram-swap \
	CONFIG_PACKAGE_luci-light \
	CONFIG_PACKAGE_kmod-nft-queue
do
	require "$sym"
done

# The eBPF/DPD dataplane belongs to X86/ROCKCHIP. It must not leak into the
# NSS firmware, where ECM/NSS owns the forwarding path.
for pkg in dpd-fastpath einat-ebpf dpdfwd router-acl router-qos router-dataplane; do
	if grep -qx "CONFIG_PACKAGE_${pkg}=y" "$CONFIG"; then
		echo "  LEAK  CONFIG_PACKAGE_${pkg}=y" >&2
		missing=1
	fi
done

[ "$missing" = 0 ] || {
	echo "!! verify-pz-l8: required PZ-L8/NSS/honk/zram symbols are missing" >&2
	exit 1
}

echo "verify-pz-l8: NSS + honk + zram config OK"
