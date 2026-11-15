#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# zcdesk Windows 交付验收脚本（本机可重复执行）
#
# 用途：每次出包后跑一遍，确认「装的是哪一版 + 能不能连上被控端」两件事。
# 这两条是本项目的性命线：版本号必须能在主页看到；连接必须成功。
#
# 用法：
#   bash test/verify-windows.sh                      # 用桌面上的包
#   bash test/verify-windows.sh path/to/x86_64.msi   # 指定包
#   PEER_ID=253375647 bash test/verify-windows.sh    # 指定被控端（默认 G32）
#   SKIP_INSTALL=1 bash test/verify-windows.sh       # 只验证已装版本
#
# 依赖：powershell（Windows）、python3（读 app.so 找版本串）
# 退出码：0 = 全部通过；非 0 = 有检查项失败
# ---------------------------------------------------------------------------
set -u

PEER_ID="${PEER_ID:-253375647}"
APP_EXE="C:/Program Files/智策远控/智策远控.exe"
APP_SO="C:/Program Files/智策远控/data/app.so"
CONFIG_DIR="C:/Users/${USERNAME:-Administrator}/AppData/Roaming/智策远控"
LOG_DIR="$CONFIG_DIR/log"
DESKTOP="${USERPROFILE:-C:/Users/Administrator}/Desktop"

FAIL=0
ok()   { echo "  PASS  $1"; }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
step() { echo "[$1] $2"; }

PKG="${1:-}"
if [ -z "$PKG" ]; then
  PKG=$(ls -t "$DESKTOP"/zcdesk-*-x86_64.msi 2>/dev/null | head -1)
fi

echo "=== zcdesk Windows 交付验收 ==="
echo "包: ${PKG:-<未找到，跳过安装>}"
echo "被控端: $PEER_ID"
echo

# ---------------------------------------------------------------------------
step 1 "安装（SKIP_INSTALL=1 可跳过）"
if [ "${SKIP_INSTALL:-0}" = "1" ]; then
  echo "  SKIP  按要求跳过安装"
elif [ -z "$PKG" ] || [ ! -f "$PKG" ]; then
  bad "找不到安装包（桌面无 zcdesk-*-x86_64.msi）"
else
  powershell -NoProfile -Command \
    "Get-Process 智策远控 -ErrorAction SilentlyContinue | Stop-Process -Force" >/dev/null 2>&1
  sleep 2
  msiexec //i "$(cygpath -w "$PKG" 2>/dev/null || echo "$PKG")" //qn //norestart >/dev/null 2>&1
  sleep 8
  [ -f "$APP_EXE" ] && ok "安装完成（$APP_EXE 存在）" || bad "安装后找不到 exe"
fi
echo

# ---------------------------------------------------------------------------
step 2 "版本串核对（app.so 内必须含当前版本，且无旧版本残留）"
if [ ! -f "$APP_SO" ]; then
  bad "找不到 $APP_SO"
else
  VER=$(python - "$APP_SO" <<'PY'
import re, sys
d = open(sys.argv[1], 'rb').read()
m = sorted(set(re.findall(rb'v2\.\d+\.\d+', d)))
print(' '.join(x.decode() for x in m))
PY
)
  echo "  app.so 内版本串: ${VER:-<无>}"
  if [ -n "$VER" ]; then
    NEWEST=$(echo "$VER" | tr ' ' '\n' | sort -V | tail -1)
    ok "检测到版本 $NEWEST"
    for old in v1.0.7 v2.0.0 v2.0.1 v2.0.2 v2.0.3 v2.1.0 v2.1.1 v2.1.2; do
      echo "$VER" | grep -q "$old" && bad "存在旧版本残留 $old"
    done
  else
    bad "app.so 内没有任何 v2.x 版本串（版本号可能未编入）"
  fi
fi
echo

# ---------------------------------------------------------------------------
step 3 "配置检查（登录相关开关必须是关闭状态，且不得有 api-server）"
CFG2="$CONFIG_DIR/config/智策远控2.toml"
CFGL="$CONFIG_DIR/config/智策远控_local.toml"
if [ -f "$CFG2" ]; then
  grep -q "api-server" "$CFG2" && bad "主配置仍含 api-server（应已移除）" || ok "主配置无 api-server"
  grep -q "custom-rendezvous-server" "$CFG2" && ok "已预置 ID 服务器" || bad "缺少 ID 服务器配置"
  grep -q "^key" "$CFG2" && ok "已预置 key" || bad "缺少 key 配置"
else
  echo "  SKIP  未找到主配置（首次运行会自动播种）"
fi
if [ -f "$CFGL" ]; then
  if grep -q "access_token" "$CFGL"; then
    bad "本地配置仍含 access_token（会触发 KX 握手死锁，必须清除）"
  else
    ok "本地配置无 access_token（连接走干净路径）"
  fi
  for k in enable-webrtc enable-udp-punch enable-ipv6-punch; do
    grep -q "^$k = 'Y'" "$CFGL" && bad "实验开关 $k 被强制开启（会破坏连接）" || true
  done
  ok "实验性打洞开关未强制开启"
else
  echo "  SKIP  未找到本地配置"
fi
echo

# ---------------------------------------------------------------------------
step 4 "连接验收（核心：必须能连上 $PEER_ID）"
powershell -NoProfile -Command \
  "Get-Process 智策远控 -ErrorAction SilentlyContinue | Stop-Process -Force" >/dev/null 2>&1
sleep 2
powershell -NoProfile -Command \
  "Start-Process '$APP_EXE' -ArgumentList '--connect','$PEER_ID'" >/dev/null 2>&1
sleep 25
TITLE=$(powershell -NoProfile -Command \
  "(Get-Process 智策远控 -ErrorAction SilentlyContinue | Select-Object -First 1).MainWindowTitle" 2>/dev/null | tr -d '\r')
echo "  窗口标题: ${TITLE:-<空>}"
case "$TITLE" in
  *"$PEER_ID"*"Remote Desktop"*) ok "已建立远程会话窗口" ;;
  *) bad "未建立远程会话（标题不含 $PEER_ID）" ;;
esac
if [ -d "$LOG_DIR" ]; then
  LATEST=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
  if [ -n "$LATEST" ]; then
    if grep -q "Connection closed: Failed to secure tcp" "$LATEST"; then
      bad "日志出现 Failed to secure tcp（连接握手失败）"
    else
      ok "日志无 secure tcp 失败记录"
    fi
    grep -q "secure tcp with rendezvous server failed" "$LATEST" \
      && echo "  NOTE  出现过握手降级告警（自建 OSS 服务器正常现象，不影响连接）"
  fi
fi
echo

# ---------------------------------------------------------------------------
echo "=== 结果: $([ "$FAIL" -eq 0 ] && echo '全部通过 ✅' || echo "$FAIL 项失败 ❌") ==="
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
