-- 智策远控 D1 Schema（与契约文档 13-login-api-design.md 第三节逐字一致）
-- 时间戳字段统一存 Unix 毫秒（INTEGER）。
-- 执行方式：
--   远端：wrangler d1 execute zcdesk-db --remote --file schema.sql
--   本地：wrangler d1 execute zcdesk-db --local  --file schema.sql

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  salt TEXT NOT NULL,
  display_name TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS tokens (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS ab_personal (
  user_id TEXT PRIMARY KEY,
  guid TEXT NOT NULL,
  data TEXT,
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS ab_settings (
  user_id TEXT PRIMARY KEY,
  settings TEXT,
  updated_at INTEGER NOT NULL
);

-- 细粒度地址簿（1.5.1 客户端 personal 模式增量 API）：peers/tags 文档存储
CREATE TABLE IF NOT EXISTS ab_peers (
  user_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  data TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, peer_id)
);
CREATE TABLE IF NOT EXISTS ab_tags (
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  color INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, name)
);
