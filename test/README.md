# test/ · 常用测试与验收脚本索引

| 脚本 | 用途 | 何时跑 |
|---|---|---|
| `verify-windows.sh` | 交付验收四条：安装 / 版本串无旧残留 / 配置干净 / 连接被控端 | **每次出包后必跑**，四条全 PASS 才算交付 |
| `verify-capture.sh` | 采集兼容五条：服务 / compat 触发链与钉 GDI / 生效拓扑 / 微信二维码像素 / 配置干净 | 采集类改动出包后、或用户报"画面白/二维码看不见"时 |
| `run-regression-tests.sh` | Rust 单元回归 7 个（Bug1 连丢回退 + Bug2 拓扑策略 + 默认关闭） | 每次改 `video_service.rs` / `compat_display.rs` / `portable_service.rs` 后 |
| `probe-qr.py` | 微信窗口 GDI 屏幕 DC 抓取 + darkpx 判定（0 有码 / 1 白窗 / 2 无窗口） | 单独复核二维码可读性；依赖 `pip install pillow psutil` |
| `probe-topo.py` | ACTIVE 显示设备快照（0 含间接显示 / 1 仅物理输出） | 复核真实生效拓扑，不要只信日志标签 |

## 约定

- 验收脚本退出码 0 = 通过（SKIP/NOTE 不算失败），非 0 = 有 FAIL。
- `verify-windows.sh` 第 4 步会**杀进程并发起一次 outgoing 连接**（默认被控端
  `PEER_ID=253375647`），会断开当前 incoming 远程会话——协调好时机再跑。
- `verify-capture.sh` 只读日志/拓扑/抓屏，**不断会话**，可随时重跑。
- 机制结论与踩坑清单见 `kb/zcdesk-gdi-idd-capture-compat.md`；
  登录 token 死锁教训见 `kb/zcdesk-login-token-oss-server-deadlock.md`。