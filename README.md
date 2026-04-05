<div align="center">
  <h1>⚡ Graphclaw</h1>
  <p><strong>Graph-native multi-agent AI platform — built entirely in Jac</strong></p>
  <p>
    <img src="https://img.shields.io/badge/jac-0.13.5-blueviolet" alt="Jac">
    <img src="https://img.shields.io/badge/python-≥3.12-blue" alt="Python">
    <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
    <img src="https://img.shields.io/badge/status-alpha-orange" alt="Status">
    <a href="https://discord.gg/graphclaw"><img src="https://img.shields.io/badge/Discord-Community-5865F2?style=flat&logo=discord&logoColor=white" alt="Discord"></a>
  </p>
</div>

**Graphclaw** is a multi-agent AI platform where memory lives in a property graph, agents are graph walkers, and skills can be installed from the internet at runtime — all written in **[Jac](https://www.jac-lang.org/)**, the AI-native full-stack language built on Jaseci.

Inspired by [nanobot](https://github.com/HKUDS/nanobot) and [openclaw](https://github.com/openclaw/openclaw). Graphclaw replaces the flat-file memory model with a live, decaying, self-maintaining graph — and adds a coordinator that routes tasks across a team of specialist agents.

---

## Why Graphclaw

|  | nanobot | openclaw | **Graphclaw** |
|---|---|---|---|
| Language | Python | TypeScript | **Jac (compiles to Python)** |
| Memory | Flat `.md` files | File-based | **OSP property graph** |
| Memory recall | LLM summarization | File scan | **Indexed graph traversal + optional semantic** |
| Agents | Single agent | Single agent | **Multi-agent (Coordinator, DevOps, Planner, Builder, Researcher)** |
| Skills | SKILL.md files | ClawHub | **Dynamic directory + online GitHub install** |
| Multi-user | No | No | **Yes — per-user root graph, JWT auth** |
| Deployment | pip | pip | **`jac run` → `jac start` → `jac start --scale` (Kubernetes)** |
| AI functions | LLM calls | LLM calls | **`by llm()` — Meaning Typed Programming** |

---

## Features

🧠 **Graph Memory** — Facts live as typed nodes (`User`, `Feedback`, `Project`, `Reference`) with confidence scores that decay over time. The `Dream` walker runs in the background, merging duplicates, linking contradictions, and pruning stale nodes — without rewriting a blob of markdown.

🤖 **Multi-Agent Team** — A `Coordinator` agent classifies your intent and routes to the right specialist:
- **DevOps** — deployments, infra, CI/CD, Base44, Loveable
- **Planner** — task breakdown, project management, priorities
- **Builder** — code writing, file editing, shell, git
- **Researcher** — web search, knowledge extraction, memory synthesis

🔌 **Skill Directory** — Skills are self-contained modules with a `skill.json` manifest and a `skill.py` tool file. Install new skills at runtime from any GitHub URL or the central registry — no restart needed.

⚡ **Jac OSP** — Nodes connected to `root` auto-persist. Per-user isolation is built in. Walkers traverse data instead of pulling it to logic.

🌐 **5 Channels** — Telegram, Discord, Slack, Email, WhatsApp. One message bus routes everything.

🔑 **Multi-Provider** — OpenRouter (default), Anthropic, OpenAI, DeepSeek, Groq, Ollama, and any OpenAI-compatible endpoint.

---

## Install

```bash
git clone https://github.com/graphclaw/graphclaw
cd graphclaw
bash install.sh
```

The installer will ask you:
1. **Deployment mode** — single-user (personal) or multi-user (hosted)
2. **LLM provider** — OpenRouter, Anthropic, OpenAI, or Ollama
3. **Channels** — Telegram, Discord, Slack tokens
4. **Skill API keys** — Base44, Loveable (optional, add later)

Then start:

```bash
graphclaw          # CLI mode (no channels configured)
# or
~/.graphclaw/run.sh
```

---

## Quick Start

**CLI mode:**
```bash
graphclaw
> deploy my app to base44
> [devops] Checking Base44 apps... deploying graphclaw-demo... done ✓
```

**As an HTTP server (multi-user):**
```bash
jac start graphclaw/main.jac   # → http://localhost:8000
```

**Scale to Kubernetes:**
```bash
jac start --scale graphclaw/main.jac
```

---

## Memory

Memory is a graph, not a file. Every fact is a node:

```
root
 ├──[:HasMemory]──▶ Memory { content, type, confidence: 0.9, decay_rate: 0.01 }
 ├──[:HasSession]──▶ Session ──[:HasTurn]──▶ Turn
 └──▶ Topic ──[:Tagged]──▶ Memory
           Memory ──[:Relates { contradicts | refines | derived_from }]──▶ Memory
```

**Confidence decay** — every memory loses `0.01` confidence per day since last validation. After ~90 days without revalidation a fact is considered stale and tombstoned by `Dream`.

**Dual recall** — substring match by default (fast), semantic recall via `by llm()` on demand:
```
agent.recall("deployment strategy")          # substring
agent.recall("deployment strategy", semantic=True)   # + LLM semantic check
```

**Dream** runs every 2 hours:
- Tombstones zero-confidence nodes
- Merges near-duplicate facts
- Links contradicting memories with `[:Relates { contradicts }]` edges
- Auto-tags untagged memories with topic nodes
- Revalidates still-accurate decaying memories

---

## Skills

Each skill is a directory:

```
skills/registry/
└── base44/
    ├── skill.json    ← manifest (name, description, tools list)
    └── skill.py      ← async Python tool functions
```

**Built-in skills:** `base44`, `loveable`

**Install a skill online:**
```
> install the kubernetes skill
[devops] Installing skill 'kubernetes' from registry...
✓ Skill installed — tools: apply_manifest, get_pods, scale_deployment, get_logs...
```

Or directly:
```python
InstallSkill(source="kubernetes") spawn root
InstallSkill(source="https://github.com/myorg/skills-registry") spawn root
```

**Skills the DevOps agent can tap into:**

| Skill | Tools |
|---|---|
| `base44` | `deploy_app`, `get_build_logs`, `get_app_status`, `update_env_vars`, `restart_app`, `rollback_app` |
| `loveable` | `create_project`, `publish_project`, `send_prompt`, `get_project_status`, `get_chat_history` |
| `kubernetes` *(install)* | `apply_manifest`, `get_pods`, `scale_deployment`, `get_logs` |
| *any GitHub repo* | whatever it exports |

---

## Agents

```
User message
    │
    ▼
CoordinatorAgent
    │  classify_intent() by llm()
    ├──▶ DevOpsAgent    — infra, deployments, Base44, Loveable, shell
    ├──▶ PlannerAgent   — task breakdown, project plans, priorities
    ├──▶ BuilderAgent   — code, file edits, shell, git
    └──▶ ResearcherAgent — web search, knowledge extraction
```

All agents share the same memory graph. DevOps leaving a fact about a failed deployment is immediately visible to Coordinator on the next turn.

---

## Channels

| Channel | Setup |
|---|---|
| Telegram | `TELEGRAM_BOT_TOKEN` |
| Discord | `DISCORD_BOT_TOKEN` |
| Slack | `SLACK_BOT_TOKEN` + `SLACK_APP_TOKEN` |
| Email | SMTP + IMAP credentials |
| WhatsApp | Node.js Baileys bridge (`cd bridge && npm start`) |

Configure in `~/.graphclaw/config.json` or via `install.sh`.

---

## Providers

Default: **OpenRouter** — one API key, access to every major model.

```json
{
  "providers": {
    "openrouter": { "api_key": "sk-or-..." },
    "anthropic":  { "api_key": "sk-ant-..." },
    "openai":     { "api_key": "sk-..." },
    "ollama":     { "base_url": "http://localhost:11434" }
  },
  "agents": {
    "model": "openrouter/anthropic/claude-sonnet-4-6"
  }
}
```

Supported: OpenRouter, Anthropic, OpenAI, DeepSeek, Groq, Gemini, Mistral, Ollama, vLLM, Azure OpenAI, and any OpenAI-compatible endpoint.

---

## Configuration

Full config at `~/.graphclaw/config.json`. Key fields:

```json
{
  "workspace": "~/.graphclaw/workspace",
  "multi_user": false,
  "agents": {
    "model": "openrouter/anthropic/claude-sonnet-4-6",
    "max_tokens": 8192,
    "temperature": 0.7,
    "max_tool_iterations": 200,
    "dream": {
      "enabled": true,
      "interval_hours": 2
    }
  },
  "skills": {
    "registry_url": "https://raw.githubusercontent.com/graphclaw/skills-registry/main/index.json"
  }
}
```

---

## Multi-User Mode

Set during install or flip `"multi_user": true` in config. Each user gets:
- An isolated `root` graph (memories don't leak between users)
- JWT authentication (set `AUTH_SECRET_KEY` env var)
- Per-user session history

Run as an API server:
```bash
jac start graphclaw/main.jac   # → http://localhost:8000/docs
```

---

## Project Structure

```
graphclaw/
├── graphclaw/
│   ├── main.jac              Entry point
│   ├── config/               Config schema + loader
│   ├── memory/               Graph schema, store, recall, consolidate, dream
│   ├── agents/               Coordinator, DevOps, Planner, Builder, Researcher
│   ├── channels/             Bus, Telegram, Discord, Slack, Email, WhatsApp
│   ├── providers/            LLM provider abstraction + registry
│   ├── tools/                Shell, filesystem, web search/fetch
│   └── skills/
│       ├── loader.jac        Dynamic skill loading + online install
│       └── registry/         Built-in skills (base44, loveable)
├── bridge/                   WhatsApp Node.js bridge (Baileys)
├── install.sh                Setup wizard
├── jac.toml                  Jac project config
└── pyproject.toml            Python dependencies
```

---

## Built on

- **[Jac / Jaseci](https://docs.jaseci.org/)** — AI-native full-stack language
- **[byLLM](https://docs.jaseci.org/learn/jac-byllm/)** — Meaning Typed Programming (`by llm()`)
- **[LiteLLM](https://github.com/BerriAI/litellm)** — multi-provider LLM routing
- Inspired by **[nanobot](https://github.com/HKUDS/nanobot)** and **[openclaw](https://github.com/openclaw/openclaw)**

---

## Roadmap

- [ ] CLI (`graphclaw run`, `graphclaw skill install`, `graphclaw memory`)
- [ ] `graphclaw/skills-registry` — public community skill repository
- [ ] More DevOps skills: Kubernetes, Docker, GitHub Actions, Vercel, Railway, AWS
- [ ] Streaming output to channels
- [ ] Web UI (Jac `cl {}` codespace — React frontend auto-generated)
- [ ] `jac start --scale` Kubernetes deployment guide

---

## Contributing

Graphclaw is in alpha. PRs welcome — especially new skills in `graphclaw/skills/registry/`.

Each skill needs:
- `skill.json` — manifest with `name`, `description`, `tools`, `requirements`
- `skill.py` — async Python functions, one per tool

See `graphclaw/skills/registry/base44/` as a reference.

---

**MIT License**
