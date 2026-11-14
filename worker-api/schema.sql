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
