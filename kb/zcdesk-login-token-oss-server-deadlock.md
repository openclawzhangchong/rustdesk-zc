# 知识库 · 登录 token × OSS 服务器握手死锁（2026-11-15 事故）

> 本文是 CHANGELOG / README 铁律引用的完整教训记录。结论先行：
> **`access_token` 不是普通账号凭据，而是上游协议栈的全局开关；把它写进 RustDesk
> 本地配置命名空间，会把"独立登录功能"和"核心远程连接"耦合在一起并死锁。**

## 1. 现象

v2.0.x 线接入自建账号 API（CF Worker + D1）后，客户端登录成功即把上游
`access_token` 写入本地配置。随后**所有跨公网连接**失败：
`Connection closed: Failed to secure tcp: deadline`，约 18 秒超时。
同一机器未登录时连接正常；局域网个别场景看似正常，掩盖了问题。

## 2. 根因链

1. 上游协议栈在配置中存在 `access_token` 时，连接 ID 服务器（hbbs）会切到
   **新版 key_exchange 加密握手分支**：客户端**等服务器先发密钥**。
2. 自建 OSS 版 `rustdesk-server`（1.1.x）**没有 KeyExchange 能力**（源码 0 处），
   永远不会发密钥。
3. 客户端 `READ_TIMEOUT = 18s` 死等 → 超时 → `Failed to secure tcp: deadline`。
4. 于是"登录"这一个动作，通过上游埋好的全局状态，杀死了"连接"。

**D1/Worker 里存账号本身完全无害**；有害的是借用上游账户状态做载体。
耦合是上游早就埋好的、我们事先没有审计的。

## 3. 修复历程（版本对应）

- **v2.1.1**（fe8c33ba3）：secure 握手失败容忍降级——失败时警告 + 重连 socket +
  明文继续（端到端加密保持）。止血，但 token 仍在配置里，行为不可控。
- **v2.1.2**（bd8e8710f）：用户决策**账号登录整体移除**。seed 恢复
  `disable-ab` / `disable-account` 隐藏登录与地址簿入口，**移除 `api-server` 预置**；
  UI 成果（tab 中文文字、关于页重排）保留回归。
- **v2.2.1 部署附带清理**：老线播种遗留的 `api-server` 与实验性打洞开关
  （`enable-webrtc` / `enable-udp-punch` / `enable-ipv6-punch` = 'Y'）必须从
  **用户与 LocalService 两个 profile** 的配置中清除（seed 只填空、不覆盖既有值），
  否则 `test/verify-windows.sh` 第 3 步 FAIL。清理前先备份配置目录。

## 4. 铁律（永不撤销）

1. 将来若要做账号：**只能独立登录**——自有账号服务 + **自己独立的配置键**，
   或按设备 ID 存备注的平行服务；绝不写 `access_token` 等上游键。
2. `disable-account` / `disable-ab` 两个隐藏开关**不要移除**。
3. 任何新功能上线，验收清单第一条永远是
   **"原来能连的电脑还连不连得上"**（`test/verify-windows.sh` 第 4 步）。

## 5. 排查指纹

- 日志：`Failed to secure tcp: deadline` / `secure tcp with rendezvous server failed`
  （后者在 OSS 服务器上是降级告警，v2.1.1 起不影响连接）。
- 配置：`智策远控_local.toml` 出现 `access_token`；`智策远控2.toml` 出现 `api-server`。
- 对照实验：同一机器删除 token 前后各连一次，差异即实锤。