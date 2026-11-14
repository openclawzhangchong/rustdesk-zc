#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 智策远控 API 烟测脚本（契约：rustdesk-selfhost/docs/13-login-api-design.md）
#
# 流程：注册测试用户 -> 登录 -> 拉空簿 -> 推送 -> 拉回比对 -> 错误口令 401
#
# 用法：
#   1) 本地（先另开终端跑 `npx wrangler dev --local`）：
#        bash test/api-tests.sh
#   2) 远端：
#        BASE_URL=https://zcdeskapi.jiuyeke.cn bash test/api-tests.sh
#
# 可用环境变量：
#   BASE_URL     服务地址，默认 http://127.0.0.1:8787（wrangler dev 默认端口）
#   TEST_USER    测试用户名（手机号或字母数字），默认 13800000001
#   TEST_PASS    测试口令（>=4 位，纯数字可），默认 123456
#   PROVISION    1=自动注册测试用户（默认，仅本地模式）；0=跳过注册
#   WRANGLER     wrangler 命令，默认自动探测（wrangler 或 npx wrangler）
#   PERSIST_DIR  wrangler 本地状态目录；若 wrangler dev 用了 --persist-to，
#                这里传同一个目录，保证 d1 execute --local 读写同一个库
#
# 说明：远端模式下登录/注册接口可自给自足（服务端支持首登自动注册与显式注册），
#       本地模式仍通过 wrangler d1 execute 直接写 users 表完成预置
#       （PBKDF2-SHA256 / 10 万迭代 / 随机盐，与 Worker 算法一致）。
# ---------------------------------------------------------------------------
set -u

BASE_URL="${BASE_URL:-http://127.0.0.1:8787}"
TEST_USER="${TEST_USER:-13800000001}"
TEST_PASS="${TEST_PASS:-123456}"
PROVISION="${PROVISION:-1}"
PERSIST_DIR="${PERSIST_DIR:-}"

WORKER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DB_NAME="${DB_NAME:-intern-db}"  # 与 wrangler.toml 的 d1_databases.database_name 一致

command -v curl >/dev/null || { echo "需要 curl"; exit 1; }
command -v node >/dev/null || { echo "需要 node"; exit 1; }

WRANGLER="${WRANGLER:-}"
if [ -z "$WRANGLER" ] && command -v wrangler >/dev/null 2>&1; then
  WRANGLER="wrangler"
fi
if [ -z "$WRANGLER" ]; then
  WRANGLER="npx --yes wrangler"
fi

case "$BASE_URL" in
  http://127.0.0.1:*|http://localhost:*|http://[::1]:*|https://127.0.0.1:*|https://localhost:*) IS_LOCAL=1 ;;
  *) IS_LOCAL=0 ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BODY="$WORK/body"

PERSIST_ARGS=()
if [ -n "$PERSIST_DIR" ]; then
  mkdir -p "$PERSIST_DIR"
  PERSIST_ARGS=(--persist-to "$PERSIST_DIR")
fi

FAILURES=0
STEP=0

check() { # check <说明> <期望> <实际>
  if [ "$2" = "$3" ]; then
    echo "  PASS  $1"
  else
    echo "  FAIL  $1  期望=[$2] 实际=[$3]"
    FAILURES=$((FAILURES + 1))
  fi
}

next_step() { STEP=$((STEP + 1)); echo "[$STEP] $1"; }

