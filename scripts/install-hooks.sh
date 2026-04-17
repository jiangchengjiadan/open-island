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
    npm install
    
    echo -e "${GREEN}✓ Bridge dependencies installed${NC}"
}

install_tool_hooks() {
    echo -e "${BLUE}Installing Claude hooks and silent Codex monitoring...${NC}"
    node "$SCRIPT_DIR/auto-install-hooks.js"
    node "$SCRIPT_DIR/install-codex-wrapper.js"
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

# Open Island Launcher

REPO_ROOT="$REPO_ROOT"
BRIDGE_DIR="\$REPO_ROOT/bridge"
NATIVE_DIR="\$REPO_ROOT/native/NotchMonitor"
HOOK_INSTALLER="\$REPO_ROOT/scripts/auto-install-hooks.js"
CODEX_WRAPPER_INSTALLER="\$REPO_ROOT/scripts/install-codex-wrapper.js"

case "\$1" in
    start)
        echo "Installing hooks..."
        node "\$HOOK_INSTALLER"
        node "\$CODEX_WRAPPER_INSTALLER"
        
        echo "Starting Open Island..."
        cd "\$NATIVE_DIR"
        swift package clean >/dev/null 2>&1 || true
        swift run NotchMonitor &
        ;;
    
    stop)
        pkill -f "\$BRIDGE_DIR/server.js" 2>/dev/null || true
        pkill -f "swift run NotchMonitor" 2>/dev/null || true
        pkill -f "/NotchMonitor" 2>/dev/null || true
        ;;
    
    restart)
        \$0 stop
        sleep 1
        \$0 start
        ;;
    
    status)
        if pgrep -f "\$BRIDGE_DIR/server.js" > /dev/null || pgrep -f "swift run NotchMonitor" > /dev/null || pgrep -f "/NotchMonitor" > /dev/null; then
            echo "Open Island is running"
        else
            echo "Open Island is not running"
        fi
        ;;
    
    *)
        echo "Usage: open-island [start|stop|restart|status]"
        exit 1
        ;;
esac
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
