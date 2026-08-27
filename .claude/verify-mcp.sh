#!/bin/bash
# verify-mcp.sh - Script to verify MCP server configuration for Claude Code

echo "========================================="
echo "MCP Configuration Verification for Claude"
echo "========================================="
echo ""

CONFIG_FILE=~/Library/Application\ Support/Claude/claude_desktop_config.json

# Check if configuration file exists
if [ -f "$CONFIG_FILE" ]; then
    echo "✓ Configuration file exists"
    echo "  Location: $CONFIG_FILE"
    echo ""
else
    echo "✗ Configuration file not found at $CONFIG_FILE"
    echo ""
    echo "  To create it, run:"
    echo "  cat > ~/Library/Application\ Support/Claude/claude_desktop_config.json << 'EOF'"
    echo '  {
    "mcpServers": {
      "figma-dev-mode": {
        "command": "npx",
        "args": ["-y", "@figma/mcp-server-figma-dev-mode"],
        "description": "Figma Dev Mode MCP server"
      }
    }
  }'
    echo "  EOF"
    echo ""
    exit 1
fi

# Validate JSON syntax
if python3 -m json.tool "$CONFIG_FILE" > /dev/null 2>&1; then
    echo "✓ JSON syntax is valid"
else
    echo "✗ JSON syntax error in configuration"
    echo "  Error details:"
    python3 -m json.tool "$CONFIG_FILE" 2>&1 | grep -v "^Expecting"
    exit 1
fi

# Check for Figma MCP server configuration
if grep -q "figma-dev-mode" "$CONFIG_FILE"; then
    echo "✓ Figma MCP server configured"
else
    echo "⚠ Figma MCP server not found in configuration"
fi

echo ""
echo "System Requirements:"
echo "-------------------"

# Check if Figma is running
if pgrep -i figma > /dev/null; then
    echo "✓ Figma Desktop App is running"
    FIGMA_PIDS=$(pgrep -i figma | head -3 | tr '\n' ' ')
    echo "  Process IDs: $FIGMA_PIDS..."
else
    echo "⚠ Figma Desktop App is not running"
    echo "  Launch Figma and enable Dev Mode (Shift+D) for MCP to work"
fi

# Check for Node.js/npx
if which npx > /dev/null 2>&1; then
    echo "✓ npx is available"
    NPX_VERSION=$(npx --version 2>/dev/null)
    echo "  Version: $NPX_VERSION"
else
    echo "✗ npx not found (required for MCP servers)"
    echo "  Install Node.js to get npx: brew install node"
fi

# Check for Node.js
if which node > /dev/null 2>&1; then
    echo "✓ Node.js is installed"
    NODE_VERSION=$(node --version 2>/dev/null)
    echo "  Version: $NODE_VERSION"
else
    echo "✗ Node.js not found"
    echo "  Install with: brew install node"
fi

echo ""
echo "MCP Server Configuration:"
echo "------------------------"
echo "Configured MCP servers:"
python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    if 'mcpServers' in config:
        for name, settings in config['mcpServers'].items():
            print(f'  • {name}')
            if 'description' in settings:
                print(f'    {settings[\"description\"]}')
    else:
        print('  None configured')
" 2>/dev/null || echo "  Error reading configuration"

echo ""
echo "========================================="
echo "Next Steps:"
echo ""

# Determine if restart is needed
ALL_GOOD=true
if [ ! -f "$CONFIG_FILE" ]; then
    ALL_GOOD=false
elif ! grep -q "figma-dev-mode" "$CONFIG_FILE" 2>/dev/null; then
    ALL_GOOD=false
fi

if [ "$ALL_GOOD" = true ]; then
    echo "✓ Configuration looks good!"
    echo ""
    echo "To activate MCP servers:"
    echo "1. Stop Claude Code (Ctrl+C in terminal)"
    echo "2. Restart with: claude"
    echo ""
    echo "After restart, these tools should be available:"
    echo "  • mcp__figma-dev-mode-mcp-server__get_code"
    echo "  • mcp__figma-dev-mode-mcp-server__get_image"
    echo "  • mcp__figma-dev-mode-mcp-server__get_metadata"
else
    echo "⚠ Configuration needs attention"
    echo "  Fix the issues above, then restart Claude Code"
fi

echo "========================================="