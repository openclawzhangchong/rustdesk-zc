#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# zcdesk 采集修复回归测试（v2.2.1 起，7 个）
#
# 用法：bash test/run-regression-tests.sh
# 前置：VCPKG_ROOT / LIBCLANG_PATH 指向本机工具链（示例见下），Rust MSVC _toolchain。
# 覆盖：Bug1 跨窗口连丢回退 / 成功帧保留 DXGI / 突发上限不变 / 既有 refresh；
#       Bug2 间接显示已活动跳过 / clone 优先与 IDD 主显示回退 / 兼容默认关闭。
# 其中 spaced_access_lost_falls_back_to_gdi 在 master 上 fail（已实锤），
# 其余锁定健康机器行为不变。
# ---------------------------------------------------------------------------
set -e
export VCPKG_ROOT="${VCPKG_ROOT:-D:/vcpkg}"
export LIBCLANG_PATH="${LIBCLANG_PATH:-D:/_zc_build/llvm/bin}"
cd "$(dirname "$0")/.."
cargo test --locked --release --lib --features "hwcodec,vram" -- \
  video_service::tests compat_display::tests