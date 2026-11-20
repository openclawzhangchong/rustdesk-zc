# v2.0.4 修复计划与诊断记录 · 远程画面间歇性空白 / 微信二维码看不见

状态：代码已实现、回归测试通过；zc-custom 线已部署二轮待验收。
**移植说明（2026-11-20）**：本修复已原样移植到产品线 `zc-v2.1.0`（v2.2.0 基线），
交付版本 **v2.2.1**（src 四文件与旧基线逐字一致，零冲突重放）；zc-custom 线的
v2.0.4 提交 b6f5ee781 留作历史、不发 Release。下文版本号/部署时间均指 zc-custom 线
的诊断与首轮/二轮部署过程，机制与回归面结论对 v2.2.1 同样适用。
作者：张翀 · 智策AI研发团队

## 1. 问题报告

用户报告：远程控制被控机时，被控机上微信客户端登录二维码在远程画面里"被屏蔽"
（白窗/空白），同一机器同一状态下向日葵远程能看到二维码。被控机为 GPU-P
虚拟机（Intel UHD Graphics 730 虚拟化输出），安装版智策远控 v2.0.3。

## 2. 双 bug 模型（均已实锤）

### Bug1：DXGI 恢复预算窗口缺陷 → 远程冻结/空白

- 位置：`src/server/video_service.rs` `DxgiRecoveryState`。
- 旧逻辑：只在 `DXGI_RECOVERY_WINDOW`（10s）内累计 3 次 `ACCESS_LOST` 重试才回退
  GDI；窗口过期即清零 `attempts`。
- 本机驱动行为：每隔约 30s 丢一次 DXGI 访问（`ACCESS_LOST` → `ConnectionReset`），
  窗口每次过期清零 → 日志无限循环 `dxgi access lost, restart capture: attempt 1`
  （安装版活日志 20:16:17–20:25:12 每 30s 一条），期间无帧 → 远程冻结/空白。
- 修复：新增跨窗口"连丢计数" `lost_streak`。两次间隔超窗的 access lost 之间没有
  任何成功帧即 `fallback_pending`（钉住 GDI）；成功送达一帧 `note_frame()` 清零。
  既有突发 3 次上限行为原样保留。

### Bug2：GDI 读不到硬件合成窗口内容 → 二维码白窗

- 现象：GDI 回退后远程仍白窗；GDI 屏幕 DC 抓微信登录窗 = 纯白，子窗
  `MMUIRenderSubWindowHW`（`WS_EX_LAYERED|WS_EX_TRANSPARENT`）PrintWindow = 纯黑。
- 本机采集路矩阵（Intel 物理输出活动时）：DXGI DuplicateOutput 同卡 device
  `0x80070005` / 周期性 ACCESS_LOST；WGC 窗口+监视器 0 帧；Magnification 全黑；
  PrintWindow 对 D3D 内容白/黑；GDI 屏幕 DC 能读 layered+flip swapchain 自制对照
  与 Electron 内容，**唯独读不到微信硬件渲染内容**。
- 因果实验（2026-11-18，用户授权"跑完整实验"，GDI 屏幕 DC 裁剪抓取，darkpx>500=有码）：

  | 步骤 | 拓扑 | 微信状态 | darkpx | 结论 |
  |---|---|---|---|---|
  | 1 | Intel-only 1440x900 主 | 重启后 | 70 | 白窗复现 |
  | 2 | 自带 usbmmidd 插入即主显示（Intel 自动脱离） | 不重启 | 2021 | 二维码可读 |
  | 3 | clone（Intel+usbmmidd 同位置同分辨率） | — | — | GPU-P 拒绝 clone（BADMODE，多组 devmode 参数均失败） |
  | 4 | 拔 usbmmidd 回 Intel 主 | 不重启 | 2098 | 二维码仍可读（合成路径已被踢入可读路径并persist） |
  | 5 | 卸载 usbmmidd 驱动 | — | — | 设备节点清除干净 |

