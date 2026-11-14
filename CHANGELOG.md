# 更新日志 · 智策远控 (zcdesk)

基于 [RustDesk 1.5.1](https://github.com/rustdesk/rustdesk) 二次开发。
作者：张翀 · 智策AI研发团队 · 官网：[zcdesk.jiuyeke.cn](https://zcdesk.jiuyeke.cn)

---

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