# 从 JSON 文件取字段（点号路径），缺失输出 <<missing>>，非法 JSON 输出 <<badjson>>
jsonget() {
  node -e '
    const fs = require("fs");
    let o;
    try { o = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
    catch (e) { console.log("<<badjson>>"); process.exit(0); }
    let v = o;
    for (const k of process.argv[2].split(".")) {
      if (v == null) { v = undefined; break; }
      v = v[k];
    }
    if (v === undefined || v === null) console.log("<<missing>>");
    else if (typeof v === "object") console.log(JSON.stringify(v));
    else console.log(String(v));
  ' "$1" "$2"
}

# http <METHOD> <URL> <JSON体,可为空,支持 @file 传 UTF-8 文件> <Bearer token,可为空> -> STATUS / $BODY
# 含中文的请求体建议用 @file（node 写 UTF-8 文件），避免 Windows 下 curl.exe
# 按 ANSI 代码页转换命令行参数导致乱码
http() {
  local method="$1" url="$2" data="${3:-}" token="${4:-}"
  local args=(-s -o "$BODY" -w '%{http_code}' -X "$method" "$url")
  [ -n "$token" ] && args+=(-H "Authorization: Bearer $token")
  if [ -n "$data" ]; then
    args+=(-H "Content-Type: application/json" --data-binary "$data")
  else
    args+=(-H "Content-Length: 0")
  fi
  STATUS="$(curl "${args[@]}")"
}

echo "=== 智策远控 API 烟测 ==="
echo "BASE_URL = $BASE_URL"
echo "TEST_USER = $TEST_USER"
echo

# ---------------------------------------------------------------------------
# [0] 注册测试用户（本地模式直接写 D1；远端模式给出 SQL 提示）
# ---------------------------------------------------------------------------
SQL_FILE="$WORK/provision.sql"

# 用 node 生成注册 SQL：PBKDF2-SHA256 / 10 万迭代 / 32 字节哈希 / 16 字节随机盐（hex），
# 与 Worker 的 crypto.subtle 实现完全一致
cat > "$WORK/gen-user.js" <<'GENEOF'
const crypto = require("crypto");
const esc = (s) => s.replace(/'/g, "''");
const user = process.env.TU;
const pass = process.env.TP;
const salt = crypto.randomBytes(16);
const hash = crypto.pbkdf2Sync(pass, salt, 100000, 32, "sha256");
const id = crypto.randomUUID();
const now = Date.now();
const del = (t) =>
  "DELETE FROM " + t + " WHERE user_id IN (SELECT id FROM users WHERE username = '" + esc(user) + "');";
console.log(
  del("tokens") + "\n" +
  del("ab_personal") + "\n" +
  del("ab_settings") + "\n" +
  "DELETE FROM users WHERE username = '" + esc(user) + "';\n" +
  "INSERT INTO users (id, username, password_hash, salt, display_name, created_at) VALUES ('" +
  id + "', '" + esc(user) + "', '" + hash.toString("hex") + "', '" + salt.toString("hex") +
  "', '', " + now + ");"
);
GENEOF

TU="$TEST_USER" TP="$TEST_PASS" node "$WORK/gen-user.js" > "$SQL_FILE" || exit 1

if [ "$PROVISION" = "1" ]; then
  next_step "注册测试用户（写入 users 表）"
  if [ "$IS_LOCAL" = "1" ]; then
    if (cd "$WORKER_DIR" && $WRANGLER d1 execute "$DB_NAME" --local "${PERSIST_ARGS[@]}" --file "$SQL_FILE" --yes >/dev/null 2>&1); then
      echo "  PASS  测试用户已写入本地 D1"
    else
      echo "  FAIL  wrangler d1 execute --local 失败（确认 wrangler dev 已在 $WORKER_DIR 启动、PERSIST_DIR 与 dev 一致）"
      FAILURES=$((FAILURES + 1))
    fi
  else
    echo "  SKIP  远端模式不自动写库，请手动执行以下 SQL 后重跑："
    sed 's/^/        /' "$SQL_FILE"
    echo "        wrangler d1 execute $DB_NAME --remote --file <sql文件>"
  fi
else
  echo "[0] 跳过注册测试用户（PROVISION=0）"
fi
echo

# ---------------------------------------------------------------------------
# [1] 登录
# ---------------------------------------------------------------------------
next_step "登录（POST /api/login）"
http POST "$BASE_URL/api/login" "{\"username\":\"$TEST_USER\",\"password\":\"$TEST_PASS\"}"
check "HTTP 状态码" "200" "$STATUS"
TOKEN="$(jsonget "$BODY" access_token)"
check "access_token 存在" "0" "$(echo "$TOKEN" | grep -c '<<')"
check "type = access_token" "access_token" "$(jsonget "$BODY" type)"
check "user.name" "$TEST_USER" "$(jsonget "$BODY" user.name)"
check "user.display_name 字段存在" "0" "$(jsonget "$BODY" user.display_name | grep -c '<<')"
check "user.avatar 字段存在" "0" "$(jsonget "$BODY" user.avatar | grep -c '<<')"
check "user.status 字段存在" "0" "$(jsonget "$BODY" user.status | grep -c '<<')"
echo

# ---------------------------------------------------------------------------
# [2] 拉取空地址簿
# ---------------------------------------------------------------------------
next_step "拉取空地址簿（POST /api/ab/personal 空体）"
http POST "$BASE_URL/api/ab/personal" "" "$TOKEN"
check "HTTP 状态码" "200" "$STATUS"
GUID="$(jsonget "$BODY" guid)"
check "guid 已生成（UUID v4）" "1" "$(echo "$GUID" | grep -Ec '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')"
check "data 为空结构" '{"tags":[],"peers":[],"tag_colors":"{}"}' "$(jsonget "$BODY" data)"
echo

# ---------------------------------------------------------------------------
# [3] 推送地址簿（覆盖保存）
# ---------------------------------------------------------------------------
next_step "推送地址簿（POST /api/ab/personal 带 data 信封）"
INNER='{"tags":["zc测试标签"],"peers":["{\"id\":\"1000001\",\"name\":\"测试机器\"}"],"tag_colors":"{\"zc测试标签\":4284045345}"}'
# 用 node 生成 UTF-8 信封文件，curl 以 --data-binary @file 原样发送
ENVELOPE_FILE="$WORK/envelope.json"
node -e 'require("fs").writeFileSync(process.argv[1], JSON.stringify({data: process.argv[2]}), "utf8")' "$ENVELOPE_FILE" "$INNER"
http POST "$BASE_URL/api/ab/personal" "@$ENVELOPE_FILE" "$TOKEN"
check "HTTP 状态码（200 空体）" "200" "$STATUS"
check "响应为空体" "" "$(cat "$BODY")"
echo

# ---------------------------------------------------------------------------
# [4] 拉回比对
# ---------------------------------------------------------------------------
next_step "拉回比对（POST /api/ab/personal）"
http POST "$BASE_URL/api/ab/personal" "" "$TOKEN"
check "HTTP 状态码" "200" "$STATUS"
check "guid 不变" "$GUID" "$(jsonget "$BODY" guid)"
check "data.tags 与推送一致" '["zc测试标签"]' "$(jsonget "$BODY" data.tags)"
check "data.peers 数量" "1" "$(node -e 'const o=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(o.data.peers.length)' "$BODY")"
echo

# ---------------------------------------------------------------------------
# [5] 错误口令 -> 401
# ---------------------------------------------------------------------------
next_step "错误口令（POST /api/login）"
http POST "$BASE_URL/api/login" "{\"username\":\"$TEST_USER\",\"password\":\"wrong-pass\"}"
check "HTTP 状态码" "401" "$STATUS"
check "返回 error 字段" "0" "$(jsonget "$BODY" error | grep -c '<<')"
echo

# ---------------------------------------------------------------------------
# [6] 无 token / 伪造 token -> 401
# ---------------------------------------------------------------------------
next_step "无 token 访问（POST /api/ab/personal）"
http POST "$BASE_URL/api/ab/personal" ""
check "HTTP 状态码" "401" "$STATUS"

next_step "伪造 token 访问（POST /api/ab/personal）"
http POST "$BASE_URL/api/ab/personal" "" "faketoken-faketoken-faketoken"
check "HTTP 状态码" "401" "$STATUS"
echo

# ---------------------------------------------------------------------------
# [7] 其余契约端点抽查
# ---------------------------------------------------------------------------
next_step "legacy 兜底（GET /api/ab）"
http GET "$BASE_URL/api/ab" "" "$TOKEN"
check "HTTP 状态码" "200" "$STATUS"
check "响应为空列表" "[]" "$(cat "$BODY")"

next_step "共享簿占位（POST /api/ab/shared/profiles）"
http POST "$BASE_URL/api/ab/shared/profiles" "" "$TOKEN"
check "HTTP 状态码" "200" "$STATUS"
check "响应为空列表" "[]" "$(cat "$BODY")"

next_step "设置保存与读取（POST /api/ab/settings）"
http POST "$BASE_URL/api/ab/settings" '{"max_peer_one_ab":100}' "$TOKEN"
check "保存 HTTP 状态码（200 空体）" "200" "$STATUS"
http POST "$BASE_URL/api/ab/settings" "" "$TOKEN"
check "读取 HTTP 状态码" "200" "$STATUS"
check "读回设置" '{"max_peer_one_ab":100}' "$(cat "$BODY")"
echo

# ---------------------------------------------------------------------------
# [8] 登录选项列表（客户端登录框打开即拉）
# ---------------------------------------------------------------------------
next_step "登录选项（GET /api/login-options）"
http GET "$BASE_URL/api/login-options"
check "HTTP 状态码" "200" "$STATUS"
check "响应为空列表（无第三方登录）" "[]" "$(cat "$BODY")"

# ---------------------------------------------------------------------------
# [9] 显式注册：新用户 -> 200 + token；重复 -> 409；弱口令 -> 400
# ---------------------------------------------------------------------------
REG_USER="zc-reg-$(date +%s)"
next_step "显式注册新用户（POST /api/register）"
http POST "$BASE_URL/api/register" "{\"username\":\"$REG_USER\",\"password\":\"$TEST_PASS\"}"
check "HTTP 状态码" "200" "$STATUS"
check "access_token 存在" "0" "$(jsonget "$BODY" access_token | grep -c '<<')"
check "type = access_token" "access_token" "$(jsonget "$BODY" type)"
check "user.name" "$REG_USER" "$(jsonget "$BODY" user.name)"

next_step "重复注册（POST /api/register）"
http POST "$BASE_URL/api/register" "{\"username\":\"$REG_USER\",\"password\":\"$TEST_PASS\"}"
check "HTTP 状态码（用户名已存在）" "409" "$STATUS"

next_step "弱口令注册（POST /api/register）"
http POST "$BASE_URL/api/register" "{\"username\":\"zc-weak-$(date +%s)\",\"password\":\"123\"}"
check "HTTP 状态码（密码至少 4 位）" "400" "$STATUS"

# ---------------------------------------------------------------------------
# [10] 首登自动注册（远端自给自足的关键路径）
# ---------------------------------------------------------------------------
AU_USER="zc-auto-$(date +%s)"
next_step "首登自动注册（POST /api/login 未存在用户）"
http POST "$BASE_URL/api/login" "{\"username\":\"$AU_USER\",\"password\":\"$TEST_PASS\"}"
check "HTTP 状态码" "200" "$STATUS"
check "access_token 存在" "0" "$(jsonget "$BODY" access_token | grep -c '<<')"

echo "=== 完成：$((STEP)) 步，$FAILURES 个失败 ==="
exit $([ "$FAILURES" -eq 0 ] && echo 0 || echo 1)
