#!/bin/bash
# 使用本地 conda 环境安装 Node.js 和 pnpm，预下载依赖
# 优势：使用国内镜像，无需 Docker

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STORE_DIR="${SCRIPT_DIR}/.pnpm-store"

echo "==> 1. 检查 conda 环境"
if [ -z "$CONDA_DEFAULT_ENV" ]; then
    echo "❌ 错误: 未检测到 conda 环境，请先激活 conda"
    echo "   运行: conda activate your-env"
    exit 1
fi
echo "    当前环境: $CONDA_DEFAULT_ENV"

echo ""
echo "==> 2. 安装 Node.js (通过 conda)"
if ! command -v node &> /dev/null; then
    echo "    Node.js 未安装，正在安装..."
    conda install -y -c conda-forge nodejs=22
else
    echo "    ✓ Node.js 已安装: $(node -v)"
fi

echo ""
echo "==> 3. 启用 pnpm (通过 corepack)"
if ! command -v pnpm &> /dev/null; then
    echo "    pnpm 未安装，正在启用 corepack..."
    corepack enable
    corepack prepare pnpm@10.22.0 --activate
else
    PNPM_VERSION=$(pnpm -v)
    echo "    ✓ pnpm 已安装: $PNPM_VERSION"
    if [ "$PNPM_VERSION" != "10.22.0" ]; then
        echo "    版本不匹配，准备 pnpm@10.22.0..."
        corepack prepare pnpm@10.22.0 --activate
    fi
fi

echo ""
echo "==> 4. 配置 pnpm 使用国内镜像"
pnpm config set registry https://mirrors.cloud.tencent.com/npm/
echo "    ✓ 镜像源: $(pnpm config get registry)"


echo ""
echo "==> 5. 深度检查 Store 权限"
mkdir -p "$STORE_DIR"
# 检查是否存在 root 拥有的文件（深度扫描）
if find "$STORE_DIR" -user root | grep -q .; then
    echo "    ⚠️ 发现 Store 中存在 root 拥有的子文件，正在修复权限..."
    sudo chown -R $USER:$USER "$STORE_DIR"
    echo "    ✓ 权限已深度修复"
else
    echo "    ✓ Store 权限正常"
fi

echo ""
echo "==> 6. 尝试清理旧依赖 (可选)"
if [ -d "node_modules" ] || find packages -maxdepth 2 -name "node_modules" -type d 2>/dev/null | grep -q .; then
    echo "    发现旧的 node_modules，尝试清理..."
    if ! rm -rf node_modules packages/*/node_modules 2>/dev/null; then
        echo "    ⚠️ 提示: 部分 node_modules 无法删除 (所有者可能是 root)。"
        echo "    如果后续 pnpm 报错 'Permission denied'，请手动运行:"
        echo "    sudo find . -type d -name 'node_modules' -exec rm -rf {} + 2>/dev/null"
    else
        echo "    ✓ 清理完成"
    fi
else
    echo "    ✓ 无需清理"
fi

echo ""
echo "==> 7. 下载依赖到本地 store"
echo "    Store: $STORE_DIR"
echo "    ⏳ 这可能需要几分钟，请耐心等待..."
echo ""

# 设置 store 位置并下载 (跳过可能失败的 lifecycle scripts)
pnpm config set store-dir "$STORE_DIR"
pnpm install --frozen-lockfile --ignore-scripts

echo ""
echo "==> ✅ 依赖下载成功！"
echo "    Store 位置: $STORE_DIR"
echo "    Store 大小: $(du -sh "$STORE_DIR" | cut -f1)"
echo ""
echo "💡 下一步: 构建 Docker 镜像"
echo "    docker build -f Dockerfile.source.cached -t n8n:latest ."
