# 知识库 · GDI/IDD 合成面采集兼容（微信二维码白窗）经验总结

> 对应修复：v2.2.1（诊断记录 `docs/zc-v2.0.4-dxgi-fallback-plan.md`，
> 实现 `src/compat_display.rs` + `video_service.rs` / `portable_service.rs` 薄钩子）。
> 本文总结**机制结论**与**踩坑清单**，供后续采集类改动直接复用。

## 1. 机制结论（全部实机实测，GPU-P 虚拟机 / Intel UHD 730 虚拟化输出）

1. **双 bug 模型**：
   - Bug1：DXGI 恢复预算只在 10s 窗口内累计 3 次重试；驱动每 ~30s 丢一次
     `ACCESS_LOST` 时窗口过期清零 → 无限重建 DXGI、远程冻结/空白。
     修复＝跨窗口连丢计数（无成功帧即钉 GDI）。
   - Bug2：GDI 屏幕 DC 读不到**硬件合成路径**上的窗口内容（微信登录二维码白窗）。
2. **可读性取决于合成路径，而合成路径取决于活动输出类型**：
   活动输出为软件间接显示（IDD：usbmmidd / OrayIddDriver / RustDeskIdd）时，
   DWM 合成面 **GDI 全可读**；物理 GPU 输出时硬件 scanout/overlay 路径 GDI 盲。
3. **IDD 下仅 GDI 面可读，DXGI duplication 仍盲**（v2.2.1 验收实锤）：
   IDD 激活后 GDI 屏幕 DC 抓微信 darkpx 862 有码，同期 DXGI 采集的远程画面仍白窗。
   ⇒ 兼容拓扑生效期间**必须把采集钉住 GDI**（`is_enabled() && !is_gdi() → set_gdi()`）。
4. **合成路径残留不免疫重启**：IDD 引起的 mode change 会把既有窗口踢入可读路径且
   看似持久（拔 IDD 后旧窗口仍有码），但**在物理输出上重启微信即重新落白窗路径**。
   ⇒ 修复必须保持 IDD 在场，不做自动拔除/恢复。
5. **向日葵"一开就有码"同机制**：其 IDD 接管主显示 → 合成面可读；不是它"破解"了微信。
6. **clone 标签 ≠ 物理屏镜像**：GPU-P 上 clone staging/apply 可被接受
   （日志 `compat display enabled: Clone`），但实际生效拓扑仍为 IDD 唯一主显示
   （物理输出脱离、分辨率跟随原主显示）。可读性结论以 IDD 主显示为准。

## 2. 采集回退的隐蔽路径（钩子必须全覆盖）

- scrap `dxgi::Capturer::new` 内 D3D11/duplicate 失败时**静默**回退 GDI
  （仅 `println!`，服务进程 stdout 丢弃 → 日志无痕）→ `is_gdi()` 出生即真。
- 帧中途 `DuplicateOutput` 重建失败也会静默 `set_gdi()` 并返回 `WouldBlock` 吞错。
- 服务形态下 `video_service` 可能拿到**共享内存 IPC capturer**，其 `is_gdi()` 是
  恒真 stub；真实采集循环在 `portable_service` 宿主侧 ⇒ 钩子要落在真实循环，
  且 video_service 侧用 `!last_portable_service_running` 排除 stub。
- 权限：安装版 `--server` 以 **SYSTEM、session 1** 运行（GetOwner 实测），
  装驱动/plug/改拓扑都有权限；日志目录在 LocalService profile 不代表令牌。
- **断连会被上游拔监视器**：`connection.rs` 连接关闭调 `reset_all()` → amyuni
  监视器被拔、拓扑回物理输出；`--server` 是 per-session 进程，同进程内重连若靠
  `ENABLED` 早退就没人重插 ⇒ `ensure_async` 必须每次复查拓扑、被拔后重插。

## 3. 踩坑清单（构建 / 部署 / 验收）

- **Git Bash × msiexec**：`//l*v` 双斜杠不被 MSYS 还原 → 客户端卡参数校验、
  引擎不启动、日志空。须 `MSYS_NO_PATHCONV=1` + 单斜杠开关。
- **MSI 日志 UTF-16**：`iconv -f UTF-16LE` 后再读；时间戳易误读，进程 StartTime 对照。
- **build.py 硬编码相对 `target/` 检查**：不能用 `CARGO_TARGET_DIR`，用 junction
  `target → 共享缓存目录`。
- **打包噪声不入库**：`flutter/pubspec.lock`、`res/msi/*`（preprocess 写 BuildDir/
  BuildDate）、`libs/portable/app_metadata.toml` 均为 CI 再生噪声，出包后还原/删除。
- **配置只填空不覆盖**：老线播种的 `api-server`/打洞开关升级后仍在，须手动清
  （两个 profile），清理前备份；见 `kb/zcdesk-login-token-oss-server-deadlock.md`。
- **GDI 抓取假阳性**：窗口遗留坐标超出桌面时屏外黑边被计入 darkpx → 先
  `SetWindowPos` 移窗入屏再抓（`test/probe-qr.py` 已内置）。
- **验收要看真实生效拓扑**：`EnumDisplayDevices` ACTIVE + `ENUM_CURRENT_SETTINGS`
  （`test/probe-topo.py`），不要信日志标签 alone。
- **flutter 桥接**：本仓库不跑 codegen 的 CI 再生文件不入库；本地开发可手跑
  `flutter_rust_bridge_codegen`（需 rustfmt 组件 + `flutter pub get` 走镜像）。

## 4. 回归与验收入口

- 单元：`bash test/run-regression-tests.sh`（7 个，spaced 测试 master 上 fail 已实锤）。
- 交付：`bash test/verify-windows.sh`（安装/版本串/配置干净/连接被控端，四条全 PASS）。
- 采集：`bash test/verify-capture.sh`（compat 触发链/钉 GDI/生效拓扑/微信二维码像素）。