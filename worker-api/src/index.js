/**
 * 智策远控 API Worker —— 登录 + 地址簿云同步（Cloudflare Worker + D1）
 *
 * 契约文档：rustdesk-selfhost/docs/13-login-api-design.md（所有端点、请求/响应
 * 字段、D1 Schema 严格按该文档实现）。
 *
 * 端点：
 *   POST /api/login            登录，返回 {access_token, type, user}
 *   POST /api/ab/personal      空体=拉取 {guid, data}；带 {data:"..."}=推送覆盖保存
 *   POST /api/ab               推送覆盖保存（{"data":"<JSON 字符串>"}，存 TEXT 原样）
 *   POST /api/ab/settings      空体=拉取设置；带 JSON 体=保存设置
 *   POST /api/ab/shared/profiles  MVP 不支持共享簿，固定返回 []
 *   GET  /api/ab               legacy 兜底，固定返回 []
 *
 * 认证：Authorization: Bearer <access_token>；token 存 D1 tokens 表，30 天过期。
 * 密码：PBKDF2-SHA256（crypto.subtle，10 万迭代），每用户随机盐，只存哈希（hex）。
 * 错误：一律 {error:"消息"}，不泄露内部细节。
 */

const PBKDF2_ITERATIONS = 100000;
const PASSWORD_HASH_BITS = 256;
const SALT_BYTES = 16;
const TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 天

// 客户端从未推送过地址簿时返回的空结构（契约第二节示例，tag_colors 为字符串）
const EMPTY_AB = { tags: [], peers: [], tag_colors: "{}" };

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
  "Access-Control-Max-Age": "86400",
};

// path -> 允许的 method（用于 405 判定）
const KNOWN_PATHS = {
  "/api/login": ["POST"],
  "/api/login-options": ["GET"],
  "/api/ab/personal": ["POST"],
  "/api/ab": ["GET", "POST"],
  "/api/ab/settings": ["POST"],
  "/api/ab/shared/profiles": ["POST"],
};

// ---------------------------------------------------------------------------
// 基础工具
// ---------------------------------------------------------------------------

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS_HEADERS },
  });
}

// 200 + 空体（客户端把 200+空体/字面 null 当成功）
function emptyResponse(status = 200) {
  return new Response(null, { status, headers: CORS_HEADERS });
}

function errorResponse(message, status) {
  return jsonResponse({ error: message }, status);
}

function bytesToHex(bytes) {
  let s = "";
  for (const b of bytes) s += b.toString(16).padStart(2, "0");
  return s;
}

function hexToBytes(hex) {
  const out = new Uint8Array(hex.length >> 1);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function randomHex(byteLength) {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return bytesToHex(bytes);
}

/** token = crypto.randomUUID() + 随机 hex（契约第一节） */
function newToken() {
  return crypto.randomUUID() + "-" + randomHex(16);
}

/** PBKDF2-SHA256（10 万迭代），返回 256 位哈希的 hex */
async function hashPassword(password, saltHex) {
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveBits"]
  );
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt: hexToBytes(saltHex), iterations: PBKDF2_ITERATIONS },
    keyMaterial,
    PASSWORD_HASH_BITS
  );
  return bytesToHex(new Uint8Array(bits));
}

// ---------------------------------------------------------------------------
// 认证
// ---------------------------------------------------------------------------

/** 校验 Bearer token，成功返回 user_id，失败返回 null */
async function authenticate(request, env) {
  const header = request.headers.get("Authorization") || "";
  const match = /^Bearer\s+(\S+)\s*$/i.exec(header);
  if (!match) return null;
  const row = await env.DB
    .prepare("SELECT user_id FROM tokens WHERE token = ? AND expires_at > ?")
    .bind(match[1], Date.now())
    .first();
  return row ? row.user_id : null;
}

