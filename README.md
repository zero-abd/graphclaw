<div align="center">
  <h1>⚡ Graphclaw</h1>
  <p><strong>Graph-native AI assistant runtime in Jac</strong></p>
  <p>
    <img src="https://img.shields.io/badge/jac-0.13.5-blueviolet" alt="Jac">
    <img src="https://img.shields.io/badge/python-3.12%2B-blue" alt="Python 3.12+">
    <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
    <img src="https://img.shields.io/badge/status-alpha-orange" alt="Status">
  </p>
</div>

**Graphclaw** is a graph-native AI assistant runtime where memory is stored as a live knowledge graph, tools are exposed through Jac and Python, and skills plus MCP servers can be attached at runtime. It is written in **[Jac](https://www.jac-lang.org/)** and runs on top of the current Jaseci/Jac toolchain.

Inspired by **[nanobot](https://github.com/HKUDS/nanobot)** and **[openclaw](https://github.com/openclaw/openclaw)**, Graphclaw keeps the agent experience local and extensible while leaning hard into graph memory, Jac-native control surfaces, OpenClaw-style skills, and MCP integration.

---

## Why Graphclaw

|  | nanobot | openclaw | **Graphclaw** |
|---|---|---|---|
| Language | Python | TypeScript | **Jac + Python** |
| Core memory | Flat markdown | Files + runtime state | **Workspace-backed knowledge graph** |
| Skills | Prompt/files | SKILL.md ecosystem | **Native skills + OpenClaw-style SKILL.md + ClawHub** |
| MCP support | Limited / external | Core concept | **Configured MCP servers exposed to all agents** |
| Browser automation | Usually external | Growing ecosystem | **Playwright-backed browser helpers** |
| Dashboard | External / ad hoc | Web-first control UI | **Jac-native dashboard app** |
| Initial graph state | Usually empty | Tool/runtime first | **Seeded root graph with identity, skills, MCP, dream cadence** |

---

## Features

### 🧠 Graph memory from the first launch
- Root assistant graph is seeded immediately
- Built-in identity nodes include:
  - root
  - name
  - identity
  - soul
  - conversation cadence
  - dream cadence
- Skills and MCP now also live in the root graph as capability subtrees
- Sessions, turns, consolidated memories, and dream maintenance extend the graph over time

### 🤖 Multi-agent runtime
Graphclaw routes work through specialist agents:
- **Coordinator runtime** — routes intent and keeps identity consistent
- **DevOps** — deployment, infra, builders, skill/MCP operations
- **Planner** — planning and breakdown
- **Builder** — implementation and editing
- **Researcher** — research, search, synthesis

These agents now share:
- OpenClaw-style skill runtime
- MCP runtime access where relevant
- shared graph memory context

### 🔌 Skills system
Graphclaw supports:
- **native skills** via `skill.json` + `skill.py`
- **workflow skills** via `SKILL.md`
- **ClawHub installation/update flows**
- workspace/shared/bundled precedence similar to OpenClaw-style skill selection

### 🔗 MCP support
Configured MCP servers are exposed through runtime tools such as:
- listing servers
- refreshing MCP catalogs
- listing tools/resources/prompts
- calling MCP tools
- reading MCP resources
- resolving MCP prompts

### 🌐 Channels
Current channel integrations include:
- Telegram
- Discord
- Slack
- Email
- WhatsApp bridge

### 🧪 Jac-native dashboard
The local dashboard is a real Jac client app and includes:
- Overview
- Sessions
- Channels
- Skills
- Graph Memory

### 🖥 Browser automation helpers
Graphclaw includes Playwright-backed browser helpers for:
- screenshots
- browser progress capture
- automation support for builder/platform flows

---

## Install

**Requirements:**
- **[Python 3.12+](https://docs.python.org/3.12/)**
- **[Git](https://git-scm.com/)**

**Linux / macOS / WSL:**
```bash
curl -fsSL https://raw.githubusercontent.com/zero-abd/graphclaw/main/install.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/zero-abd/graphclaw/main/install.ps1 | iex
```

**Local clone:**
```bash
git clone https://github.com/zero-abd/graphclaw
cd graphclaw
bash install.sh
```

The installer configures:
1. deployment mode
2. default model provider
3. first chat channel
4. optional builder skill credentials

Then launch:
```bash
graphclaw
```

Windows:
```powershell
graphclaw
```

---

## Quick start

### Interactive local mode
```bash
graphclaw
```

In the normal interactive single-user flow Graphclaw will:
- start the runtime
- start the local dashboard if enabled
- fall back to CLI chat when no channel is enabled

### Local dashboard
By default, the local dashboard runs at:
```text
http://127.0.0.1:18789/
```

### API / hosted mode
```bash
jac start graphclaw/main.jac
```

### Local Jac fallback
If the toolchain needs the safer local execution path:
```bash
jac run --no-autonative graphclaw/main.jac
```

---

## Memory model

Graphclaw's graph starts with seeded assistant structure, then grows through use:

```text
assistant_root
├── assistant_name
├── assistant_identity
├── assistant_soul
├── assistant_conversation_cadence
├── assistant_dream_cadence
├── assistant_skills_root
│   ├── assistant_skills_inherent
│   ├── assistant_skills_clawhub
│   ├── assistant_skills_workspace
│   └── assistant_skills_shared
└── assistant_mcp_root
    ├── assistant_mcp_servers
    ├── assistant_mcp_tools
    ├── assistant_mcp_resources
    └── assistant_mcp_prompts
```

As conversations happen, Graphclaw adds:
- sessions
- turns
- consolidated memory nodes
- relationships
- topic tags

And every 2 hours **Dream** can:
- decay confidence
- revalidate memory
- tag untagged nodes
- tombstone stale memories

---

## Skills

Graphclaw uses two skill styles:

### Native skills
```text
graphclaw/skills/registry/<skill>/
├── skill.json
└── skill.py
```

### OpenClaw-style workflow skills
```text
<skill>/SKILL.md
```

The runtime supports:
- listing installed skills
- recommending skills semantically
- invoking skill workflows
- approval-aware skill installation
- updating installed skills

Built-in examples include:
- `base44`
- `loveable`

---

## MCP

Graphclaw reads MCP configuration from `mcpServers` / `mcp_servers` config and exposes that runtime to agents.

Example shape:

```json
{
  "mcpServers": {
    "filesystem": {
      "enabled": true,
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/root"]
    }
  }
}
```

At runtime Graphclaw can cache and expose:
- server summaries
- MCP tools
- resources
- prompts

---

## Channels

| Channel | Notes |
|---|---|
| Telegram | pairing / allowlist aware |
| Discord | pairing / allowlist aware |
| Slack | bot + app token |
| Email | IMAP / SMTP |
| WhatsApp | bridge-based |

Telegram and Discord default to safer OpenClaw-style posture:
- pairing for unknown DMs
- allowlist for groups
- optional owner approvals

Local approval commands:
```text
pairing list telegram
pairing approve telegram <code>
```

---

## Providers

Default provider flow is built around **[OpenRouter](https://openrouter.ai/)**, but the config/provider registry supports the broader OpenAI-compatible ecosystem.

Example:
```json
{
  "providers": {
    "default_provider": "openrouter",
    "openrouter": { "api_key": "sk-or-...", "base_url": "https://openrouter.ai/api/v1" },
    "anthropic": { "api_key": "sk-ant-..." },
    "openai": { "api_key": "sk-..." }
  },
  "agents": {
    "model": "openrouter/anthropic/claude-sonnet-4-6"
  }
}
```

---

## Configuration

Main config lives at:
```text
~/.graphclaw/config.json
```

Key sections:
- `workspace`
- `providers`
- `agents`
- `channels`
- `skills`
- `dashboard`
- `mcpServers`

---

## Project structure

```text
graphclaw/
├── graphclaw/
│   ├── main.jac
│   ├── agents/
│   ├── browser/
│   ├── channels/
│   ├── config/
│   ├── dashboard.jac
│   ├── dashboard_app/
│   ├── mcp/
│   ├── memory/
│   ├── providers/
│   ├── skills/
│   └── tools/
├── install.sh
├── install.ps1
├── jac.toml
├── pyproject.toml
└── README.md
```

---

## Built on

- **[Jac](https://www.jac-lang.org/)**
- **[Jaseci Docs](https://docs.jaseci.org/)**
- **[LiteLLM](https://github.com/BerriAI/litellm)**
- Inspired by **[nanobot](https://github.com/HKUDS/nanobot)** and **[openclaw](https://github.com/openclaw/openclaw)**

---

## Roadmap

- [x] Jac-native local dashboard
- [x] OpenClaw-style skills + ClawHub integration
- [x] MCP runtime support
- [x] Seeded root graph for identity / skills / MCP
- [ ] richer graph visualization and live graph operations
- [ ] more builder/platform skills
- [ ] stronger hosted multi-user story

---

## Contributing

Graphclaw is alpha and evolving fast. PRs are welcome.

Good places to contribute:
- new native skills
- OpenClaw-style workflow skills
- MCP integrations
- dashboard improvements
- graph-memory/runtime tooling

---

**MIT License**
