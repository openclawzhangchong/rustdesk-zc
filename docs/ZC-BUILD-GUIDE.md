# 智策远控 云端打包完全指南

> 本文是**唯一权威**的打包说明。下次重启云端打包，照本文逐条执行即可顺畅出包。
> 最后验证：2026-11-16，v2.2.0 出包成功（run 43803630080，Windows x64 成功）。

---

## 一、30 秒版（日常发版就这三步）

```bash
# 1. 改版本号（两处，必须同步）
#    flutter/lib/consts.dart            -> const kZcProductVersion = 'v2.2.1';
#    .github/workflows/flutter-build.yml -> PRODUCT_VERSION: "2.2.1"

# 2. 提交推送（分支必须 zc-v2.1.0，不要用 master）
git add -A && git commit -m "feat(v2.2.1): ..." && git push origin zc-v2.1.0

# 3. 派发云端构建（tag 与版本号一致）
gh workflow run zc-build.yml -R openclawzhangchong/rustdesk-zc \
  --ref zc-v2.1.0 -f upload-tag=v2.2.1
```

出包后：Release 页面自动出现 `zcdesk-<ver>-x86_64.exe` + `.msi`，下载到桌面即可交付。

---

## 二、前置条件（重启打包前必须确认）

| 检查项 | 要求 | 不满足会怎样 |
|---|---|---|
| **仓库可见性** | **必须 Public** | 私密仓库 Actions 配额用尽后，job 会 `steps:[]` 3 秒失败、日志 BlobNotFound，runner 根本不启动 |
| 分支 | `zc-v2.1.0` | 用 master 会带上下游无关代码，连接行为不可控 |
| 版本号两处一致 | `consts.dart` 与 `PRODUCT_VERSION` | 主页显示与实际产物名不符 |
| Release tag | 与版本号一致（如 v2.2.1） | 产物混在旧 tag 里，分不清 |
| 工作流输入 | `build-android` 默认 false | 只出 Windows；需要 Android 显式传 `-f build-android=true` |

> 若仓库当前是私密（配额已恢复想省公开），**打包前必须临时转公开**，出包验收后再转回。

---

## 三、工作流结构与参数

`zc-build.yml`（入口）→ 调用 `flutter-build.yml`（上游工作流，已做 ZC 定制）

```yaml
# zc-build.yml 输入参数
upload-tag:     # Release tag，与产品版本号一致，如 v2.2.1
build-android:  # 布尔，默认 false（Windows-only 交付）
```

`flutter-build.yml` 里的 ZC 关键定制（勿动）：

| 位置 | 内容 | 作用 |
|---|---|---|
| `env.PRODUCT_VERSION` | 交付物版本号 | 决定文件名 `zcdesk-<ver>-<arch>.ext` |
| `env.VERSION` | `1.5.1`（上游基线） | **仅用于二进制 `--version` 自检**，不参与命名 |
| Windows 打包步骤（571/595 行附近） | `zcdesk-${{ env.PRODUCT_VERSION }}-...` | exe/msi 命名 |
| Android job（1532/1836 行） | `if: inputs.build-android != false` | Android 门控 |
| `res/msi` 模板 | **zc 定制版**（zh-CN 单文化，Codepage 936） | 中文产品名编译 |

---

## 四、常见失败与修法（按出现频率排序）

### 1. 失败但 `steps: []`、3 秒结束、日志 BlobNotFound
**原因**：仓库私密 + Actions 配额耗尽，runner 未启动。
**修法**：`gh repo edit <repo> --visibility public --accept-visibility-change-consequences`，重新派发。

### 2. `error WIX0311: characters not available in code page '1252'`
**原因**：`res/msi` 混入了上游新版模板（1252 码页），中文品牌名（智策远控）编译失败。
**修法**：确认 `res/msi/Package/Language/` 只有 `Package.zh-CN.wxl` 和 `WixExt_zh-CN.wxl`，
且 `Product.wxs` 的 `Package/@Codepage` 为 936。**不要把官方 1.5.1 的 res/msi 整体覆盖回来。**