- 机制结论：可读性取决于微信窗口 swapchain 创建/重建时落入的合成路径。活动输出为
  软件间接显示（IDD：OrayIddDriver / usbmmidd）时 DWM 走 GDI 可读合成面；为 GPU-P
  物理输出时走硬件 scanout/overlay 路径，GDI 盲。IDD 引起的 mode change 会把既有
  窗口踢入可读路径且持久；但"在 Intel 上重启微信"会重新落入白窗路径 → 修复必须
  保持 IDD 在场才免疫微信重启。向日葵"一开就有码"= 其 IDD 接管主显示，同机制。
- 抓取陷阱记录：窗口遗留 1920x1080 坐标超出 1440x900 桌面时，屏外黑边会被 darkpx
  误计为"有码"；抓取脚本须先把窗口移入屏内再计数。

## 3. 修复设计（纯增量）

### Bug1（video_service.rs）

- 常量 `DXGI_LOST_STREAK_LIMIT = 2`；`DxgiRecoveryState` 增 `lost_streak` 字段。
- `next_attempt()` 开头纯增量插入超窗连丢计数与 `fallback_pending` 判定；既有
  窗口/attempts 逻辑不动。
- 新增 `note_frame()`；Ok 帧分支 cfg(windows) 块加一行薄钩子调用。
- 既有 warn 文案改为 "burst or spaced losses" 以便诊断（唯一修改的既有行）。

### Bug2（新增 src/compat_display.rs + 10 处薄钩子）

- 触发（转换路径）：`video_service.rs` 四处 `c.set_gdi()`（恢复预算耗尽 / 选项禁用 DXGI /
  无帧回退 / DXGI 错误回退）各加一行 `crate::compat_display::ensure_async()`，
  全部位于既有 `#[cfg(windows)]` 块内。
- 触发（出生即 GDI / 中途静默 GDI，首轮部署验收揪出的缺口）：scrap 在
  `dxgi::Capturer::new` 内 D3D11/duplicate 失败时**静默**回退 GDI（仅 `println!`，
  无日志），`is_gdi()` 自创建起为真，上述四个 `!c.is_gdi()` 守卫全部落空。补三处：
  1. `video_service.rs` 启动 `gdi: {}` 日志处：`c.is_gdi() && !last_portable_service_running`
     → ensure_async（共享内存 IPC capturer 的 is_gdi 是恒真 stub，须排除，其真实采集
     循环在 portable_service 侧自有钩子）；
  2. `video_service.rs` WouldBlock 分支同守卫一行——覆盖 scrap 帧中途静默 set_gdi
     （mod.rs 内 DuplicateOutput 重建失败路径，返回 WouldBlock 吞掉错误）；
  3. `portable_service.rs` 宿主采集循环两处：Capturer::new 成功后 `v.is_gdi()`、
     帧错误分支 `is_gdi()==Some(true)`——覆盖便携宿主模式（video_service 侧拿到的
     是 stub，钩子必须落在真实采集循环）。
- 权限实测：安装版服务形态下真实采集进程 `--server` 以 **SYSTEM、session 1** 运行
  （Win32_Process GetOwner 实测），SetupAPI 装驱动 / ioctl plug / 改拓扑均有权限；
  日志目录在 LocalService _profile 只是配置目录选择，不代表令牌。
- **钉住 GDI（v2.2.1 实机验收揪出的最后一环）**：拓扑生效后可读的是 **GDI 合成面
  _only_**——DXGI duplication 读 scanout，仍不含硬件 flip 窗口内容（实测：IDD 激活后
  GDI 屏幕 DC 抓微信 darkpx 862 有码，而同期 DXGI 采集的远程画面仍白窗）。故 compat
  ENABLED 期间采集必须钉住 GDI：`video_service.rs` 帧循环与 `portable_service.rs`
  宿主循环各加一处 `is_enabled() && !is_gdi() → set_gdi()` 薄钩子（video_service 侧
  另加 `!last_portable_service_running` 守卫排除 IPC stub）。健康机器 ENABLED 恒假
  → 零影响（测试 `compat_disabled_by_default_so_healthy_capture_stays_dxgi` 锁定）。
