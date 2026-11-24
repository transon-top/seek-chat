#!/usr/bin/env bash
# 构建 Android release APK（按 ABI 分包），产物重命名为 SeekChat-<abi>-release.apk。
# Flutter 的 CopyFlutterApksTask 把文件名硬编码为 app-<abi>-release.apk，Gradle 无法改名。
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build apk --release --split-per-abi

dir=build/app/outputs/flutter-apk
for f in "$dir"/app-*-release.apk; do
  [ -e "$f" ] || continue
  mv "$f" "$dir/SeekChat-$(basename "$f" | sed 's/^app-//')"
done

ls -lh "$dir"/SeekChat-*.apk
