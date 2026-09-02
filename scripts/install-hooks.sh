#!/bin/bash

# Open Island Hook 安装脚本
# 自动配置 Claude Code 等 AI 工具的 hooks

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Open Island Hook Installer"
echo "================================"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查依赖
check_dependencies() {
    echo -e "${BLUE}Checking dependencies...${NC}"
    
    if ! command -v node &> /dev/null; then
        echo -e "${RED}Error: Node.js is required but not installed.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Node.js found${NC}"
}

# 安装 bridge 依赖
install_bridge() {
    echo -e "${BLUE}Installing bridge dependencies...${NC}"
    
    cd "$REPO_ROOT/bridge"

    if [ "${FORCE_BRIDGE_INSTALL:-0}" != "1" ]; then
        echo -e "${GREEN}✓ Bridge dependencies already installed${NC}"
        return
    fi

    npm install --no-audit --no-fund
    
    echo -e "${GREEN}✓ Bridge dependencies installed${NC}"
}

install_tool_hooks() {
    SELECTED_TOOLS="${OPEN_ISLAND_TOOLS:-}"
    if [ -z "$SELECTED_TOOLS" ]; then
        echo -e "${RED}No tools selected.${NC}"
        echo "Set OPEN_ISLAND_TOOLS to a comma-separated list, for example: claude,cursor"
        exit 1
    fi
    echo -e "${BLUE}Installing explicitly selected tools: $SELECTED_TOOLS${NC}"
    HOOK_TOOLS="$(printf '%s' "$SELECTED_TOOLS" | tr ',' '\n' | sed '/^codex-wrapper$/d' | paste -sd, -)"
    if [ -n "$HOOK_TOOLS" ]; then
        PLAN_FILE="$(mktemp "${TMPDIR:-/tmp}/open-island-plan.XXXXXX")"
        rm -f "$PLAN_FILE"
        node "$SCRIPT_DIR/auto-install-hooks.js" --tools "$HOOK_TOOLS" --plan-file "$PLAN_FILE"
        if [ "${OPEN_ISLAND_ASSUME_YES:-0}" != "1" ]; then
            printf "Apply this plan? [y/N] "
            read -r ANSWER
            if [ "$ANSWER" != "y" ] && [ "$ANSWER" != "Y" ]; then
                rm -f "$PLAN_FILE"
                echo "Installation cancelled."
                exit 0
            fi
        fi
        node "$SCRIPT_DIR/auto-install-hooks.js" --apply --plan-file "$PLAN_FILE"
        rm -f "$PLAN_FILE"
    fi
    if printf '%s' "$SELECTED_TOOLS" | tr ',' '\n' | grep -qx 'codex-wrapper'; then
        node "$SCRIPT_DIR/install-codex-wrapper.js"
    fi
    echo -e "${GREEN}✓ Hooks installed${NC}"
}

# 创建启动脚本
create_launch_script() {
    echo -e "${BLUE}Creating launch script...${NC}"
    
    LAUNCH_SCRIPT="$HOME/.local/bin/open-island"
    LEGACY_SCRIPT="$HOME/.local/bin/notch-monitor"

    mkdir -p "$(dirname "$LAUNCH_SCRIPT")"

    cat > "$LAUNCH_SCRIPT" <<EOF
#!/bin/bash
exec "$REPO_ROOT/scripts/open-island" "\$@"
EOF

    chmod +x "$LAUNCH_SCRIPT"

    cat > "$LEGACY_SCRIPT" <<EOF
#!/bin/bash

exec "$LAUNCH_SCRIPT" "\$@"
EOF

    chmod +x "$LEGACY_SCRIPT"
    
    echo -e "${GREEN}✓ Launch script created at $LAUNCH_SCRIPT${NC}"
    echo -e "${GREEN}✓ Legacy compatibility shim updated at $LEGACY_SCRIPT${NC}"
    echo -e "${YELLOW}Add $(dirname "$LAUNCH_SCRIPT") to your PATH${NC}"
}

# 主流程
main() {
    check_dependencies
    install_bridge
    install_tool_hooks
    create_launch_script
    
    echo ""
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}Installation Complete!${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Add ~/.local/bin to your PATH if not already done"
    echo "2. Start the monitor: open-island start"
    echo "3. Use Claude Code or Codex normally - they will appear in the notch panel"
    echo ""
}

main "$@"
