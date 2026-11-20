#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# zcdesk 采集兼容验收脚本（微信二维码白窗修复，v2.2.1 起）
#
# 检查五件事：
#   1 服务 Running
#   2 服务日志的 compat 触发链（enabled / skipped / 健康 DXGI 未触发）+ 钉 GDI 状态
#   3 真实生效拓扑含间接显示（compat 触发时）
#   4 微信登录二维码 GDI 像素可读（有微信窗口时；无窗口 SKIP）
#   5 配置干净（无 api-server / access_token / 强制打洞开关）
#
# 用法：bash test/verify-capture.sh
# 环境变量：LOG_DIR（默认 LocalService 服务侧 server 日志目录）、QR_TAG（抓取标签）
# 依赖：powershell、python（pillow/psutil，见 test/probe-qr.py）
# 退出码：0 = 全部通过（含 SKIP/NOTE）；非 0 = 有 FAIL
# ---------------------------------------------------------------------------
set -u
FAIL=0
ok()   { echo "  PASS  $1"; }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
note() { echo "  NOTE  $1"; }
step() { echo "[$1] $2"; }

LOG_DIR="${LOG_DIR:-C:/Windows/ServiceProfiles/LocalService/AppData/Roaming/智策远控/log/server}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "=== zcdesk 采集兼容验收 ==="
echo

step 1 "服务状态"
STATE=$(powershell -NoProfile -Command \
  "(Get-CimInstance Win32_Service | Where-Object { \$_.PathName -like '*智策*' }).State" 2>/dev/null | tr -d '\r')
[ "$STATE" = "Running" ] && ok "服务 Running" || bad "服务状态=${STATE:-<无>}"
echo

step 2 "compat 触发链与钉 GDI（服务日志）"
LATEST=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
if [ -z "$LATEST" ]; then
  bad "找不到服务日志（$LOG_DIR）"
else
  echo "  日志: $LATEST"
  LAST_GDI=$(grep -a "] gdi: " "$LATEST" | tail -1 | sed 's/.*] gdi: //')
  if grep -aq "compat display enabled" "$LATEST"; then
    ok "compat display enabled（$(grep -a 'compat display enabled' "$LATEST" | tail -1 | sed 's/.*enabled: //')）"
    if grep -aq "compat display active, pin gdi" "$LATEST"; then
      ok "出现钉 GDI 钩子日志"
    elif [ "$LAST_GDI" = "true" ]; then
      ok "当前采集为 GDI（兼容生效期间无需再钉）"
    else
      bad "compat 已生效但当前采集仍为 DXGI（LAST_GDI=$LAST_GDI）→ 远程会白窗"
    fi
  elif grep -aq "compat display skipped" "$LATEST"; then
    note "已有间接显示活动，compat 跳过（不动拓扑，属预期）"
  elif grep -aq "] gdi: true" "$LATEST"; then
    bad "日志有 GDI 采集但无 compat 行（钩子缺口？）"
  else
    note "DXGI 健康、未触发 compat（健康机器预期零影响）"
  fi
fi
echo

step 3 "真实生效拓扑"
if python "$HERE/probe-topo.py"; then
  ok "存在间接显示活动（上方快照）"
else
  if [ -n "$LATEST" ] && grep -aq "compat display enabled\|compat display skipped" "$LATEST"; then
    bad "compat 已触发但拓扑无间接显示"
  else
    note "仅物理输出（健康机器预期）"
  fi
fi
echo

step 4 "微信二维码 GDI 像素"
QR_OUT="${QR_OUT:-${TEMP:-.}}"
mkdir -p "$QR_OUT"
python "$HERE/probe-qr.py" "${QR_TAG:-verify}" "$QR_OUT" 2>/dev/null
RC=$?
case $RC in
  0) ok "二维码可读（darkpx > 500，截图见 $QR_OUT）" ;;
  2) note "没有可见微信窗口，跳过（打开微信登录框后重跑）" ;;
  *) bad "微信窗口白窗/空白（darkpx <= 500）" ;;
esac
echo

step 5 "配置干净"
for CFG in "C:/Users/${USERNAME:-Administrator}/AppData/Roaming/智策远控/config" \
           "C:/Windows/ServiceProfiles/LocalService/AppData/Roaming/智策远控/config"; do
  if [ -f "$CFG/智策远控2.toml" ] && grep -q "api-server" "$CFG/智策远控2.toml"; then
    bad "$CFG 仍含 api-server"
  fi
  if [ -f "$CFG/智策远控_local.toml" ]; then
    grep -q "access_token" "$CFG/智策远控_local.toml" && bad "$CFG 含 access_token"
    for k in enable-webrtc enable-udp-punch enable-ipv6-punch; do
      grep -q "^$k = 'Y'" "$CFG/智策远控_local.toml" && bad "$CFG 强制开启 $k"
    done
  fi
done
[ "$FAIL" -eq 0 ] && ok "两个 profile 配置干净"
echo

echo "=== 结果: $([ "$FAIL" -eq 0 ] && echo '全部通过 ✅' || echo "$FAIL 项失败 ❌") ==="
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)