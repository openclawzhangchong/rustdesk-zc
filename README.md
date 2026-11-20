# 智策远控 · zcdesk

> 开源远程桌面，开箱即连。基于 [RustDesk 1.5.1](https://github.com/rustdesk/rustdesk) 二次开发。
> 作者：张翀 · 智策AI研发团队 · 官网：[zcdesk.jiuyeke.cn](https://zcdesk.jiuyeke.cn)

> [!WARNING]
> ## 🚫 项目铁律：千万不能走上游的登录
>
> **本项目将来若要做账号/登录功能，必须是完全独立的自研实现，绝对禁止复用、
> 触发或写入任何 RustDesk 上游的账户状态（尤其是 `access_token`）。**
>
> 原因（2026-11-15 事故，完整教训见 `CHANGELOG.md` 与知识库
> `zcdesk-login-token-oss-server-deadlock.md`）：
> - `access_token` 不是普通账号凭据，而是**上游协议栈的全局状态**。只要它出现在客户端
>   本地配置里，上游就会在连接 ID 服务器时切到"加密握手"分支，**等服务器先发密钥**
>   （`READ_TIMEOUT=18s` 死等）。
> - 自建 OSS 版 `rustdesk-server`（1.1.x）**没有这个能力**（源码 0 处 KeyExchange），
>   于是所有跨公网连接必然超时死锁（`Failed to secure tcp: deadline`）。
> - **D1/Worker 存账号本身完全无害，有害的是把 token 写进上游的配置命名空间**——
>   这一个动作把"独立的登录功能"和"最核心的远程连接"耦合在了一起，
>   而耦合是上游早就埋好的、我们事先没有审计的。
>
> **因此**：
> 1. 现在：登录/地址簿云同步入口已隐藏（`disable-account`/`disable-ab`），
>    `api-server` 不再预置，客户端永远走"未登录"的干净连接路径。**不要移除这两个开关。**
> 2. 将来若要做账号：只能做**独立登录**——自己的账号服务 + **自己独立的配置键**
>    （绝不写 `access_token` 等上游键），或按设备 ID 存备注的平行服务，
>    绝不触碰上游登录状态。
> 3. 任何新功能上线前，验收清单**第一条永远是"原来能连的电脑还连不连得上"**，
>    先跑通这条回归，再谈新功能。
>
> ## 📦 附：Release 历史资产铁律
>
> **任何 Release / tag / 历史安装包，一律不删、不覆盖、不"清理"。**
> 每个 tag 是独立的历史记录：旧的是旧的，新的是新的，新旧靠版本号区分，
> **绝不靠删除旧包来"避免混淆"**。
> 既往教训：曾删除 v1.0.7 / v2.0.2 / v2.1.0 等 Release，导致
> `v1.0.2-local`（本地构建版）等旧安装包永久找不回。
> 以后如需标注某版"有缺陷/已取代"，在 CHANGELOG 里写清楚即可，资产保留。

---

## ✅ 当前稳定版

| 项 | 值 |
|---|---|
| **稳定版版本** | **v2.2.4** |
| 交付物 | `zcdesk-2.2.4-x86_64.msi`（安装器）、`zcdesk-2.2.4-x86_64.exe`（便携版） |
| 平台 | Windows x64（Android 需显式传 `build-android=true`） |
| Release | `v2.2.4` |
| 已验证 | 安装 ✓ 主页版本号可见 ✓ 连接被控端 ✓ 配置干净 ✓ 采集自愈 ✓ 向日葵式主页+品牌蓝青+月亮/太阳双钮双向实测+作者署名 ✓ |

> **分不清版本怎么办**：程序主页有三处版本号——标题旁徽标、底部状态栏「就绪 vX.Y.Z」、
> 手机顶栏应用名后。看一眼就知道装的是哪版。

> 📦 **打包流程**：见 [docs/ZC-BUILD-GUIDE.md](docs/ZC-BUILD-GUIDE.md)
> ——云端 CI 一键派发、参数说明、常见失败与修法、出包后验收清单，全部固化在仓库里。

## 智策远控定制能力

- **品牌化**：智策远控中文名 + ZC logo + teal 配色；中文安装向导（zh-CN 单文化 MSI）
- **零配置接入**：ID/中继/Key 编译时内置，安装即可用（仅空时播种，不覆盖用户修改）
- **Android 单向客户端**：只能控人、不能被控（`conn-type=outgoing`），无远程后门
- **自主版本线 v2.x**：与上游 1.5.1 区隔；主页三处版本号常驻（标题徽标/状态栏/手机顶栏）
- **主页方案 B**：左侧分组导航 + 在线/离线筛选 + 设备卡片渐变头图；tab 中文文字标签
- **向日葵式主页（v2.2.2）**：白色导航 rail + 圆角选中态；本机识别码大黑字卡 +
  远程协助卡（模式下拉 + 连接按钮）；布局酷似向日葵、美术自有
- **品牌配色 + 昼夜切换（v2.2.3/v2.2.4）**：蓝→青品牌族（与 logo 一致）+ 冷灰中性色；
  导航 rail 月亮/太阳并排双钮一键浅↔深（选中高亮、与设置同步）；rail 底部署名「作者：张翀」
- **采集自愈（v2.2.1）**：DXGI 跨窗口连丢自动钉 GDI，修远程画面间歇性冻结/空白；
  GDI 读不到硬件合成窗口（微信登录二维码白窗）时自动启用自带签名虚拟显示兼容采集，
  并在兼容生效期间钉住 GDI、断连后自动重插；健康机器零影响
- **独立登录铁律**：绝不走上游登录（见顶部铁律与知识库）

## 测试与知识库

| 入口 | 内容 |
|---|---|
| [test/README.md](test/README.md) | 常用测试/验收脚本索引（交付四条、采集五条、单元回归 7 个、二维码/拓扑探针） |
| [kb/zcdesk-gdi-idd-capture-compat.md](kb/zcdesk-gdi-idd-capture-compat.md) | 采集兼容机制结论 + 构建/部署/验收踩坑清单 |
| [kb/zcdesk-login-token-oss-server-deadlock.md](kb/zcdesk-login-token-oss-server-deadlock.md) | 登录 token × OSS 握手死锁事故完整教训 |
| [docs/zc-v2.0.4-dxgi-fallback-plan.md](docs/zc-v2.0.4-dxgi-fallback-plan.md) | 采集修复诊断记录：实验矩阵、回归面、部署坑（v2.2.1 移植说明在内） |
| [handoff/v2.2.1-handoff.md](handoff/v2.2.1-handoff.md) | v2.2.1 交接单：验收证据、部署清理、复验清单、已知限制 |

<p align="center">
  <img src="res/logo-header.svg" alt="RustDesk - Your remote desktop"><br>
  <a href="#raw-steps-to-build">Build</a> •
  <a href="#how-to-build-with-docker">Docker</a> •
  <a href="#file-structure">Structure</a> •
  <a href="#screenshots">Screenshots</a><br>
  [<a href="docs/README-UA.md">Українська</a>] | [<a href="docs/README-CS.md">česky</a>] | [<a href="docs/README-ZH.md">中文</a>] | [<a href="docs/README-HU.md">Magyar</a>] | [<a href="docs/README-ES.md">Español</a>] | [<a href="docs/README-FA.md">فارسی</a>] | [<a href="docs/README-FR.md">Français</a>] | [<a href="docs/README-DE.md">Deutsch</a>] | [<a href="docs/README-PL.md">Polski</a>] | [<a href="docs/README-ID.md">Indonesian</a>] | [<a href="docs/README-FI.md">Suomi</a>] | [<a href="docs/README-ML.md">മലയാളം</a>] | [<a href="docs/README-JP.md">日本語</a>] | [<a href="docs/README-NL.md">Nederlands</a>] | [<a href="docs/README-IT.md">Italiano</a>] | [<a href="docs/README-RU.md">Русский</a>] | [<a href="docs/README-PTPT.md">Português (Portugal)</a>] | [<a href="docs/README-PTBR.md">Português (Brasil)</a>] | [<a href="docs/README-EO.md">Esperanto</a>] | [<a href="docs/README-KR.md">한국어</a>] | [<a href="docs/README-AR.md">العربي</a>] | [<a href="docs/README-VN.md">Tiếng Việt</a>] | [<a href="docs/README-DA.md">Dansk</a>] | [<a href="docs/README-GR.md">Ελληνικά</a>] | [<a href="docs/README-TR.md">Türkçe</a>] | [<a href="docs/README-NO.md">Norsk</a>] | [<a href="docs/README-RO.md">Română</a>]<br>
  <b>We need your help to translate this README, <a href="https://github.com/rustdesk/rustdesk/tree/master/src/lang">RustDesk UI</a> and <a href="https://github.com/rustdesk/doc.rustdesk.com">RustDesk Doc</a> to your native language</b>
</p>

> [!Caution]
> **Misuse Disclaimer:** <br>
> The developers of RustDesk do not condone or support any unethical or illegal use of this software. Misuse, such as unauthorized access, control or invasion of privacy, is strictly against our guidelines. The authors are not responsible for any misuse of the application.


Chat with us: [Discord](https://discord.gg/nDceKgxnkV) | [Twitter](https://twitter.com/rustdesk) | [Reddit](https://www.reddit.com/r/rustdesk) | [YouTube](https://www.youtube.com/@rustdesk)

[![RustDesk Server Pro](https://img.shields.io/badge/RustDesk%20Server%20Pro-Advanced%20Features-blue)](https://rustdesk.com/pricing.html)

Yet another remote desktop solution, written in Rust. Works out of the box with no configuration required. You have full control of your data, with no concerns about security. You can use our rendezvous/relay server, [set up your own](https://rustdesk.com/server), or [write your own rendezvous/relay server](https://github.com/rustdesk/rustdesk-server-demo).

![image](https://user-images.githubusercontent.com/71636191/171661982-430285f0-2e12-4b1d-9957-4a58e375304d.png)

RustDesk welcomes contribution from everyone. See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for help getting started.

[**FAQ**](https://github.com/rustdesk/rustdesk/wiki/FAQ)

[**BINARY DOWNLOAD**](https://github.com/rustdesk/rustdesk/releases)

[**NIGHTLY BUILD**](https://github.com/rustdesk/rustdesk/releases/tag/nightly)

[<img src="https://f-droid.org/badge/get-it-on.png"
    alt="Get it on F-Droid"
    height="80">](https://f-droid.org/en/packages/com.carriez.flutter_hbb)
[<img src="https://flathub.org/api/badge?svg&locale=en"
    alt="Get it on Flathub"
    height="80">](https://flathub.org/apps/com.rustdesk.RustDesk)

## Dependencies

Desktop versions use Flutter or Sciter (deprecated) for GUI. This tutorial is for Sciter only, since it is easier and more friendly to start. Check out our [CI](https://github.com/rustdesk/rustdesk/blob/master/.github/workflows/flutter-build.yml) for building the Flutter version.

Please download Sciter dynamic library yourself.

[Windows](https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.win/x64/sciter.dll) |
[Linux](https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.lnx/x64/libsciter-gtk.so) |
[macOS](https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.osx/libsciter.dylib)

## Raw Steps to build

- Prepare your Rust development env and C++ build env

- Install [vcpkg](https://github.com/microsoft/vcpkg), and set `VCPKG_ROOT` env variable correctly

  - Windows: vcpkg install libvpx:x64-windows-static libyuv:x64-windows-static opus:x64-windows-static aom:x64-windows-static
  - Linux/macOS: vcpkg install libvpx libyuv opus aom

- run `cargo run`

## [Build](https://rustdesk.com/docs/en/dev/build/)

## How to Build on Linux

### Ubuntu 18 (Debian 10)

```sh
sudo apt install -y zip g++ gcc git curl wget nasm yasm libgtk-3-dev clang libxcb-randr0-dev libxdo-dev \
        libxfixes-dev libxcb-shape0-dev libxcb-xfixes0-dev libasound2-dev libpulse-dev cmake make \
        libclang-dev ninja-build libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

### openSUSE Tumbleweed

```sh
sudo zypper install gcc-c++ git curl wget nasm yasm gcc gtk3-devel clang libxcb-devel libXfixes-devel cmake alsa-lib-devel gstreamer-devel gstreamer-plugins-base-devel xdotool-devel
```

### Fedora 28 (CentOS 8)

```sh
sudo yum -y install gcc-c++ git curl wget nasm yasm gcc gtk3-devel clang libxcb-devel libxdo-devel libXfixes-devel pulseaudio-libs-devel cmake alsa-lib-devel gstreamer1-devel gstreamer1-plugins-base-devel
```

### Arch (Manjaro)

```sh
sudo pacman -Syu --needed unzip git cmake gcc curl wget yasm nasm zip make pkg-config clang gtk3 xdotool libxcb libxfixes alsa-lib pipewire
```

### Install vcpkg

```sh
git clone https://github.com/microsoft/vcpkg
cd vcpkg
git checkout 2023.04.15
cd ..
vcpkg/bootstrap-vcpkg.sh
export VCPKG_ROOT=$HOME/vcpkg
vcpkg/vcpkg install libvpx libyuv opus aom
```

### Fix libvpx (For Fedora)

```sh
cd vcpkg/buildtrees/libvpx/src
cd *
./configure
sed -i 's/CFLAGS+=-I/CFLAGS+=-fPIC -I/g' Makefile
sed -i 's/CXXFLAGS+=-I/CXXFLAGS+=-fPIC -I/g' Makefile
make
cp libvpx.a $HOME/vcpkg/installed/x64-linux/lib/
cd
```

### Build

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
git clone --recurse-submodules https://github.com/rustdesk/rustdesk
cd rustdesk
mkdir -p target/debug
wget https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.lnx/x64/libsciter-gtk.so
mv libsciter-gtk.so target/debug
VCPKG_ROOT=$HOME/vcpkg cargo run
```

## How to build with Docker

Begin by cloning the repository and building the Docker container:

```sh
git clone https://github.com/rustdesk/rustdesk
cd rustdesk
git submodule update --init --recursive
docker build -t "rustdesk-builder" .
```

Then, each time you need to build the application, run the following command:

```sh
docker run --rm -it -v $PWD:/home/user/rustdesk -v rustdesk-git-cache:/home/user/.cargo/git -v rustdesk-registry-cache:/home/user/.cargo/registry -e PUID="$(id -u)" -e PGID="$(id -g)" rustdesk-builder
```

Note that the first build may take longer before dependencies are cached, subsequent builds will be faster. Additionally, if you need to specify different arguments to the build command, you may do so at the end of the command in the `<OPTIONAL-ARGS>` position. For instance, if you wanted to build an optimized release version, you would run the command above followed by `--release`. The resulting executable will be available in the target folder on your system, and can be run with:

```sh
target/debug/rustdesk
```

Or, if you're running a release executable:

```sh
target/release/rustdesk
```

Please ensure that you run these commands from the root of the RustDesk repository, or the application may not find the required resources. Also note that other cargo subcommands such as `install` or `run` are not currently supported via this method as they would install or run the program inside the container instead of the host.

## File Structure

- **[libs/hbb_common](https://github.com/rustdesk/rustdesk/tree/master/libs/hbb_common)**: video codec, config, tcp/udp wrapper, and some other utility functions shared with the server
- **[libs/base](https://github.com/rustdesk/rustdesk/tree/master/libs/base)**: protobuf, fs functions for file transfer, keyboard and platform code used only by this app
- **[libs/scrap](https://github.com/rustdesk/rustdesk/tree/master/libs/scrap)**: screen capture
- **[libs/enigo](https://github.com/rustdesk/rustdesk/tree/master/libs/enigo)**: platform specific keyboard/mouse control
- **[libs/clipboard](https://github.com/rustdesk/rustdesk/tree/master/libs/clipboard)**: file copy and paste implementation for Windows, Linux, macOS.
- **[src/ui](https://github.com/rustdesk/rustdesk/tree/master/src/ui)**: obsolete Sciter UI (deprecated)
- **[src/server](https://github.com/rustdesk/rustdesk/tree/master/src/server)**: audio/clipboard/input/video services, and network connections
- **[src/client.rs](https://github.com/rustdesk/rustdesk/tree/master/src/client.rs)**: start a peer connection
- **[src/rendezvous_mediator.rs](https://github.com/rustdesk/rustdesk/tree/master/src/rendezvous_mediator.rs)**: Communicate with [rustdesk-server](https://github.com/rustdesk/rustdesk-server), wait for remote direct (TCP hole punching) or relayed connection
- **[src/platform](https://github.com/rustdesk/rustdesk/tree/master/src/platform)**: platform specific code
- **[flutter](https://github.com/rustdesk/rustdesk/tree/master/flutter)**: Flutter code for desktop and mobile

## Screenshots

![Connection Manager](https://github.com/rustdesk/rustdesk/assets/28412477/db82d4e7-c4bc-4823-8e6f-6af7eadf7651)

![Connected to a Windows PC](https://github.com/rustdesk/rustdesk/assets/28412477/9baa91e9-3362-4d06-aa1a-7518edcbd7ea)

![File Transfer](https://github.com/rustdesk/rustdesk/assets/28412477/39511ad3-aa9a-4f8c-8947-1cce286a46ad)

![TCP Tunneling](https://github.com/rustdesk/rustdesk/assets/28412477/78e8708f-e87e-4570-8373-1360033ea6c5)

