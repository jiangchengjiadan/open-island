# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Open Island is a macOS "Dynamic Island" style AI Agent monitoring tool. It displays a floating panel near the MacBook notch area to monitor multiple AI coding assistants (Claude Code, Codex, Cursor, Gemini CLI) in real-time, with permission approval capabilities.

## Architecture

The system has three components communicating via Unix Domain Sockets:

```
┌─────────────────┐     Unix Socket      ┌──────────────────┐
│  AI Tools       │◄──────────────────► │   Bridge Server  │
│  (Claude, etc)  │    /tmp/notch-      │   (Node.js)      │
│  + Hook Scripts │      monitor.sock   │                  │
└─────────────────┘                     └────────┬─────────┘
                                                 │ Unix Socket
                                                 ▼
                                        ┌──────────────────┐
                                        │  Native macOS    │
                                        │  App (SwiftUI)   │
                                        │  - NotchPanel    │
                                        │  - SocketService │
                                        └──────────────────┘
```

### Components

- **native/NotchMonitor/**: SwiftUI macOS app (macOS 13+). Displays the floating panel with agent cards. Entry point: `NotchMonitorApp.swift`. Uses `SocketService` singleton for communication.

- **bridge/**: Node.js Unix Socket server. Manages agent registration, status updates, and permission request/response routing. Main files: `server.js` (server), `hook.js` (client library for AI tools).

- **scripts/install-hooks.sh**: Installs dependencies and configures Claude Code hooks in `~/.claude/settings.json`.

## Build & Run Commands

### Bridge Server (Node.js)
```bash
cd bridge
npm install          # Install dependencies
npm start            # Run server (node server.js)
npm run dev          # Run with nodemon for development
```

### Native macOS App (Swift)
```bash
cd native/NotchMonitor
swift build          # Build the app
swift run NotchMonitor   # Run the app
```

### Full Installation
```bash
./scripts/install-hooks.sh   # Installs bridge deps, configures hooks, creates the `open-island` launcher
open-island start            # Starts the app via the generated launcher
```

## Message Protocol (Unix Socket JSON)

Messages exchanged over the socket are newline-delimited JSON:

| Type | Direction | Description |
|------|-----------|-------------|
| `agent_register` | Hook → Server | Register a new agent session |
| `agent_update` | Hook → Server | Update agent status/task |
| `agent_unregister` | Hook → Server | Remove agent |
| `permission_request` | Hook → Server | Request user permission |
| `permission_response` | Server → Hook | User's permission decision |
| `agent_registered`, `agent_updated`, `agent_unregistered` | Server → App | Broadcasts to UI |
| `permission_requested`, `permission_responded` | Server → App | Permission flow events |

## Key Files

- `bridge/server.js`: `NotchMonitorServer` class - handles socket connections, agent state, message routing
- `bridge/hook.js`: `NotchMonitorHook` class - client library for AI tools to connect and communicate
- `native/NotchMonitor/Sources/Services/SocketService.swift`: Observable service managing agent state for SwiftUI
- `native/NotchMonitor/Sources/Views/NotchPanel.swift`: Main UI with agent cards, status dots, permission badges
- `native/NotchMonitor/Sources/Models/Agent.swift`: Data models (Agent, AgentType, AgentStatus, PermissionRequest)

## Design System

Colors defined in README.md:
- Background: `#1a1a2e`
- Card: `#252542`
- Purple accent: `#8b5cf6`
- Indigo accent: `#6366f1`
- Success (running): `#10b981`
- Waiting: `#f59e0b`
- Error: `#ef4444`

Agent-specific colors are defined in `AgentType.color` in Agent.swift.
