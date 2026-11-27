# DPD-FW-WRT

在 [VIKINGYFY/OpenWRT-CI](https://github.com/VIKINGYFY/OpenWRT-CI) 基础上做的
ImmortalWrt 云编译：大部分目标使用上游 `VIKINGYFY/immortalwrt`，本仓库只加
eBPF 数据面（`ebpf/`）、少量构建期改动和 X86/RK 的专属 UI/插件。
**PZ-L8 例外**：它的 NSS 板级支持只能建立在官方 `openwrt/openwrt@v25.12.5`
加 `mufeng05/openwrt-cmcc-pz-l8-nss` 的固定 commit 上，使用独立工作流。

数据面本身（DPD、einat、honk p1 core）在 **[kwrum1/dpd-fw](https://github.com/kwrum1/dpd-fw)**
编译发布，本仓库只下载产物。

## 型号

| 工作流 | 配置 | 源码分支 | 数据面 | 说明 |
|---|---|---|---|---|
| `EBPF-WRT-ALL` | `X86` | `owrt` | DPD TC/eBPF + einat + honk p1 core | 专属 UI（`luci-app-ebpf`）、ACL/QoS/多 WAN 等插件 |
| `QCA-PPE` | `IPQ60XX` / `IPQ807X`（WIFI-YES/NO） | `owrt` | 内核 flowtable / PPE | 原版包、原版 honk |
| `QCA-NSS` | 同上四个配置 | `main` | `qca-nss-drv` / ECM | 原版包、原版 honk |
| `PZ-L8` | `PZ-L8` | `openwrt/openwrt@v25.12.5` | QSDK NSS / ECM | 板级支持来自 `mufeng05/openwrt-cmcc-pz-l8-nss`；只装 honk/dae + zram + luci-light |
| `MTK-ALL` | `MEDIATEK`（WIFI-YES/NO） | `owrt` | 原版 | 原版包、原版 honk |
| `RASPBERRYPI` | `RASPBERRYPI-3` / `-4` / `-5` | `owrt` | 原版 | 原版包、原版 honk；手动运行时可单选型号 |
| `ROCKCHIP` | `ROCKCHIP` | `owrt`（手动可选） | DPD TC/eBPF + einat + honk p1 core | 与 X86 同一套 eBPF 栈；手动运行时可改源码/分支/LAN IP |
| `WRT-TEST` | 任选 | 任选 | 按配置 | 手动单型号/只出 `.config` |

ROCKCHIP 构建在上游 armv8 设备之外额外加入了 **NSY G68-PLUS**
（RK3568 + RTL8367S DSA 交换机）。板级 DTS、U-Boot defconfig、内核补丁，
以及上游 `02_network` 中的网口/MAC 映射，都放在 `device/nsy-g68-plus/`，
由 `Scripts/apply-nsy-g68.sh` 在构建期以锚点方式接入上游树；只对
`WRT_CONFIG=ROCKCHIP` 生效，锚点缺失会直接失败。

**PZ-L8** 是独立的 NSS 构建，不走 `WRT-CORE`：CMCC PZ-L8（IPQ5018 +
QCA8337 + QCN6122）的板级、QSDK NSS 驱动和 256 MB pbuf 调优来自
`mufeng05/openwrt-cmcc-pz-l8-nss`。工作流把官方 OpenWrt `v25.12.5` 与该
项目的固定 commit 一起使用，并只保留 `honk` / `luci-app-honk`、LuCI 轻量
组件、`zram-swap` 和必要的 NSS/WiFi 包。具体取舍见 `docs/pz-l8.md`。

IPQ53XX / IPQ95XX 的配置保留但不在矩阵里：上游 `kmod-ath12k` 的依赖在
`owrt`/`main` 上都未满足，镜像组装会失败。

## 发布形式

- 每个平台一个 release，tag 为 `dpd-fw-wrt-<CONFIG>-<构建时间>`，例如
  `dpd-fw-wrt-X86-26.11.10-06.12.01`。
- 固件文件名同样以 `dpd-fw-wrt-` 开头，带目标、wifi 变体和时间：
  `dpd-fw-wrt-immortalwrt-x86-64-generic-squashfs-combined-none-26.11.10-06.12.01.img.gz`。
- 每个 release 附带 `provenance-<CONFIG>.txt`：源码提交、配置、内核、clang/libbpf；
  X86/ROCKCHIP 另含 eBPF ABI、BPF 对象哈希与源码树哈希、einat 资产名。

## 触发

| 方式 | 行为 |
|---|---|
| 定时 | `Auto-Clean` 每周二、周五 04:00（北京时间）清空旧 release/tag/artifacts/运行记录，完成后通过 `workflow_run` 触发全部构建（含 `PZ-L8`） |
| 手动 | Actions → 选工作流 → Run workflow；`WRT-TEST` 可只出配置（`TEST=true`） |
| 检查类 CI | 全部在 `kwrum1/dpd-fw`：`ci`（编译 BPF/dpdctl）、`upstream`（补丁锚点）、`sdk`（出四个 apk）、`einat`、`honk-core` |

## 目录

```
Config/              各型号的 defconfig 片段
device/              非上游设备的板级文件（目前为 NSY G68-PLUS）
device/pz-l8/        PZ-L8 的 zram/运行期 overlay
ebpf/                数据面包（X86/ROCKCHIP 专用）：router-dataplane、einat-ebpf、LuCI
patches/honk/        X86/RK 的 honk 包源码补丁（core 由 dpd-fw 构建）
Scripts/             Packages.sh / Handles.sh / Settings.sh
.github/workflows/   薄工作流 + 公用核心 WRT-CORE.yml
```

## 维护

- honk：`X86/ROCKCHIP` 用上游包 + `patches/honk/honk-x86rk.patch` + `kwrum1/dpd-fw` 的
  `core-p1`；`IPQ/MTK` 用原版。补丁只带本项目改动的那部分，上游漂移会在 `Packages.sh` 直接报错。
- einat：二进制来自 `kwrum1/dpd-fw` 的 `einat-p2` release，哈希写死在
  `ebpf/einat-ebpf/Makefile`；返回码/回归由 dpd-fw 的 `einat` 工作流保证。
- 构建缓存包含 `.ccache`、`staging_dir/host*`、`staging_dir/tool*`；离线/弱网环境
  可把 `dl/` 里已有的源码包保留下来，`make download` 会直接复用、不再下载。
