#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Prepare an OpenWrt v25.12.5 checkout for the CMCC PZ-L8 NSS build.
#
# The board support is not maintained as a fork here. It comes from
# mufeng05/openwrt-cmcc-pz-l8-nss at a pinned commit, applied by that project's
# own setup.sh against the exact OpenWrt tag it was written for. On top of it
# this script adds what this repository needs:
#
#   * honk + luci-app-honk (upstream kenzok8 packages, stock NSS core)
#   * v2ray-geoip / v2ray-geosite, honk's geo data dependencies
#   * a small zram swap default for the 256 MB board
#   * Config/PZ-L8.txt, instead of the reference project's larger package set
#
# Usage:
#   GITHUB_WORKSPACE=/path/to/honk-CI WRT_CONFIG=PZ-L8 \
#     Scripts/apply-pz-l8.sh /path/to/openwrt
#
# The target tree must be the v25.12.5 tag (or the same commit). The reference
# patch is a plain diff and its anchors are tag-specific; a different source
# must be reviewed and deliberately bumped here.

set -euo pipefail

CONFIG_NAME="${WRT_CONFIG:-PZ-L8}"
if [ "$CONFIG_NAME" != "PZ-L8" ]; then
	echo "apply-pz-l8: WRT_CONFIG=${CONFIG_NAME:-<unset>} (PZ-L8 only) -> skipped"
	exit 0
fi

: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE must be set}"

TREE=${1:-"$GITHUB_WORKSPACE/openwrt"}
SRC_ROOT=$(cd "$(dirname "$0")/.." && pwd)
REF_DIR=${PZ_L8_REF_DIR:-"$GITHUB_WORKSPACE/pzl8-ref"}

PZ_REF_REPO=https://github.com/mufeng05/openwrt-cmcc-pz-l8-nss.git
PZ_REF_COMMIT=788ef90a59c9e1009507ba2d577738b71f9a1951
OPENWRT_EXPECTED_COMMIT=f0a60eee2fe051741c643ea6118718aae1ef17fb
HONK_REPO=https://github.com/kenzok8/openwrt-honk.git
HONK_COMMIT=2bfaed128096695dab1b4cb8bd2f700e0e9912e8
WALL_REPO=https://github.com/kenzok8/wall.git
WALL_COMMIT=6826d40fbd3c9cc42ec59143dc8261a748033ffe

die() {
	echo "!! apply-pz-l8: $*" >&2
	exit 1
}

say() {
	echo "   $*"
}

[ -f "$TREE/rules.mk" ] || die "not an OpenWrt tree: $TREE"
[ -d "$TREE/.git" ] || die "$TREE is not a git checkout; the reference patch needs git apply"

OPENWRT_TAG=$(git -C "$TREE" describe --tags --exact-match 2>/dev/null || true)
OPENWRT_HEAD=$(git -C "$TREE" rev-parse HEAD)
if [ "$OPENWRT_TAG" != "v25.12.5" ] && [ "$OPENWRT_HEAD" != "$OPENWRT_EXPECTED_COMMIT" ]; then
	die "PZ-L8 support is pinned to OpenWrt v25.12.5 (tree is ${OPENWRT_TAG:-$OPENWRT_HEAD})"
fi

fetch_pinned() {
	local repo=$1 rev=$2 dir=$3 label=$4
	local have=

	if [ ! -d "$dir/.git" ]; then
		mkdir -p "$dir"
		git -C "$dir" init -q
		git -C "$dir" remote add origin "$repo" 2>/dev/null || true
	fi
	have=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)
	if [ "$have" != "$rev" ]; then
		# GitHub accepts fetching a reachable SHA in most cases. Fall back to
		# a normal fetch if the shallow-by-SHA request is rejected.
		git -C "$dir" fetch -q --depth=1 origin "$rev" ||
			git -C "$dir" fetch -q origin
		git -C "$dir" checkout -q --detach "$rev"
	fi
	have=$(git -C "$dir" rev-parse HEAD)
	[ "$have" = "$rev" ] || die "$label: expected $rev, got $have"
	say "$label @ $rev"
}

