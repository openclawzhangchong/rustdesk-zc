# 更新日志 · 智策远控 (zcdesk)

基于 [RustDesk 1.5.1](https://github.com/rustdesk/rustdesk) 二次开发。
作者：张翀 · 智策AI研发团队 · 官网：[zcdesk.jiuyeke.cn](https://zcdesk.jiuyeke.cn)

---

## v2.0.0（自主版本线起步 + 版本号显著化）

> **版本线重编说明**：从本版起，智策远控自主版本号从 **v2.0.0** 起步，与上游 RustDesk 的 1.5.1 彻底区隔——
> 此前的 v1.0.x 线废止（v1.0.7 构建内容与本版相同，仅版本号不同）。
> **交付物文件名全部改用自主版本号**（如 `zcdesk-2.0.0-x86_64.exe`），不再出现上游 1.5.1 字样。

### 新增

- **交付物命名切换**：CI 产物文件名从上游版本号改为自主版本号（PRODUCT_VERSION），
  桌面/手机一眼分清新旧

### 新增

- **产品版本号显著上首页**：
  - Android：顶栏应用名旁直接显示 `智策远控 v2.0.0`，连接/设置两页常驻可见
  - Windows：主窗口标题旁显示版本徽标（悬停显示完整版本信息）
  - Windows：底部状态栏"就绪"旁常驻版本号
- 窗口标题、关于页中的版本号同步跟随（沿用既有机制）

### 修复（服务端 worker-api，客户端无需升级即生效）

- 登录框打开即 404 红字：Worker 缺 `GET /api/login-options` 端点（客户端拉第三方登录列表），
  已补，返回空列表 = 仅账号密码登录
- 无法注册账号：客户端没有注册界面，Worker 原先只验证不建号——改为**首次登录自动注册**
  （密码下限 4 位；要收紧时在 D1 预建账号并把自动注册分支改回 401）

### 版本纪律（从此固定）

- **自己的产品版本号逐版递增**（v2.0.0 → v2.0.1 → …），每次有交付物的改动必升一版，
  与上游 RustDesk 版本号（1.5.1，Cargo.toml）刻意分开、互不影响
- 修改位置三处同步：`flutter/lib/consts.dart` 的 `kZcProductVersion`、
  `flutter-build.yml` env 块的 `PRODUCT_VERSION`、GitHub Release tag

## v1.0.6-beta（账号登录 + 地址簿云同步，测试版）

### 新增

- 自建 API 服务器上线：`https://zcdeskapi.jiuyeke.cn`
- **账号登录**：主界面 / 设置中的账号入口恢复可用，支持注册、登录，登录态跨端同步
- **地址簿云同步**：地址簿（AB）条目随账号云端存储，多设备（Android / Windows）自动同步，
  不再只存本机

### 客户端改动

- 种子配置注入 `api-server` 选项（仅空时填充，用户手动改过则保留），指向
  `https://zcdeskapi.jiuyeke.cn`；客户端原生协议不变
- 移除出厂硬设置 `disable-ab=Y` / `disable-account=Y`——这两项原本为无 API 的自建环境
  隐藏了地址簿与账号入口，API 上线后必须放开才能看到登录 / 通讯录入口
  （`disable-group-panel` 保留，群组面板暂不开放）

### 说明

- 本版本为**测试版（beta）**，登录与同步功能仍在验证中
- API 服务端由 worker-api 独立部署，接口协议见 `rustdesk-selfhost/docs/13-login-api-design.md`

## v1.0.5-outgoing（Android 单向版）

### Android APK 阉割为「纯控制器」

> **本 APK 只能去控制别人，永远不能被别人控制。**

- `conn-type=outgoing` 硬设置（RustDesk 官方连接模式）：被控服务启动函数直接死循环——
  不注册 ID、不监听端口、不接受任何入站连接。**手机上不存在远程后门。**
- 界面移除「你的桌面 / 本机 ID / 一次性密码」整块，只剩"控制远程桌面"
- 移除被控端专用组件与权限：
  - 无障碍输入服务（InputService，注入触摸 = 被控）
  - 开机自启（BootReceiver）
  - 录屏前台服务类型（mediaProjection）
  - 麦克风前台服务类型与录音权限（microphone / RECORD_AUDIO）
  - 悬浮窗权限（SYSTEM_ALERT_WINDOW）
  - 开机自启权限（RECEIVE_BOOT_COMPLETED）
- 包名脱离 RustDesk 信誉黑名单：`com.carriez.flutter_hbb` → `cn.jiuyeke.zcdesk`

**附带收益**：远控类 App 被安全软件标记的主因就是"被控能力"（录屏 + 无障碍注入 + 后台常驻）。
单向模式从设计上排除这些能力，误报率显著降低。

**注意**：本包 applicationId 为 `cn.jiuyeke.zcdesk`，与旧版（com.carriez.flutter_hbb）**不兼容覆盖**——
安装新版前请先卸载旧版。

### 实测记录（2026-11-14，USB 真机验证）

- 安装后启动正常，无闪退（修复了命名空间迁移导致的 JNI 符号失配崩溃）
- 实机截图确认：界面只有「远程 ID」输入框，无本机 ID/密码区，单向模式生效
- 真实连接测试通过：手机 → 控制电脑（ID 386073487），用户手动确认成功
- 厂商安全检测：新包未触发"包含病毒"判定（对比旧包的 MTscam 高风险标记）

### 修复

- Android 签名改用 apksigner 直签（此前第三方签名 action 的空值判断失效导致签名被跳过，产出 debug 签名包）
- workflow_call 显式声明 secrets + 调用方 `secrets: inherit`（Android 签名密钥此前无法透传到构建）

### Windows

- vcpkg 工具链改走自托管通道（VPS），LLVM 改用 conda-forge，构建对 GitHub CDN 故障免疫
- 引擎下载失败自动降级原版引擎（非致命）

---

## v1.0.1（Windows 品牌化 + 汉化安装器）

- 应用名/版权/版本信息全面品牌化（智策远控 · 智策AI研发团队）
- MSI 安装器简体中文（zh-CN 单文化构建）
- 自有中文许可协议替换上游隐私政策
- 隐藏 Powered by 字样与登录/通讯录/群组入口
- teal 配色主题
- 构建依赖去 GitHub 化（LLVM=conda-forge、vcpkg 工具=VPS 自托管），对 GitHub CDN 故障免疫

## v1.0（首个交付版）

- Windows x64 MSI + 便携版
- 默认服务器三件套内置（零配置接入）
- 中文安装向导