- **断连重插（v2.2.1 验收第二坑）**：`connection.rs` 连接关闭调
  `virtual_display_manager::reset_all()` 会把我们插的 amyuni 监视器拔掉；`--server`
  是 per-session 进程，但同进程内重连时旧 `ENABLED=true` 曾让 `ensure_async` 直接
  返回 → 拓扑回 Intel、再次白窗。现 `ensure_async` 改为每次复查拓扑
  （ENABLED 且间接显示仍活动才早退），被拔后自动重插；Skip（向日葵等已活动）也置
  ENABLED → 同样钉 GDI 保证可读。
- `ensure_async()`：原子 ENABLED/RUNNING 守卫，后台线程执行，不阻塞采集线程。
- `ensure()`：
  1. 不支持虚拟显示的 Windows 版本 → bail（健康旧系统零影响）。
  2. 已有任何间接显示活动（DeviceString 含 `IddDriver` / `Virtual Display`，覆盖
     向日葵遗留、RustDeskIdd、usbmmidd）→ Skip，不动拓扑。
  3. 复用 `virtual_display_manager::plug_in_monitor`（amyuni 分支：deviceinstaller64
     或 SetupAPI 安装自带签名 usbmmidd + ioctl plug）。
  4. 轮询等待 usbmmidd 活动（≤10s）；再等 3.5s——amyuni plug 会 spawn 线程把新监视器
     重置 1920x1080，须等其结束再 staging，否则 clone 模式被覆盖。
  5. 策略 `plan_topology(false, clone_stage_ok)`：先试 clone（物理主显示当前模式 +
     IDD 同分辨率同位置 staging）；两路 staging 均成功 → apply（物理屏保持镜像）。
     clone 被拒（GPU-P 等）→ IDD 设主显示（本机验证分支：Intel 自动脱离，整桌面
     迁到 IDD，GDI 全可读）。
  6. 成功后 ENABLED=true，服务生命周期内钉住；Skip 不置 ENABLED（后续回退可复查）。
- 不做自动恢复/拔除：保持 IDD 在场才免疫微信重启（实验步骤 4 的 persist 只是
  合成路径残留，微信重启即失效）。
- 健康机器：DXGI 正常 → 永不触发 → 零拓扑副作用。

## 4. 回归测试（cargo test --locked --release --lib --features "hwcodec,vram"）

结果：7 passed（Bug1 三新 + 1 既有 + Bug2 两策略 + 1 默认关闭），0 failed。

Bug1（video_service::tests，cfg(windows)）：
1. `spaced_access_lost_falls_back_to_gdi`：超窗连丢 → next_attempt()=None 且
   fallback_pending。**master 上返回 Some(1) → fail**（已用 stash 验证计划，见 §6）。
2. `delivered_frame_keeps_dxgi_recovery_available`：note_frame 后间隔丢仍 Some(1)。
3. `burst_recovery_limit_unchanged`：Some(1)/Some(2)/Some(3)/None+fallback 不变。

Bug2（compat_display::tests）：
4. `active_indirect_display_skips_compat_topology`：间接显示已活动 → Skip。
5. `clone_preferred_with_idd_primary_fallback`：clone 优先、被拒回退 IDD 主显示。
   （master 无此模块 → 编译期 fail。）
6. `compat_disabled_by_default_so_healthy_capture_stays_dxgi`：ENABLED 默认假 →
   钉 GDI 钩子在健康机器上不触发。

## 5. 回归面报告

- 采集主路：DXGI 正常机器不进入任何新代码路径（lost_streak 只在超窗丢失时累加；
  compat 只在 GDI 回退/出生即 GDI 时触发，健康机器 is_gdi()=false 且共享内存 stub
  被守卫排除）。突发 3 次重试上限由测试 3 锁定。
