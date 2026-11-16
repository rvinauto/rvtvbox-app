# gitpack — 两个项目「上传到 git 就自动编译」的包

一个可直接 `git init && git push` 的仓库，包含两套 GitHub Actions：
x86_64 runner 上编译，**不需要 qemu、不需要 arm64 宿主**。

| 目录 / 工作流 | 作用 | 耗时 |
|---|---|---|
| `xingchen/` + `build-xingchen-apk.yml` | 拉 XingChen 源码 @ `52450c04`，下载 mihomo/sherpa，出 **arm64 release APK** 并作为 artifact 上传 | 20–40 min |
| `webhtv/` + `build-webhtv-apk.yml` | 拉 fork @ `852d8428`，打上游 3 个修复补丁，出 **WebHTV 改进版 APK** | 20–40 min |
| `webhtv/` + `verify-webhtv-absorb.yml` | 同一套补丁，只编 Java 双 ABI + 跑 native 校验（快） | 8–15 min |

## 为什么不在本机编译

本机是 **arm64 VPS**，而 NDK 29 与 SDK CMake 3.22.1 只发 `linux-x86_64` 包。要在 arm64 上跑只能
`qemu-user-static` 包一层，代价是一连串环境坑（实测耗时 3 小时仍未出包）：

1. 真实 ELF 必须留在原目录（`$ORIGIN` 决定 `CMAKE_ROOT`、lld 的 libz、clang 资源目录）；
2. wrapper 必须用 `qemu-x86_64-static -0 <绝对路径>` 还原 argv[0]，否则 `lld is a generic driver`；
3. AAPT2 由 AGP 从 Maven 拉进 `~/.gradle/caches/**/transformed/`，得再包一遍；
4. 即使包完，`aapt2` 的 daemon 模式仍报 `Daemon startup failed`；
5. 且 qemu 下 `clang++` 不把 `-static-libstdc++` 展开成 `-lc++_static -lc++abi`，native 链接报
   `undefined symbol: operator new(unsigned long)` / `vtable for std::length_error`。

CI 的 runner 本来就是 x86_64，以上 5 条全部不存在 —— 这才是「在 git 里编译」的真正收益。

## 用法

```bash
git init && git add . && git commit -m "ci: build xingchen apk + verify webhtv absorb"
git remote add origin git@github.com:<you>/<repo>.git && git push -u origin main
```

推送后在 Actions 页手动触发 `build-xingchen-apk`，跑完在 run 页面底部下载 `xingchen-apk` artifact。

## 固定版本（可复现）

| 项 | 值 |
|---|---|
| XingChen 源码 | `XingChenApp/xingchen` @ `52450c0461659685425bd7f3deacd2e899d13a49` |
| webhtv fork | `Silent1566/webhtv` @ `852d8428`（`release/v5.6.0-beta-202611080849`） |
| Gradle | 9.5.1（wrapper 自带） |
| AGP | 9.2.1 |
| JDK | 21（JetBrains 21.0.3） |
| compileSdk | 37（实际包名 `android-37.0/37.1/37.2`，**没有** `android-37`） |
| build-tools | 37.0.0 |
| NDK | 29.0.14206865 |
| CMake | 3.22.1 |
| Python | 3.10（Chaquopy 17.0.0） |

两者工具链完全相同，所以同一个 SDK 安装步骤复用在两个 workflow 里。

## 目录

```
.github/workflows/build-xingchen-apk.yml
.github/workflows/verify-webhtv-absorb.yml
xingchen/scripts/build.sh          # 取源码 + 下依赖 + 临时签名 + 出包
webhtv/scripts/apply.sh            # 取 fork + git apply 补丁 + 双 ABI 编译（校验用）
webhtv/scripts/build-apk.sh        # 同上但出 APK（改进版）
webhtv/patches/                    # 3 个上游补丁 + 已解冲突的合并补丁
webhtv/docs/吸收方案.md             # 两个 webhtv 仓库的优点吸收方案
```

## 两个 APK 的区别（容易混）

- `build-xingchen-apk` 出的 APK 是**原版星辰播放器**（XingChen @ `52450c04`），一个字节的代码都没改，
  与官方发布版等价（仅 CI 临时签名、mihomo 内核现下）。它**不含**任何 webhtv 的改动。
- `build-webhtv-apk` 出的 APK 才是**吸收了上游修复的 WebHTV**：基线是 fork 的 1776 个提交功能主线，
  再叠加 pan 代理 jar 生命周期、ARMv7 libass 双 ABI、直播状态栏 inset 三处修复。

## 备注

- `mihomo`（Clash 内核，61MB）和 `sherpa-onnx.aar` 都不入库，由脚本按 sha256 现下；下载失败会降级并继续，
  不会阻塞出包（Clash 节点功能不可用而已）。
- 签名用 CI 临时 keystore，**仅供验证编译**，不能用于发布。
- `webhtv/patches/merged-all-3-upstream-fixes.patch` 是三个补丁的合并版（已解 `JarLoader` /
  `LiveActivity` / `docs` 三处冲突），`apply.sh` 用它（`git apply -3`）；单个补丁保留在同目录便于按需 cherry-pick。
