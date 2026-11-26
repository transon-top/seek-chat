#!/usr/bin/env bash
# 一次性安装：git 全局模板 + 当前 clone 的 lefthook 钩子。
# 模板让本机以后 clone 的仓库在仓库根有 lefthook.yml 时自动带上 pre-push 钩子。
set -euo pipefail

cd "$(dirname "$0")/../.."

if ! command -v lefthook >/dev/null 2>&1; then
  echo "缺少 lefthook：brew install lefthook" >&2
  exit 1
fi

template_dir="${XDG_CONFIG_HOME:-$HOME/.config}/git/templates"
template_hook="$template_dir/hooks/pre-push"
mkdir -p "$(dirname "$template_hook")"
cat > "$template_hook" <<'EOF'
#!/usr/bin/env sh
# 通用 pre-push：仓库根有 lefthook.yml 时执行 lefthook；否则放行。
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$repo_root/lefthook.yml" ] || exit 0
if ! command -v lefthook >/dev/null 2>&1; then
  echo "lefthook 未安装：brew install lefthook" >&2
  exit 1
fi
cd "$repo_root"
exec lefthook run pre-push
EOF
chmod +x "$template_hook"

git config --global init.templateDir "$template_dir"
lefthook install

echo "已配置 git 模板：$template_dir"
echo "当前 clone 的 pre-push 钩子已安装。"
