# MCP (Model Context Protocol) Server Configuration Guide

## What are MCP Servers?

MCP servers are external processes that extend Claude Code's capabilities by providing structured access to external services, APIs, and tools. They act as bridges between Claude and external systems, enabling functionality that wouldn't otherwise be available.

## Critical Understanding

### MCP Servers are NOT Persistent
- **MCP servers must be configured on each machine** where Claude Code is used
- **Configuration does not sync** between different installations
- **Previous usage does not guarantee availability** in new sessions
- **Claude Code must be restarted** after configuration changes

### Evidence of Past Usage vs Current Availability
When you see MCP tools listed in `.claude/settings.local.json` but they're not available in the current session, this indicates:
1. MCP was configured and working in a previous environment
2. The current environment lacks the necessary configuration
3. The configuration file needs to be created/restored

## Configuration File Location

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
**Linux**: `~/.config/claude/claude_desktop_config.json`
**Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

## Figma MCP Server Setup

### Prerequisites
1. **Node.js and npm** installed (for npx command)
2. **Figma Desktop App** installed and running
3. **Figma Dev Mode** enabled in the design file

### Configuration Steps

1. **Create the configuration file**:
```bash
# macOS
mkdir -p ~/Library/Application\ Support/Claude
cat > ~/Library/Application\ Support/Claude/claude_desktop_config.json << 'EOF'
{
  "mcpServers": {
    "figma-dev-mode": {
      "command": "npx",
      "args": ["-y", "@figma/mcp-server-figma-dev-mode"],
      "description": "Figma Dev Mode MCP server for extracting design specifications, code, and images from Figma files"
    }
  }
}
EOF
```

2. **Restart Claude Code**:
```bash
# Stop Claude Code
# Press Ctrl+C in the terminal where Claude is running

# Start Claude Code again
claude
```

3. **Verify MCP tools availability**:
After restart, the following tools should be available:
- `mcp__figma-dev-mode-mcp-server__get_code`
- `mcp__figma-dev-mode-mcp-server__get_image`
- `mcp__figma-dev-mode-mcp-server__get_metadata`

## How MCP Tools Appear in Claude Code

MCP tools follow a specific naming pattern:
```
mcp__<server-name>__<tool-name>
```

For example:
- Server name: `figma-dev-mode-mcp-server`
- Tool name: `get_code`
- Full tool name: `mcp__figma-dev-mode-mcp-server__get_code`

## Figma MCP Server Capabilities

### Available Tools

1. **get_metadata**
   - Extracts design context from Figma files
   - Returns variables, components, and layout information
   - Provides design system information

2. **get_image**
   - Exports visual representations of Figma frames
   - Returns base64-encoded images
   - Useful for visual reference during implementation

3. **get_code**
   - Generates code from selected Figma frames
   - Produces SwiftUI, UIKit, or other platform-specific code
   - Includes styling, layout, and component structure

### Usage Examples

```python
# Get metadata from a Figma file
mcp__figma-dev-mode-mcp-server__get_metadata(
    url="https://www.figma.com/design/..."
)

# Extract an image from a specific node
mcp__figma-dev-mode-mcp-server__get_image(
    url="https://www.figma.com/design/...?node-id=123-456"
)

# Generate code for a component
mcp__figma-dev-mode-mcp-server__get_code(
    url="https://www.figma.com/design/...?node-id=123-456"
)
```

## Troubleshooting Guide

### MCP Tools Not Available

1. **Check configuration file exists**:
```bash
cat ~/Library/Application\ Support/Claude/claude_desktop_config.json
```

2. **Verify JSON syntax is valid**:
```bash
python3 -m json.tool ~/Library/Application\ Support/Claude/claude_desktop_config.json
```

3. **Ensure Claude Code was restarted** after configuration

4. **Check Node.js/npm installation**:
```bash
which npx
npx --version
```

### Figma MCP Specific Issues

1. **"Figma not running" error**:
   - Launch Figma Desktop App
   - Verify with: `ps aux | grep -i figma`

2. **"Dev Mode not enabled" error**:
   - Open your Figma file
   - Press `Shift+D` to enable Dev Mode
   - Look for the Dev Mode indicator in the UI

3. **"Cannot access file" error**:
   - Ensure file has proper permissions
   - Check you're logged into Figma
   - Try opening the file in browser first

### Connection Issues

If MCP server fails to connect:

1. **Check if port is in use** (for local servers):
```bash
lsof -i :3845  # Figma local MCP port
```

2. **Test direct connection**:
```bash
# For Figma local server
curl -X POST http://127.0.0.1:3845/mcp \
  -H "Content-Type: application/json" \
  -d '{"method":"ping"}'
```

3. **Review Claude Code logs** for connection errors

## Adding Additional MCP Servers

The configuration supports multiple MCP servers:

```json
{
  "mcpServers": {
    "figma-dev-mode": {
      "command": "npx",
      "args": ["-y", "@figma/mcp-server-figma-dev-mode"]
    },
    "another-server": {
      "command": "python",
      "args": ["-m", "another_mcp_server"]
    }
  }
}
```

## Best Practices

1. **Document MCP requirements** in project README or CLAUDE.md
2. **Include configuration in onboarding** documentation
3. **Test MCP availability** before relying on it in workflows
4. **Provide fallback options** when MCP tools aren't available
5. **Keep configuration minimal** - only add needed servers

## Security Considerations

1. **MCP servers have system access** - only use trusted servers
2. **Review server permissions** before installation
3. **Avoid hardcoding sensitive data** in configuration
4. **Use environment variables** for API keys when needed:
```json
{
  "mcpServers": {
    "example": {
      "command": "npx",
      "args": ["example-server"],
      "env": {
        "API_KEY": "${EXAMPLE_API_KEY}"
      }
    }
  }
}
```

## Common MCP Servers for iOS Development

1. **Figma Dev Mode** - Design to code conversion
2. **GitHub MCP** - Repository management
3. **Database MCP** - Direct database access
4. **API Testing MCP** - API endpoint testing

## Verification Script

Create this script to verify MCP setup:

```bash
#!/bin/bash
# verify-mcp.sh

echo "Checking MCP Configuration..."

CONFIG_FILE=~/Library/Application\ Support/Claude/claude_desktop_config.json

if [ -f "$CONFIG_FILE" ]; then
    echo "✓ Configuration file exists"

    if python3 -m json.tool "$CONFIG_FILE" > /dev/null 2>&1; then
        echo "✓ JSON syntax is valid"
    else
        echo "✗ JSON syntax error in configuration"
        exit 1
    fi

    if grep -q "figma-dev-mode" "$CONFIG_FILE"; then
        echo "✓ Figma MCP server configured"
    else
        echo "✗ Figma MCP server not configured"
    fi
else
    echo "✗ Configuration file not found at $CONFIG_FILE"
    echo "  Run the setup command to create it"
    exit 1
fi

if pgrep -i figma > /dev/null; then
    echo "✓ Figma is running"
else
    echo "⚠ Figma is not running (required for Figma MCP)"
fi

if which npx > /dev/null; then
    echo "✓ npx is available"
else
    echo "✗ npx not found (required for MCP servers)"
    echo "  Install Node.js to get npx"
fi

echo ""
echo "If all checks pass, restart Claude Code to enable MCP servers"
```

## References

- [MCP Protocol Specification](https://modelcontextprotocol.io)
- [Figma Dev Mode Documentation](https://www.figma.com/developers/api#dev-mode)
- [Claude Desktop Configuration](https://claude.ai/docs/desktop-configuration)