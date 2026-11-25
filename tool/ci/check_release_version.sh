#!/usr/bin/env bash
# 校验发版 tag 与 pubspec.yaml 一致：vX.Y.Z 必须等于 version 的 X.Y.Z，
# 且 +n 必须严格大于上一个可达 v* tag 的 +n。缺少上一个 tag 时跳过递增检查。
set -euo pipefail
cd "$(dirname "$0")/../.."

tag="${1:-${GITHUB_REF_NAME:-}}"
if [ -z "$tag" ]; then
  echo "用法: $0 vX.Y.Z" >&2
  exit 2
fi

fail() {
  echo "::error::$*"
  exit 1
}

if ! [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "tag '$tag' 不是 vX.Y.Z 形式，无法发版。"
fi

current_version="$(awk '/^version:/ { sub(/^version:[ \t]*/, ""); print; exit }' pubspec.yaml)"
[ -n "$current_version" ] || fail "pubspec.yaml 缺少 version。"

current_name="${current_version%%+*}"
current_build="${current_version#*+}"
if [ "$current_build" = "$current_version" ] || ! [[ "$current_build" =~ ^[0-9]+$ ]]; then
  fail "pubspec.yaml 的 version '$current_version' 缺少合法的 +n 构建号。"
fi
if [ "$current_name" != "${tag#v}" ]; then
  fail "tag $tag 与 pubspec.yaml 版本 $current_version 不一致：请先改 pubspec.yaml 再打 tag。"
fi

if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)" = "true" ]; then
  fail "仓库是浅克隆，无法校验 +n 递增；需要完整历史与 tags（fetch-depth: 0）。"
fi

prev_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude "$tag" HEAD 2>/dev/null || true)"
if [ -z "$prev_tag" ]; then
  echo "版本校验通过：${tag}（${current_version}），没有上一个 v* tag，跳过 +n 递增检查。"
  exit 0
fi

prev_version="$(git show "$prev_tag:pubspec.yaml" 2>/dev/null | awk '/^version:/ { sub(/^version:[ \t]*/, ""); print; exit }')"
[ -n "$prev_version" ] || fail "无法读取 $prev_tag 的 pubspec.yaml 版本。"

prev_build="${prev_version#*+}"
if [ "$prev_build" = "$prev_version" ] || ! [[ "$prev_build" =~ ^[0-9]+$ ]]; then
  prev_build=0
fi
if [ "$current_build" -le "$prev_build" ]; then
  fail "+n 未递增：pubspec 为 ${current_version}，上一版 ${prev_tag} 为 ${prev_version}。"
fi

echo "版本校验通过：${tag}（${current_version}），上一版 ${prev_tag} 为 ${prev_version}。"