say "== PZ-L8: fetching pinned reference trees =="
fetch_pinned "$PZ_REF_REPO" "$PZ_REF_COMMIT" "$REF_DIR" "mufeng05/openwrt-cmcc-pz-l8-nss"
fetch_pinned "$HONK_REPO" "$HONK_COMMIT" "$GITHUB_WORKSPACE/.pz-l8-honk" "kenzok8/openwrt-honk"
fetch_pinned "$WALL_REPO" "$WALL_COMMIT" "$GITHUB_WORKSPACE/.pz-l8-wall" "kenzok8/wall"

say "== PZ-L8: applying the reference NSS tree =="
bash "$REF_DIR/scripts/setup.sh" "$TREE"

say "== PZ-L8: installing this repository's overlay and zram defaults =="
install -d "$TREE/files"
cp -a "$SRC_ROOT/device/pz-l8/root/." "$TREE/files/"
find "$TREE/files/etc/uci-defaults" -type f -exec chmod 0755 {} + 2>/dev/null || true
find "$TREE/files/etc/init.d" -type f -exec chmod 0755 {} + 2>/dev/null || true

# Keep the workflow's SSID/key convention while preserving the reference
# project's MAC-suffix behaviour on first boot.
WIRELESS="$TREE/files/etc/config/wireless"
WIFI_UCI="$TREE/files/etc/uci-defaults/97-pzl8-wifi-ssid"
SSID_BASE=${WRT_SSID:-OWRT}
WIFI_KEY=${WRT_WORD:-12345678}
sed_escape() {
	printf '%s' "$1" | sed 's/[\/\\&|]/\\&/g'
}
SSID_ESC=$(sed_escape "$SSID_BASE")
KEY_ESC=$(sed_escape "$WIFI_KEY")
if [ -f "$WIRELESS" ]; then
	sed -i \
		-e "s/option ssid 'PZ-L8-2G'/option ssid '${SSID_ESC}-2G'/" \
		-e "s/option ssid 'PZ-L8-5G'/option ssid '${SSID_ESC}-5G'/" \
		-e "s/option key 'pzl8test2026'/option key '${KEY_ESC}'/g" \
		"$WIRELESS"
fi
if [ -f "$WIFI_UCI" ]; then
	sed -i \
		-e "s/PZ-L8-2G/${SSID_ESC}-2G/g" \
		-e "s/PZ-L8-5G/${SSID_ESC}-5G/g" \
		"$WIFI_UCI"
fi

say "== PZ-L8: installing honk and geo data packages =="
install -d "$TREE/package/honk" "$TREE/package/luci-app-honk" \
	"$TREE/package/v2ray-geodata"
cp -a "$GITHUB_WORKSPACE/.pz-l8-honk/honk/." "$TREE/package/honk/"
cp -a "$GITHUB_WORKSPACE/.pz-l8-honk/luci-app-honk/." "$TREE/package/luci-app-honk/"
cp -a "$GITHUB_WORKSPACE/.pz-l8-wall/v2ray-geodata/." "$TREE/package/v2ray-geodata/"

say "== PZ-L8: resolving the minimal config =="
install -m 0644 "$SRC_ROOT/Config/PZ-L8.txt" "$TREE/.config"
if [ -n "${WRT_PACKAGE:-}" ]; then
	printf '%s\n' "$WRT_PACKAGE" >> "$TREE/.config"
fi

JOBS=$(nproc 2>/dev/null || echo 2)
make -C "$TREE" defconfig -j"$JOBS"
bash "$SRC_ROOT/Scripts/verify-pz-l8-config.sh" "$TREE/.config"

mkdir -p "$GITHUB_WORKSPACE/build-reports"
cat > "$GITHUB_WORKSPACE/build-reports/pz-l8-sources.txt" <<EOF
openwrt        openwrt/openwrt
openwrt_tag    v25.12.5
openwrt_commit $OPENWRT_HEAD
pz_l8_ref      mufeng05/openwrt-cmcc-pz-l8-nss
pz_l8_commit   $PZ_REF_COMMIT
honk           kenzok8/openwrt-honk
honk_commit    $HONK_COMMIT
v2ray_geodata  kenzok8/wall
geo_commit     $WALL_COMMIT
EOF

if [ -n "${GITHUB_ENV:-}" ]; then
	{
		echo "PZ_L8_REF_COMMIT=$PZ_REF_COMMIT"
		echo "HONK_COMMIT=$HONK_COMMIT"
		echo "V2RAY_GEODATA_COMMIT=$WALL_COMMIT"
	} >> "$GITHUB_ENV"
fi

echo "apply-pz-l8: ready"
