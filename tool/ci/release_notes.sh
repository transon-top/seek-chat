#!/usr/bin/env bash
# 本地生成 Release 说明初稿：从 gh 取 token，避免 git-cliff 未认证请求的 60 次/时限流。
# 用法与 git cliff 相同，参数原样透传，例如：
#   ./tool/ci/release_notes.sh --unreleased --tag v1.1.0
#   ./tool/ci/release_notes.sh v1.0.1..v1.1.0
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -z "${GITHUB_TOKEN:-}" ]; then
  GITHUB_TOKEN="$(gh auth token)"
fi
export GITHUB_TOKEN

exec git cliff --config cliff.toml "$@"
