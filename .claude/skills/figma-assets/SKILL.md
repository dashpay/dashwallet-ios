---
name: figma-assets
description: Set up the Figma Dev Mode MCP server and clean Figma-exported SVG assets for iOS. Use when pulling designs or icons from Figma, adding assets to AppAssets.xcassets, or when an added SVG icon renders blank.
---

# Figma MCP setup & asset cleaning

## MCP / Figma Setup

This project uses the Figma Dev Mode MCP server, configured in `.mcp.json` (`http://127.0.0.1:3845/mcp`). To use it:

1. Run Figma Desktop, enable Dev Mode (`Shift+D`), and click "Enable desktop MCP server" in the inspect panel.
2. Restart Claude Code — MCP servers connect only at startup.
3. Verify the server responds: `curl -s http://127.0.0.1:3845/mcp`

## Figma MCP assets need cleaning for iOS

Figma MCP serves assets at ephemeral `http://localhost:3845/assets/{hash}.svg` URLs (valid only while Figma Desktop + Dev Mode are running). Download them into the asset catalog (`DashWallet/Resources/AppAssets.xcassets/...`) — never reference localhost URLs in code. Then strip web-only SVG features iOS can't render:

- `fill="var(--fill-0, #78C4F5)"` → `fill="#78C4F5"` (CSS variables render invisible)
- `width="100%" height="100%"` → explicit pixel dimensions from the viewBox
- remove `preserveAspectRatio="none"`, `style="display: block;"`, `overflow="visible"`

If icons appear blank after adding an SVG, check for `var(--fill-0, ...)` or `width="100%"` first.
