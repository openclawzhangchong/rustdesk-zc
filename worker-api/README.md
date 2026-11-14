# zcdesk-api —— 智策远控登录与地址簿云同步 API

Cloudflare Worker + D1 实现，端点/字段/Schema 严格按契约文档
`rustdesk-selfhost/docs/13-login-api-design.md` 实现。

```
worker-api/
├── wrangler.toml        # Worker 配置（name=zcdesk-api，D1 绑定 DB -> zcdesk-db）
├── schema.sql           # D1 建表语句（users / tokens / ab_personal / ab_settings）
├── src/index.js         # ES Module Worker（全部端点）
└── test/api-tests.sh    # curl 烟测脚本
```

## 端点一览

| 端点 | 说明 |
| --- | --- |
| `POST /api/login` | 登录，成功返回 `{access_token, type:"access_token", user:{name,display_name,avatar,status}}`；失败 401 `{error:"用户名或密码错误"}` |
| `POST /api/ab/personal` | 空体=拉取 `{guid, data}`（未推送过 data 为空结构）；带 `{"data":"<JSON字符串>"}` =覆盖保存，200 空体。guid 首次生成 UUIDv4 后固定 |
| `POST /api/ab` | 推送覆盖保存（同上信封，data 存 TEXT 原样不解析），200 空体 |
| `POST /api/ab/settings` | 带 JSON 体=保存设置（200 空体）；空体=读取当前设置（客户端 `_getAbSettings` 以空体 POST 读取，需返回 JSON 对象） |
| `POST /api/ab/shared/profiles` | MVP 不支持共享簿，固定 200 `[]` |
| `GET /api/ab` | legacy 兜底，固定 200 `[]` |

认证：`Authorization: Bearer <access_token>`；token 存 `tokens` 表，30 天过期；
失效一律 401 `{error:"..."}`。密码 PBKDF2-SHA256（crypto.subtle，10 万迭代）+ 16 字节
随机盐，只存 hex 哈希，绝不落明文。时间戳统一为 Unix 毫秒。

## 部署步骤

前置：node + npm；Cloudflare 账号；`jiuyeke.cn` 域名已托管在同账号 Cloudflare。
（若 npm 源不通：`npm config set registry https://registry.npmmirror.com`）

```bash
cd worker-api

# 1. 创建 D1 数据库，记下输出的 database_id，填入 wrangler.toml 的 database_id
npx wrangler d1 create zcdesk-db

# 2. 初始化表结构（远端）
npx wrangler d1 execute zcdesk-db --remote --file schema.sql

# 3. 部署 Worker（需 wrangler login 或环境变量 CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID）
npx wrangler deploy
```

## 创建用户（契约未定义注册接口）

用户由管理侧直接写入 D1（用户名：手机号或字母数字；密码 ≥4 位、纯数字可，只存哈希）。
用下面命令生成 SQL（PBKDF2-SHA256 / 10 万迭代 / 16 字节随机盐，与 Worker 一致）并执行：

```bash
node -e "
const crypto=require('crypto');
const [user,pass]=process.argv.slice(1);
const esc=s=>s.replace(/'/g,\"''\");
const salt=crypto.randomBytes(16);
const hash=crypto.pbkdf2Sync(pass,salt,100000,32,'sha256');
console.log(\"INSERT INTO users (id, username, password_hash, salt, display_name, created_at) VALUES ('\"+crypto.randomUUID()+\"', '\"+esc(user)+\"', '\"+hash.toString('hex')+\"', '\"+salt.toString('hex')+\"', '', \"+Date.now()+\");\");
" 13800000000 1234 > add-user.sql
npx wrangler d1 execute zcdesk-db --remote --file add-user.sql
```

## 自定义域绑定（zcdeskapi.jiuyeke.cn）

推荐在 Dashboard 操作（自动创建 DNS 记录与边缘证书）：

1. Cloudflare Dashboard -> Workers & Pages -> `zcdesk-api`
2. Settings -> Domains & Routes -> **Add** -> Custom domain
3. 填 `zcdeskapi.jiuyeke.cn` -> 保存，等证书生效（约 1~2 分钟）

或用 wrangler：取消 `wrangler.toml` 中 `routes = [{ pattern = "zcdeskapi.jiuyeke.cn", custom_domain = true }]`
的注释后 `npx wrangler deploy`。

验证：`curl https://zcdeskapi.jiuyeke.cn/api/ab` 应返回 `[]` 或 401 JSON。

客户端配套：api-server 选项 = `https://zcdeskapi.jiuyeke.cn`。

## 本地开发与烟测

```bash
# 终端 1（本地起 Worker + 本地 D1；状态默认落在 worker-api/.wrangler/，勿提交）
npx wrangler dev --local

# 终端 2：注册测试用户 -> 登录 -> 拉空簿 -> 推送 -> 拉回比对 -> 错误口令 401 -> 401 兜底
bash test/api-tests.sh
```

远端烟测：`BASE_URL=https://zcdeskapi.jiuyeke.cn bash test/api-tests.sh`（先按上文
手动写入测试用户 SQL，脚本会打印待执行语句）。若 `wrangler dev` 使用了
`--persist-to <目录>`，测试脚本请传同名环境变量 `PERSIST_DIR=<目录>`。

## 注意

- `wrangler.toml` 中 `database_id` 为占位符，部署前必须替换为真实值。
- 本地 `wrangler dev` / `d1 execute --local` 会在 `worker-api/.wrangler/` 生成状态目录，
  不要提交；也可用 `--persist-to` 指到仓库外。
- 代码与配置中不含任何真实密钥；deploy 凭据走 `CLOUDFLARE_API_TOKEN` 环境变量或
  `wrangler login`。
