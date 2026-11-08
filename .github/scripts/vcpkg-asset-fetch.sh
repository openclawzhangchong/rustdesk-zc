#!/bin/bash
# vcpkg 资产抓取脚本（X_VCPKG_ASSET_SOURCES x-script 模板调用）
# 用法: vcpkg-asset-fetch.sh {url} {dst}
# 策略: GitHub 直连优先（含重试），失败自动切 gh-proxy 镜像
# 背景: 2026-11-08 GitHub release/archive 下载 CDN 大面积 504，详见 rustdesk-selfhost/docs/10
url="$1"
dst="$2"
curl -L --fail --retry 3 --retry-delay 5 "$url" -o "$dst" && exit 0
echo "[asset-fetch] 直连失败，切换 gh-proxy 镜像: $url"
curl -L --fail --retry 3 --retry-delay 5 "https://gh-proxy.com/$url" -o "$dst"