### 3. `No named parameter with the name 'loginMethod'`（或类似 Flutter 编译错误）
**原因**：`flutter/lib/` 里混入了依赖非官方 Rust 桥的调用（历史遗留：另一台机器的管理员审批登录系列）。
**修法**：`git checkout 1.5.1 -- flutter/lib/` 回官方，再单独重打需要的 UI 补丁。

### 4. `libvpx`/`libaom` 等 vcpkg 端口 504
**原因**：GitHub 归档下载不稳。
**修法**：已内置 `X_VCPKG_ASSET_SOURCES` x-script 镜像回退，通常自动恢复；反复失败则重跑。

### 5. i686 / aarch64 Windows job 失败
**定性**：**非交付物**（32 位与 ARM64 Windows），一直失败，**忽略即可**。
判断方法：只要 `x86_64-pc-windows-msvc` 是 success，交付物就齐了。

### 6. 整个 run 显示 failure 但 x64 success
**原因**：上述 i686/aarch64 失败拉低了整体结论。
**修法**：**不用修**，只看 x64 job 的 conclusion。

---

## 五、出包后验收清单（必跑）

```bash
# 一条命令跑完：装包 → 版本串 → 配置检查 → 连接验收
bash test/verify-windows.sh                          # 用桌面最新 msi
bash test/verify-windows.sh path/to/xxx.msi          # 指定包
PEER_ID=253375647 bash test/verify-windows.sh        # 指定被控端
```

脚本会检查：

1. 安装成功、Windows 服务「智策远控」为 Running
2. `data/app.so` 内版本串为当前版本、**无旧版本残留**（v1.0.7/v2.0.x/v2.1.0~v2.1.2）
3. 配置无 `access_token`、无 `api-server`、无 `enable-webrtc`/`enable-udp-punch`/`enable-ipv6-punch` 强制开启
4. 连接被控端后窗口标题含目标 ID、日志无 `Failed to secure tcp`

**四条全 PASS 才算交付**。任何一条 FAIL 都不许把包发给用户。

---

## 六、交付动作

1. 把 `zcdesk-<ver>-x86_64.exe` 和 `.msi` 复制到桌面（**不要删任何旧包**）
2. 更新 README 的「✅ 当前稳定版」区块（版本号 + 交付物名 + 已验证项）
3. CHANGELOG 增加该版本条目
4. 若版本重要，追加 `handoff/` 交接单
5. **旧 Release / 旧安装包一律保留**（铁律，见 README）

---

## 七、从零开始重建云端打包（极端情况）

如果改了什么导致工作流坏了，回到已知可用状态：

```bash
# 工作流本身回滚到最近可用提交（不要整体回官方，会丢 ZC 定制）
git log --oneline -10 -- .github/workflows/flutter-build.yml .github/workflows/zc-build.yml
git checkout <可用提交> -- .github/workflows/

# 分支基线确认（必须是官方 1.5.1 tag + ZC 补丁）
git log --oneline -3
git merge-base --is-ancestor 23e5bb471 HEAD && echo "基线正确"
```

**关键不可丢的 ZC 定制清单**（回滚后逐项核对）：
- [ ] `zc-build.yml` 存在且 `secrets: inherit`
- [ ] `flutter-build.yml`：`PRODUCT_VERSION` 环境变量 + 47 处产物命名已切换
- [ ] `flutter-build.yml`：`build-android` 门控
- [ ] `res/msi`：zh-CN 单文化（Codepage 936）
- [ ] `src/common.rs`：`zc_seed_default_server()`（品牌名/服务器/key，**不含 api-server、不含实验开关**）
- [ ] `flutter/lib/consts.dart`：`kZcProductVersion`
- [ ] 版本号三处主页显示（标题徽标 / 状态栏 / 手机顶栏）

---

## 八、时间参考（实测）

| 阶段 | 耗时 |
|---|---|
| 门禁 + generate-bridge + 引擎替换 | 8~12 分钟 |
| vcpkg 依赖 | 15~25 分钟 |
| Rust 编译（x64） | 25~35 分钟 |
| MSI 打包 + 上传 | 3~5 分钟 |
| **总计** | **45~55 分钟**（Windows-only） |

若超过 70 分钟仍无进展，检查是否卡在 vcpkg（下载）或 Rust 编译（内存），拉日志看 `##[error]`。