- GDI 回退机器：新增后台拓扑线程；最坏情况安装/插入失败仅 warn 日志，采集维持
  原 GDI 行为（不劣化）。
-  headless / 隐私模式 /  peer 虚拟显示：compat 见间接显示已活动即 Skip，不与
  `virtual_display_manager` 既有 headless/peer 管理争抢；未活动时 plug 复用同一
  amyuni 计数与锁。
- 显示拓扑副作用仅限"GDI 回退且无间接显示"的受影响机器：一次闪屏；clone 成功则
  物理屏镜像不变画面，clone 被拒则主显示切到 IDD（GPU-P 虚拟机上物理输出自动脱离，
  已验证；真实物理屏机器 clone 几乎总被 WDDM 支持）。
- 非 Windows：模块与钩子均 cfg(windows)，零影响。
- 版本面：Cargo.toml 保持上游 1.5.1；产品版本三处同步 v2.0.4
  （flutter/lib/consts.dart kZcProductVersion、.github/workflows/flutter-build.yml
  PRODUCT_VERSION、CHANGELOG）。

## 6. 验证与交付步骤

1. [x] Bug1 修复 + 3 测试通过（4 passed 含 1 既有）。
2. [x] 因果实验闭环（§2 矩阵），用户授权并选定"自动兼容采集"方案。
3. [x] Bug2 实现 + 2 策略测试。
4. [x] fail-on-master 复核：master 版 video_service.rs + spaced 测试 →
   `left: Some(1), right: None` 断言失败（FAILED, exit 101）；恢复修复版后字节一致。
5. [x] 重建 exe/msi：codegen（补 rustfmt 组件 + flutter pub get 镜像）→
   build.py --portable --flutter --skip-portable-pack --hwcodec --vram →
   package-v204.sh。产物 D:\_zc_build\SignOutput-v204\zcdesk-2.0.4-x86_64.exe/.msi。
   构建坑记录：build.py 硬编码相对 target/ 检查 → 用 junction 指向共享缓存；
   打包对 pubspec.lock/res/msi/app_metadata.toml 的改写为 CI 再生噪声，已还原不入库。
6. [x] 首轮部署（11:09 静默 MSI）验收发现 born-GDI 缺口：服务日志 `gdi: true`
   自创建起、无任何 set_gdi/compat 日志 → 四钩子全落空（scrap 创建内静默回退）。
   补 §3 三处钩子 → 6 测试复跑 passed → 重建/重打包（11:34）→ 二轮静默 MSI
   （19:15，MainEngineThread 0，服务 Running，dll=11:31 构建）→ 待用户重连验收：
   远程见微信二维码；微信重启后仍见；日志出现 compat display enabled。
   部署坑：Git Bash 下 `msiexec //l*v` 双斜杠不被 MSYS 还原 → 客户端卡参数校验、
   引擎不启动；须 `MSYS_NO_PATHCONV=1` + 单斜杠。
7. [ ] 提交（含本计划文档、CHANGELOG、README）+ tag v2.0.4。

## 7. 已知限制

- clone 分支已实测（v2.2.1，2026-11-20）：GPU-P 上 clone staging/apply 被接受
  （日志 `compat display enabled: Clone`），但**实际生效拓扑**仍为 IDD 唯一主显示
  （Intel 物理输出脱离，分辨率跟随原主显示 1440x900）；GDI 面可读实测 darkpx 862。
  即 clone 标签不代表物理屏镜像在本驱动上成立，可读性结论以 IDD 主显示为准。
- 真实物理屏机器若 clone 被拒且物理输出不自动脱离，IDD 主显示为扩展空桌面——
  该组合（物理屏 + 拒绝 clone + DXGI _flaky_）未见实例，接受为限制。
- 实验后本机 Oray IDD 节点处于 pending reboot（向日葵侧 plug 状态丢失），配置层
  无法恢复 Oray 主显示；用户选定保持现状（Intel 主显示、二维码可读），下次自然
  重启清除 pending 标记。