#!/usr/bin/env bash
# 本地推送前检查：重跑代码生成并检查生成物漂移，再跑静态检查与测试。
# 发版工作流复用同一脚本，保证本地与发版执行相同的检查。
set -euo pipefail

cd "$(dirname "$0")/../.."

# 只判生成物路径：本地工作区可能有无关的未提交改动，不能照搬整树 git status。
generated_paths=(
  lib/shared/data/database.g.dart
  lib/l10n/generated
)

echo "==> 重跑代码生成"
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n

echo "==> 检查生成物漂移"
generated_changes="$(git status --porcelain -- "${generated_paths[@]}")"
if [[ -n "$generated_changes" ]]; then
  printf '%s\n' "$generated_changes"
  git diff HEAD -- "${generated_paths[@]}"
  echo "生成物与提交不一致：提交重新生成的产物后再推送。" >&2
  exit 1
fi

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test"
flutter test

echo "==> 本地检查全部通过"