// POST /api/login
async function handleLogin(request, env) {
  const raw = await request.text();
  let body;
  try {
    body = raw.trim() ? JSON.parse(raw) : null;
  } catch (e) {
    return errorResponse("请求格式错误", 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return errorResponse("请求格式错误", 400);
  }

  // 客户端 LoginRequest 还会带 id/uuid/autoLogin/type/deviceInfo 等字段，忽略即可
  const username = typeof body.username === "string" ? body.username.trim() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (!username || !password) {
    return errorResponse("用户名或密码错误", 400);
  }

  let user = await env.DB
    .prepare("SELECT id, username, password_hash, salt, display_name FROM users WHERE username = ?")
    .bind(username)
    .first();

  if (!user) {
    // 自动注册：首次登录即建号（客户端没有注册界面，CHANGELOG 承诺"支持注册、登录"，
    // 唯一可行方式就是首登建号；个人部署，域名未公开传播，可接受。
    // 要收紧时：预建账号后把本分支改回 401。密码下限 4 位（docs/13 用户要求宽松）。
    if (password.length < 4) return errorResponse("密码至少 4 位", 400);
    const salt = randomHex(SALT_BYTES);
    const hash = await hashPassword(password, salt);
    const ins = await env.DB
      .prepare(
        "INSERT INTO users (id, username, password_hash, salt, display_name, created_at) " +
          "VALUES (?, ?, ?, ?, ?, ?)"
      )
      .bind(crypto.randomUUID(), username, hash, salt, username, Date.now())
      .run();
    if (!ins.success) return errorResponse("注册失败，请重试", 500);
    user = await env.DB
      .prepare("SELECT id, username, password_hash, salt, display_name FROM users WHERE username = ?")
      .bind(username)
      .first();
  }

  const computed = await hashPassword(password, user.salt);
  if (computed !== user.password_hash) {
    return errorResponse("用户名或密码错误", 401);
  }

  const now = Date.now();
  const token = newToken();
  await env.DB.batch([
    // 顺手清理已过期 token
    env.DB.prepare("DELETE FROM tokens WHERE expires_at < ?").bind(now),
    env.DB.prepare("INSERT INTO tokens (token, user_id, expires_at) VALUES (?, ?, ?)")
      .bind(token, user.id, now + TOKEN_TTL_MS),
  ]);

  // LoginResponse.fromJson 期望的字段（user_model.dart / hbbs.dart）
  return jsonResponse({
    access_token: token,
    type: "access_token",
    user: {
      name: user.username,
      display_name: user.display_name || "",
      avatar: "",
      status: "",
    },
  });
}

// ---------------------------------------------------------------------------
// 地址簿同步
// ---------------------------------------------------------------------------

/** 确保用户有 ab_personal 行（首次访问生成固定 guid），返回该行 */
async function ensurePersonalRow(env, userId) {
  let row = await env.DB
    .prepare("SELECT guid, data FROM ab_personal WHERE user_id = ?")
    .bind(userId)
    .first();
  if (row) return row;
  await env.DB
    .prepare(
      "INSERT INTO ab_personal (user_id, guid, data, updated_at) VALUES (?, ?, NULL, ?) " +
        "ON CONFLICT (user_id) DO NOTHING"
    )
    .bind(userId, crypto.randomUUID(), Date.now())
    .run();
  return await env.DB
    .prepare("SELECT guid, data FROM ab_personal WHERE user_id = ?")
    .bind(userId)
    .first();
}

/** 拉取：{guid, data}；未推送过时 data 为空结构 */
async function pullPersonalAb(env, userId) {
  const row = await ensurePersonalRow(env, userId);
  let data = EMPTY_AB;
  if (row && row.data != null && row.data !== "") {
    try {
      const parsed = JSON.parse(row.data);
      data = parsed === null ? EMPTY_AB : parsed;
    } catch (e) {
      // 内容原样保存过，原样返回（不解析、不丢数据）
      data = row.data;
    }
  }
  return jsonResponse({ guid: row.guid, data }, 200);
}

/** 推送覆盖保存：data 值（JSON 字符串）原样存 TEXT，不解析内容 */
async function savePersonalAb(env, userId, text) {
  await env.DB
    .prepare(
      "INSERT INTO ab_personal (user_id, guid, data, updated_at) VALUES (?, ?, ?, ?) " +
        "ON CONFLICT (user_id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at"
    )
    .bind(userId, crypto.randomUUID(), text, Date.now())
    .run();
}

// POST /api/ab/personal 与 POST /api/ab 共用：
//   空体 / {}            -> 拉取 {guid, data}
//   {"data":"<JSON串>"}  -> 覆盖保存，200 空体
async function handleAbData(request, env) {
  const userId = await authenticate(request, env);
  if (!userId) return errorResponse("登录已过期，请重新登录", 401);

  const raw = await request.text();
  const trimmed = raw.trim();
  if (trimmed === "") return pullPersonalAb(env, userId);

  let body;
  try {
    body = JSON.parse(trimmed);
  } catch (e) {
    return errorResponse("请求格式错误", 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return errorResponse("请求格式错误", 400);
  }
  if (!Object.prototype.hasOwnProperty.call(body, "data")) {
    return pullPersonalAb(env, userId);
  }

  const data = body.data;
  if (data === null || data === undefined) {
    return errorResponse("请求格式错误", 400);
  }
  // 契约：客户端已双编码，data 为 JSON 字符串，原样存 TEXT，不解析内容
  const text = typeof data === "string" ? data : JSON.stringify(data);
  await savePersonalAb(env, userId, text);
  return emptyResponse(200);
}

// POST /api/ab/settings
//   带 JSON 体 -> 保存设置（TEXT 原样），200 空体
//   空体       -> 返回当前设置（客户端 _getAbSettings 以空体 POST 读取，需返回 JSON 对象）
async function handleAbSettings(request, env) {
  const userId = await authenticate(request, env);
  if (!userId) return errorResponse("登录已过期，请重新登录", 401);

  const raw = await request.text();
  if (raw.trim() === "") {
    const row = await env.DB
      .prepare("SELECT settings FROM ab_settings WHERE user_id = ?")
      .bind(userId)
      .first();
    let settings = {};
    if (row && row.settings) {
      try {
        const parsed = JSON.parse(row.settings);
        if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
          settings = parsed;
        }
      } catch (e) {
        settings = {};
      }
    }
    return jsonResponse(settings, 200);
  }

  await env.DB
    .prepare(
      "INSERT INTO ab_settings (user_id, settings, updated_at) VALUES (?, ?, ?) " +
        "ON CONFLICT (user_id) DO UPDATE SET settings = excluded.settings, updated_at = excluded.updated_at"
    )
    .bind(userId, raw, Date.now())
    .run();
  return emptyResponse(200);
}

// ---------------------------------------------------------------------------
// 路由
// ---------------------------------------------------------------------------

async function route(request, env) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const method = request.method;

  if (path === "/api/login" && method === "POST") return handleLogin(request, env);
  // 客户端登录框打开即拉第三方登录列表（user_model.dart queryOidcLoginOptions），
  // 缺此端点会 404 红字报错；返回空数组 = 无第三方登录，仅账号密码
  if (path === "/api/login-options" && method === "GET") return jsonResponse([], 200);
  if (path === "/api/ab/personal" && method === "POST") return handleAbData(request, env);
  if (path === "/api/ab" && method === "POST") return handleAbData(request, env);
  if (path === "/api/ab/settings" && method === "POST") return handleAbSettings(request, env);
  if (path === "/api/ab/shared/profiles" && method === "POST") return jsonResponse([], 200);
  if (path === "/api/ab" && method === "GET") return jsonResponse([], 200);

  if (KNOWN_PATHS[path]) return errorResponse("方法不允许", 405);
  return errorResponse("接口不存在", 404);
}

export default {
  async fetch(request, env, ctx) {
    try {
      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: CORS_HEADERS });
      }
      if (!env || !env.DB) {
        return errorResponse("服务未正确配置数据库绑定", 500);
      }
      return await route(request, env);
    } catch (err) {
      // 只记录到服务端日志，响应不泄露内部细节
      console.error("unhandled error:", err && (err.stack || err.message) || err);
      return errorResponse("服务器内部错误", 500);
    }
  },
};
