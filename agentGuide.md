# Claude Team Agents — Setup & Usage Guide

Complete guide to install the autonomous agent team into any project, from zero.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Copy to Your Project](#2-copy-to-your-project) (or just run `setup.sh`)
3. [Configure Credentials](#3-configure-credentials)
4. [Setup Telegram Bot](#4-setup-telegram-bot)
5. [Apply Orchestrator Patch](#5-apply-orchestrator-patch) (auto if using `setup.sh`)
6. [Running Modes](#6-running-modes)
7. [Telegram Commands](#7-telegram-commands)
8. [Pipeline Workflow](#8-pipeline-workflow)
9. [Agent Reference](#9-agent-reference)
10. [Hooks Reference](#10-hooks-reference)
11. [Skills Reference](#11-skills-reference)
12. [Troubleshooting](#12-troubleshooting)
13. [Usage Scenarios](#13-usage-scenarios)
14. [Docker-First Architecture](#14-docker-first-architecture)
15. [Context Resilience Protocol](#15-context-resilience-protocol)
16. [Environment-Specific Setup](#16-environment-specific-setup)
17. [Quick Reference Card](#17-quick-reference-card)

---

## 1. Prerequisites

### System Requirements

- **Claude Code CLI** v2.1.80+ installed and authenticated
- **Bun** runtime installed (required by native channel plugins)
- **Bash** shell (Linux, macOS, or WSL on Windows)
- **tmux** installed (required for Telegram bidirectional mode)
- **jq** installed (JSON processing in hooks and daemon) — v1.6+
- **curl** installed (Telegram API calls)
- **Git** 2.35+ initialized in your project (required for worktree support)
- **Docker** 24+ and **Docker Compose** v2+ (recommended for most stacks)
- **Node** 18+ (for hooks that use npx)

### Install Missing Tools

```bash
# Ubuntu/Debian/WSL
sudo apt install tmux jq curl git
curl -fsSL https://bun.sh/install | bash

# macOS
brew install tmux jq curl git bun

# Docker (if not installed)
curl -fsSL https://get.docker.com | sh
```

### Verify Claude Code

```bash
claude --version
# Should be v2.1.80 or higher

# Verify Opus model access (required for Agent Teams)
claude --model opus
```

### Claude Code Plan

Agent Teams require a **Claude Max plan** or **API key with Opus 4.6 access**.

### Git Global Config

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

# For signed commits (optional but recommended)
git config --global commit.gpgsign true
```

---

## 2. Copy to Your Project

### Quick Setup (Recommended)

Run the setup script — it handles everything automatically:

```bash
cd /path/to/claude-team-agents
chmod +x setup.sh
./setup.sh /path/to/your-project
```

The script will:
1. Copy `.claude/` and `docs/` to your project
2. Clean all runtime state files (PIDs, logs, queues)
3. Make all scripts executable
4. Apply the orchestrator approve-gate patch
5. Update `.gitignore` with required entries
6. Verify the setup and show a summary

### Manual Setup (if you prefer)

<details>
<summary>Click to expand manual steps</summary>

#### Step 1: Copy the .claude directory

```bash
cp -r .claude /path/to/<YOUR_PROJECT>/.claude
cp -r docs /path/to/<YOUR_PROJECT>/docs 2>/dev/null
```

#### Step 2: Clean runtime state files

```bash
cd /path/to/<YOUR_PROJECT>
rm -f .claude/telegram/daemon.pid .claude/telegram/injector.pid
rm -f .claude/telegram/daemon.log .claude/telegram/injector.log
rm -f .claude/telegram/channel-mode.env .claude/hooks/hook-log.txt
rm -f .claude/telegram/pending-questions/q-*.json
rm -f .claude/telegram/responses/*.json
```

#### Step 3: Make scripts executable

```bash
chmod +x .claude/telegram/*.sh .claude/hooks/*.sh .claude/scripts/*.sh
```

#### Step 4: Verify structure

```bash
ls .claude/
# Expected: agents/ commands/ hooks/ memory/ scripts/ skills/ telegram/
```

</details>

---

## 3. Configure Credentials

### Option A: Via settings.local.json (Recommended)

Edit `.claude/settings.local.json` to add your credentials in the `env` block. These are injected as environment variables into Claude Code sessions.

```json
{
  "env": {
    "TELEGRAM_BOT_TOKEN": "your-bot-token-here",
    "TELEGRAM_CHAT_ID": "your-chat-id-here",
    "GITLAB_TOKEN": "your-gitlab-token-here",
    "GITLAB_REPO_URL": "https://gitlab.com/your/repo"
  },
  "permissions": {
    "allow": [
      "Bash(chmod +x .claude/telegram/*.sh)",
      "Bash(bash .claude/telegram/manage.sh stop)",
      "Bash(bash .claude/telegram/manage.sh start)",
      "Bash(bash .claude/telegram/manage.sh start-channels)",
      "Bash(bash .claude/telegram/manage.sh status)"
    ]
  }
}
```

**Note**: `settings.local.json` is per-machine and should NOT be committed to git. Add it to `.gitignore`:

```bash
echo ".claude/settings.local.json" >> .gitignore
```

### Option B: Via .env file

Create a `.env` file in your project root with the minimum required credentials:

```bash
# ========================
# GIT PLATFORM (choose one)
# ========================

# For GitLab:
GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxx
GITLAB_REPO_URL=https://gitlab.com/username/repo-name

# For GitHub:
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
GITHUB_REPO_URL=https://github.com/username/repo-name

# ========================
# DATABASE (fill as needed)
# ========================
DB_ENGINE=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=myapp
DB_USERNAME=root
DB_PASSWORD=secret

# ========================
# TELEGRAM BOT (full two-way communication)
# ========================
TELEGRAM_BOT_TOKEN=your-bot-token-here
TELEGRAM_CHAT_ID=your-chat-id-here
```

**Important**: Never commit `.env` to git. The `security-gate.sh` hook blocks this automatically.

**Note**: If you used `setup.sh`, `.gitignore` entries are already added. If not, add manually:

```bash
echo -e ".env\n.env.*\n.claude/settings.local.json\n.claude/hooks/hook-log.txt\ndocs/token-reports/" >> .gitignore
```

**Token permissions by platform:**

| Platform | Where to create | Required scopes |
|----------|----------------|-----------------|
| GitLab | User Settings → Access Tokens → Create | `api`, `read_repository`, `write_repository` |
| GitHub | Settings → Developer Settings → Personal Access Tokens | `repo` (full control) |

### Option C: Use both (most robust)

Put credentials in both `settings.local.json` AND `.env`. This ensures:
- Inside Claude Code sessions: reads from `settings.local.json` env vars
- Standalone daemon (outside Claude): reads from `.env` file

---

## 4. Setup Telegram Bot

### Step 1: Create a bot

1. Open Telegram and search for `@BotFather`
2. Send `/newbot`
3. Follow prompts to name your bot (e.g. "My CI Bot") and set a username (e.g. `myproject_ci_bot`)
4. Copy the **bot token** (looks like `1234567890:ABCdefGHIjklMNOpqrsTUVwxyz`)
5. Keep this token private — do not share it

### Step 2: Get your Chat ID

1. Search for `@userinfobot` in Telegram
2. Send `/start` to it
3. It replies with your **Chat ID** (a number like `5211366883`)

Alternatively, get it automatically from the terminal:

```bash
# Send any message to your bot first, then:
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | jq '.result[0].message.chat.id'
```

### Step 3: Run the setup wizard

```bash
cd /path/to/your-project
bash .claude/telegram/setup-telegram.sh
```

This will:
- Validate your bot token
- Detect or ask for your chat ID
- Write credentials to `.env` (if not using settings.local.json)
- Register bot commands with Telegram (`/status`, `/approve`, `/reject`, `/log`, `/retro`)
- Send a test message to verify

### Step 4: Verify bot works

Check Telegram — you should receive a message: "Telegram bot ready."

If you already have credentials in `settings.local.json`, you can skip the wizard and just register commands:

```bash
# Set vars temporarily for registration
export TELEGRAM_BOT_TOKEN="your-token"
export TELEGRAM_CHAT_ID="your-chat-id"
bash .claude/telegram/setup-telegram.sh
```

### Step 5: Verify

After the daemon starts, type `/status` in your Telegram bot. If a reply appears, setup succeeded.

### Notifications Sent by the Bot

| Event | When | Example message |
|-------|------|----------------|
| Pipeline start | After context analysis | `Pipeline Started: GREENFIELD, 5 features, 3 waves` |
| Security block | When hook blocks an operation | `SECURITY BLOCK: Agent be-developer tried git push main` |
| PR ready | After PR is created | `PR Ready: feat/user-auth → main. URL: gitlab.com/...` |
| Pipeline complete | After all work is done | `Pipeline Complete: 45 minutes, 5 features` |

---

## 5. Apply Orchestrator Patch

**If you used `setup.sh`**: this is already done automatically. Skip to section 6.

**If you set up manually**: the orchestrator needs a channel-aware approve gate patch.

```bash
# From the claude-team-agents source directory:
chmod +x setup.sh
./setup.sh /path/to/your-project   # applies patch as part of setup
```

Or apply manually: see `patches/orchestrator-approve-gate.md` for the replacement content.

---

## 6. Running Modes

### Mode 1: Terminal Only (no Telegram)

Standard Claude Code — no bot, no notifications:

```bash
cd /path/to/your-project
claude
```

Then type `/start <your task>` in the terminal.

### Mode 2: Terminal + Custom Telegram (file-queue mode)

Uses bot-daemon + response-injector for Telegram integration. Requires tmux.

```bash
# Start manually
bash .claude/telegram/manage.sh start   # starts daemon + injector
claude                                   # run Claude Code in same tmux

# OR use the auto-wrapper (recommended)
bash .claude/telegram/claude-agent.sh
```

The wrapper automatically:
1. Creates a tmux session `claude-agent`
2. Starts bot-daemon and response-injector
3. Launches Claude Code
4. Cleans up on exit

**Note**: The orchestrator automatically starts the daemon at the beginning of a pipeline if it is not already running, so you do not have to start it manually every time.

### Mode 3: Terminal + Native Channels (recommended)

Uses Claude Code's native channel plugin for bidirectional Telegram messaging. Best experience.

```bash
# Auto-wrapper detects --channels and configures accordingly
bash .claude/telegram/claude-agent.sh --channels plugin:telegram@claude-plugins-official
```

What happens:
- Bot daemon starts (for /status, /run, /log commands)
- Response injector is SKIPPED (channel handles responses natively)
- `channel-mode.env` is written (hooks detect native mode)
- AskUserQuestion flows through the channel directly to Telegram

**First-time channel setup** (one-time only):

```bash
# Step 1: Install the Telegram plugin (inside Claude Code)
/plugin install telegram@claude-plugins-official

# Step 2: Reload plugins to activate the plugin's slash commands
/reload-plugins

# Step 3: Configure your bot token
# SKIP this step if TELEGRAM_BOT_TOKEN is already set in settings.local.json
/telegram:configure <your-bot-token>

# Step 4: Exit Claude Code, then restart with --channels flag
claude --channels plugin:telegram@claude-plugins-official

# Step 5: Send any message to your bot in Telegram
# The bot replies with a 6-character pairing code

# Step 6: Pair your account (inside Claude Code)
/telegram:access pair <code>

# Step 7: Lock down access so only you can send messages
/telegram:access policy allowlist
```

**Important notes:**
- `/reload-plugins` is required after install, otherwise `/telegram:configure` shows "Unknown skill"
- If `TELEGRAM_BOT_TOKEN` is already in your `settings.local.json` env block, Step 3 is optional
- Pairing is one-time only — it saves your Telegram sender ID to an allowlist
- **Bun** must be installed (the plugin runs as a Bun script)

### Bidirectional Telegram Mode

Beyond `/approve` and `/reject`, you can **answer all Claude Code questions directly from Telegram** — no need to open the terminal.

How it works:
1. Claude Code asks something (approve/reject, choose an option, yes/no)
2. The question appears in the terminal AND in Telegram with inline keyboard buttons
3. You tap a button in Telegram → the answer is automatically typed into the terminal via tmux
4. Claude Code continues — without you needing to open the terminal

```
Telegram:
  ┌─────────────────────────────────────┐
  │  Claude Code — Action Required      │
  │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
  │ Want me to commit and push this?    │
  │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
  │                                     │
  │  [Approve]  [Reject]                │
  └─────────────────────────────────────┘

Tap "Approve" → Claude Code continues automatically.
```

**Dual mode**: You can answer in Telegram OR in the terminal. Whichever arrives first is used.

**Requirement**: Run Claude Code via `claude-agent.sh` (not bare `claude`) so that a tmux session is available for response injection.

**Remote approve flow:**

```
Terminal:
  Claude Code → "Pipeline plan ready. Waiting for APPROVE..."

You in Telegram:
  /status  → view plan summary
  /approve → pipeline continues automatically

  OR

Terminal:
  Type APPROVE directly
```

Both work — Telegram approve and terminal approve. The first one in wins.

### Mode 4: Full Remote (Telegram only, no terminal)

Start the bot daemon, then control everything from Telegram:

```bash
# Start daemon in background
bash .claude/telegram/manage.sh start

# Now use Telegram to trigger pipelines:
# Send: /run Fix the login validation bug
# The daemon creates a tmux session with Claude Code + channels
```

To check if it's running:

```bash
bash .claude/telegram/manage.sh status
```

### Windows (PowerShell)

```powershell
# From your project directory — one command, fully automatic:
powershell -ExecutionPolicy Bypass -File .claude\telegram\claude-agent.ps1

# This script automatically:
# 1. Starts bot daemon via WSL (reuses bash scripts)
# 2. Starts response injector (PowerShell SendKeys)
# 3. Launches Claude Code
# 4. Cleans up on exit
```

**Differences from WSL2/Linux:**
- Does not use tmux — uses Windows `SendKeys` API instead
- Bot daemon still runs via WSL (`wsl bash ...`)
- **Terminal must be in the foreground** when a Telegram response arrives (SendKeys needs focus)
- Hook `ask-question-bridge.sh` still runs because Claude Code hooks use bash via WSL

**When to use which:**

| Environment | Command | Use Case |
|-------------|---------|----------|
| WSL2/Linux | `bash .claude/telegram/claude-agent.sh` | Docker projects, Linux apps, server-side |
| PowerShell | `powershell -File .claude\telegram\claude-agent.ps1` | Windows automation, Office Add-ins, desktop apps |

---

## 7. Telegram Commands

Once the bot daemon is running, use these commands in Telegram:

| Command | Description |
|---------|-------------|
| `/status` | Show pipeline status, channel mode, pending questions |
| `/approve` | Approve a waiting pipeline (approve gate) |
| `/reject` | Reject and stop pipeline |
| `/run <task>` | Start a new pipeline remotely |
| `/cancel` | Kill the running pipeline session |
| `/queue` | Show queued/pending tasks |
| `/log` | Show last 10 hook log entries |
| `/retro` | Trigger retrospective analysis |

### Sending a Brief

Send a `.docx` file directly to the bot in Telegram. The daemon will:
1. Download the file to `briefs/` directory
2. Auto-start a pipeline with the brief
3. Notify you when it starts

You can add a caption to the document — it becomes the task description.

### Answering Questions

When Claude asks a question (via AskUserQuestion), it appears in Telegram with inline keyboard buttons. Tap a button to answer. You can also type free text — it routes to the most recent pending question.

---

## 8. Pipeline Workflow

### Starting a Pipeline

```
/start <input>
```

Input can be:
- **Text description**: `/start Add user authentication with JWT`
- **Brief file reference**: `/start briefs/feature-spec.docx`
- **Bug report**: `/start Fix: login page returns 500 on invalid email`
- **Resume**: `/start resume` (continues from last session)
- **Preflight check**: `/start preflight` (validates environment, no pipeline run)

### Pipeline Phases

```
Phase 0: Context Analysis (parallel)
  ├── codebase-scout    → analyzes project structure
  ├── brief-reader      → extracts brief content
  ├── brief-interpreter → translates to technical requirements
  └── pm-agent          → validates completeness

Phase 0A: Docker & Port Assessment (parallel)
  ├── docker-assess.sh  → scan stack, classify Dockerizable vs Host-only services
  └── port-scan-all.sh  → find available ports, write assignments to .env

Phase 0B: Convention & Design (parallel)
  ├── convention-scout  → web searches latest stack docs
  └── design-director   → color, typography, forbidden patterns

Phase 1: Wave Planning
  └── wave-planner      → groups features into dependency-ordered waves

[APPROVE GATE] — You approve the wave plan (terminal or Telegram)

Phase 2: Foundation (greenfield only)
  └── project-initializer → env-configurator → db-designer

Phase 3: Wave Execution (parallel per wave)
  └── For each wave:
      ├── git-manager creates worktrees
      ├── be-developer + fe-developer work in parallel
      ├── git-manager auto-merges to develop
      └── health check

Phase 4: Final Review (parallel)
  ├── code-reviewer     → logic/architecture
  ├── security-check    → security rules
  ├── user-simulator    → browser-based E2E
  └── qa-checklist-runner → systematic test cases

PR Creation
  └── pr-creator        → creates PR (develop → main), never merges
```

### Other Commands

| Command | Purpose |
|---------|---------|
| `/review-and-fix` | Run code review + fix loop on current branch |
| `/review-and-fix --full` | Full codebase review (not just changed files) |
| `/qa-checklist full` | Generate checklist then run it |
| `/qa-checklist generate` | Generate checklist only |
| `/qa-checklist run` | Run existing checklist |
| `/qa-checklist run --file path` | Run from a custom file (.md, .xlsx, .docx, .csv) |
| `/qa-checklist run --file tests.xlsx --data dataset.xlsx` | Run tests using a specific data file |
| `/retro` | Analyze pipeline trends, auto-apply improvements |
| `/retro focus waves` | Retrospective focused on wave performance |
| `/retro focus hooks` | Retrospective focused on hook violations |
| `/clean` | Save session state for clean exit |
| `/compact-lessons` | Archive old lessons, merge duplicates |

---

## 9. Agent Reference

<!-- BEGIN:agent-reference -->
### Planning & Analysis (11 agents)

| Agent | Role |
|-------|------|
| orchestrator | Central coordinator — single entry point, wave execution |
| pm-agent | Product validation — brief completeness, acceptance criteria |
| brief-reader | Extracts .docx/.pdf briefs into structured format |
| brief-interpreter | Translates brief to technical language, detects ambiguities |
| context-loader | Aggregates existing docs and project state |
| codebase-scout | Analyzes codebase structure, finds touch points |
| wave-planner | Groups features into dependency-ordered waves |
| convention-scout | Web searches latest docs per stack |
| design-director | Design decisions (color, typography, forbidden patterns) |
| technical-planner | Per-feature technical specs and task breakdown |
| code-architect | Blueprint generation with file isolation per feature |

### Implementation (2 agents)

| Agent | Role |
|-------|------|
| be-developer | Backend implementation in isolated worktree |
| fe-developer | Frontend implementation in isolated worktree |

### Infrastructure (6 agents)

| Agent | Role |
|-------|------|
| git-manager | 5 modes: pre-flight, branch, base setup, auto-merge, worktree |
| project-initializer | Greenfield project setup (Docker-first) |
| env-configurator | Docker-compose, .env, connection config |
| deployment-doc | Deployment guides and CI/CD templates |
| docker-manager | Container health checks, port assignment |
| db-designer | Database schema, ERD, migrations |

### Quality & Review (8 agents)

| Agent | Role |
|-------|------|
| code-reviewer | Logic/architecture review (hooks handle formatting) |
| user-simulator | Browser automation E2E testing |
| qa-tester | Environment-aware test execution |
| qa-checklist-generator | Auto-generate QA checklist from codebase |
| qa-checklist-interpreter | Normalize checklist format, resolve ambiguities |
| qa-checklist-runner | Execute test cases per environment |
| fix-strategist | Ensures each fix attempt uses a different strategy |
| environment-matrix-runner | Multi-environment test orchestration |

### Documentation & Security (5 agents)

| Agent | Role |
|-------|------|
| doc-updater | Updates documentation after code changes |
| simulation-config-writer | Creates user-simulation-config.md |
| pr-creator | Creates PR (develop to main), NEVER merges |
| security-check | Manages security-config.md rules |
| security-learner | Adaptive security rule learning (24h auto-apply) |

### Special (1 agent)

| Agent | Role |
|-------|------|
| retro-agent | Retrospective analysis, auto-applies improvements |
<!-- END:agent-reference -->

---

## 10. Hooks Reference

<!-- BEGIN:hooks-reference -->
Hooks run as bash scripts at **zero token cost** (no Claude invocation). They enforce rules deterministically.

### PreToolUse (before execution)

| Hook | Trigger | What it does |
|------|---------|--------------|
| security-gate.sh | Bash commands | Blocks: push to main/develop, force push, .env writes, DROP DATABASE, bare npm/pip/composer when Docker is enforced |
| file-protect.sh | Write/Edit files | Blocks: .env, *.key, *.pem, credentials.*, .claude/agents/ |
| ask-question-bridge.sh | AskUserQuestion | Relays questions to Telegram (skipped in native channel mode) |

### PostToolUse (after execution)

| Hook | Trigger | What it does |
|------|---------|--------------|
| auto-format.sh | Write/Edit files | Auto-formats PHP, JS, TS, CSS, Python |
| design-check.sh | Write/Edit files | Enforces design-direction.md compliance |
| test-runner.sh | Write/Edit files | Runs related tests for changed files |

### Lifecycle

| Hook | Trigger | What it does |
|------|---------|--------------|
| notify.sh | Any notification | Sends to Telegram + logs to hook-log.txt |
| session-summary.sh | Session stop | Compiles stats, sends summary to Telegram |
| token-tracker.sh | Session stop | Finalizes token usage report |
<!-- END:hooks-reference -->

---

## 11. Skills Reference

<!-- BEGIN:skills-reference -->
Skills are loaded by agents before implementation. They contain conventions and patterns per stack.

### Stack Conventions
- `laravel-conventions` — PHP/Laravel patterns
- `nodejs-conventions` — Node.js/Express patterns
- `python-conventions` — Python/FastAPI patterns
- `react-conventions` — React/Next.js patterns

### Design & Frontend
- `design-philosophy` — 4 Apple-style design principles
- `frontend-craft` — Typography, color, motion, spatial composition
- `frontend-standards` — Combined design + craft reference

### Infrastructure
- `docker-env` — Docker operations guide
- `project-setup` — Framework initialization procedures
- `db-design` — Database schema design patterns
- `git-operations` — Git workflow and operations

### Quality
- `qa` — QA testing framework
- `qa-checklist` — Checklist generation, interpretation, execution
- `multi-db-testing` — MySQL vs PostgreSQL gotchas
- `ms-addin-testing` — Office Add-in testing patterns

### Pipeline
- `wave-execution` — Team spawning, worktree naming, merge strategy
- `task-breakdown` — Task decomposition format
- `checkpoint-protocol` — Agent pause and approval protocol
- `fix-ledger-protocol` — Fix attempt tracking rules
- `context-resilience` — Context compaction and session resume

### Utilities
- `brief-analysis` — Brief parsing and validation
- `read-docx` — Word document extraction
- `excel` — Spreadsheet processing
- `codebase-explorer` — Codebase analysis patterns
- `convention-research` — Web search templates per stack
- `design-direction` — Design decision framework
<!-- END:skills-reference -->

---

## 12. Troubleshooting

<!-- BEGIN:troubleshooting -->
### Bot daemon won't start

```bash
# Check if already running
bash .claude/telegram/manage.sh status

# Check logs
cat .claude/telegram/daemon.log

# Verify credentials
echo $TELEGRAM_BOT_TOKEN  # should not be empty
echo $TELEGRAM_CHAT_ID    # should not be empty
```

### Telegram messages not arriving

1. Verify bot token: `curl https://api.telegram.org/bot<TOKEN>/getMe`
2. Verify chat ID: send message to bot, then check `curl https://api.telegram.org/bot<TOKEN>/getUpdates`
3. Check daemon is running: `bash .claude/telegram/manage.sh status`

### Questions not relaying to Telegram

- In **custom mode**: Check `ask-question-bridge.sh` is in settings.json hooks
- In **native mode**: Verify `channel-mode.env` exists and PID is alive
- Check: `ls .claude/telegram/pending-questions/` for queued questions
- Verify the hook is executable: `ls -la .claude/hooks/ask-question-bridge.sh`
- Check pending file: `cat .claude/telegram/pending-question.json` (should exist after a question)

### Telegram inline buttons not appearing (only plain text)

- Check settings.json: must have `AskUserQuestion` hook in PreToolUse
- Check `ask-question-bridge.sh` is executable
- If file is empty: the hook did not trigger (PreToolUse may not fire for AskUserQuestion)

### Telegram response not reaching the terminal

- Make sure Claude Code is running via `claude-agent.sh` (requires tmux)
- Check response injector is running: `bash .claude/telegram/manage.sh status`
- Check tmux session: `tmux list-sessions`
- Check injector log: `cat .claude/telegram/injector.log | tail -20`
- If tmux target is empty in pending-question.json: Claude Code is not running inside tmux

### /approve from Telegram not processed

- Daemon must be running (`manage.sh status`)
- Check command file: `cat .claude/telegram/incoming-command.txt`
- If file is empty: daemon did not receive the message (check chat ID)
- If file has "APPROVE" but pipeline did not continue: orchestrator has not polled yet (wait for sampling interval)

### Telegram daemon crash

```bash
cat .claude/telegram/daemon.log | tail -20
bash .claude/telegram/manage.sh restart

# If it keeps crashing:
jq --version   # jq must be installed
```

### Hook blocked my command

The hook is doing its job. Read the BLOCKED message in stderr. Common blocks:
- Pushing to protected branch → use feature branch instead
- Writing to .env → use settings.local.json
- Editing .claude/agents/ → manual edit required (file-protect.sh)
- Bare `npm`/`pip`/`composer` on host → use `docker exec` instead (Docker enforcement)

To see block history:

```bash
grep "BLOCKED" .claude/hooks/hook-log.txt
```

### Pipeline won't resume

```bash
# Check for resume state
cat docs/wave-execution-state.md   # file-level progress
cat docs/session-handoff.md        # session-level state

# Resume
claude
# Then type: /start resume
```

If neither state file exists: run `/clean` first, then `/start <original input>`.

### Context exhausted mid-pipeline

```bash
/start resume
```

The orchestrator reads `docs/wave-execution-state.md` for file-level resume. Files already marked `[x]` are skipped — execution picks up at the first `[ ]` entry. No re-planning needed. If `wave-execution-state.md` is missing, it falls back to `docs/session-handoff.md`.

### Pipeline stuck with no output (silent context limit)

This is prevented by the Context Resilience Protocol (CRP). The orchestrator auto-compacts context after every wave. If it still happens:
- Check whether the wave is too large (> 20 files)
- Split the wave into sub-waves in `docs/wave-plan.md`

### /run from Telegram fails

```bash
# Check if tmux is available
which tmux

# Check if a session already exists
tmux list-sessions

# Kill stale sessions
tmux kill-session -t claude-pipeline

# Clean stale state
rm -f .claude/telegram/channel-mode.env
rm -f .claude/telegram/trigger-task.json
```

### Channel mode not detected

Verify `channel-mode.env` exists and contains valid PID:

```bash
cat .claude/telegram/channel-mode.env
# Should show: CHANNEL_MODE=native, SESSION_PID=<valid-pid>

# Check PID is alive
kill -0 <pid> && echo "alive" || echo "dead"
```

### Pipeline STOP at start — credentials missing

Fill `.env` with token and repo URL. See section 3.

### Hooks not running

```bash
chmod +x .claude/hooks/*.sh
jq --version   # must be installed
```

### Agent Teams not active

- Check settings.json: must have `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"`
- Check model: must be Opus 4.6

### Docker containers not running

```bash
docker compose up -d
docker compose ps     # all must be UP
docker compose logs   # check for errors
```

### Git worktree error

```bash
git --version              # must be 2.35+
git worktree list          # check for stuck worktrees
git worktree prune         # clean up orphaned worktrees
```

### PR creation failed

```bash
# Verify token
curl -H "Authorization: Bearer $GITLAB_TOKEN" https://gitlab.com/api/v4/user

# Check remote and branch
git remote -v
git branch -a
```

### Design violations keep appearing

```bash
/retro focus hooks   # identify the most common pattern
```

Then update `docs/design-direction.md` with more specific forbidden patterns.

### Fix loop with too many retries

Check `docs/fix-ledger.md` — are the strategies actually different between attempts? After 3 attempts the pipeline escalates automatically to rollback + rewrite. If it still fails, the issue is logged as known and the pipeline continues.

### Bare npm/pip/composer blocked by hook

This is Docker enforcement — the agent must use `docker exec`. If the service genuinely needs to run on the host, check `docs/docker-assessment.md`. If the service is listed under Host Services it should already be allowed. If no assessment exists yet, run:

```bash
bash .claude/scripts/docker-assess.sh .
```

### Scripts not executable

```bash
chmod +x .claude/hooks/*.sh .claude/scripts/*.sh .claude/telegram/*.sh
```

### Port conflict on docker compose up

```bash
# Re-run port scanner
bash .claude/scripts/port-scan-all.sh < /tmp/port-request.json

# Update .env with new ports, then restart
docker compose down && docker compose up -d
```

### Telegram notifications not arriving

```bash
# Test manually
bash .claude/hooks/notify.sh "test message"

# Check hook log
cat .claude/hooks/hook-log.txt | tail -5
# If log entry exists but Telegram is silent: internet/firewall issue
```
<!-- END:troubleshooting -->

---

## 13. Usage Scenarios

### Scenario A: Greenfield (Project from scratch)

**When to use**: You have a brief for a brand-new application. No existing code, no repo yet.

**Preparation:**

```bash
# 1. Create an empty project folder
mkdir -p ~/project/apps/my-project
cd ~/project/apps/my-project

# 2. Initialize git
git init
git checkout -b develop

# 3. Copy agent structure
cp -r /path/to/claude-team-agents/.claude .
cp -r /path/to/claude-team-agents/docs .
chmod +x .claude/hooks/*.sh .claude/scripts/*.sh .claude/telegram/*.sh

# 4. Create .env
cat > .env << 'EOF'
GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxx
GITLAB_REPO_URL=https://gitlab.com/username/my-project
DB_ENGINE=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=my_project
DB_USERNAME=root
DB_PASSWORD=secret
EOF

# 5. Create remote repo (manual step) — GitLab or GitHub
git remote add origin https://gitlab.com/username/my-project.git

# 6. Prepare brief (optional — you can also provide text directly)
mkdir -p briefs
# Copy brief.docx into briefs/
```

**Run:**

```bash
claude

# Option 1: From a brief file
/start briefs/brief-001.docx

# Option 2: From inline text
/start Build an e-commerce app with user auth, product catalog, shopping cart, Stripe payment, and admin dashboard. Stack: Laravel + React + MySQL.
```

**What happens:**
1. Orchestrator detects: GREENFIELD (empty folder, no codebase)
2. Convention scout researches latest docs for the detected stack
3. Design director generates `design-direction.md`
4. wave-planner splits features into waves by dependency
5. **[APPROVE GATE]** — you review and approve the wave plan
6. Foundation phase: project-init → env-config → db-design → health check
7. Wave execution: Agent Teams in parallel per wave
8. QA: environment matrix → fix loop
9. Final review: 4 reviewers in parallel
10. PR: develop → main (you merge manually)

**Checklist before `/start` for Greenfield:**
- [ ] Empty project folder
- [ ] `git init` + `git checkout -b develop`
- [ ] `.claude/` copied and scripts executable
- [ ] `.env` with complete credentials (Git token + DB + Telegram)
- [ ] Remote repo created and `git remote add origin` done
- [ ] Brief ready (file or text)
- [ ] Docker running (`docker ps` shows no error)
- [ ] Telegram bot set up (optional but recommended)

---

### Scenario B: New Feature (Add features to existing project)

**When to use**: The project is already running and you want to add new features.

**Preparation:**

```bash
cd ~/project/apps/existing-project

# Make sure you are on develop and up to date
git checkout develop
git pull origin develop

# If .claude/ is not present, copy it
ls .claude/agents/ 2>/dev/null || cp -r /path/to/claude-team-agents/.claude .
chmod +x .claude/hooks/*.sh

# Make sure .env has credentials
cat .env | grep -E "TOKEN|REPO_URL"

# Docker containers must be running
docker compose up -d
docker compose ps   # all must be UP
```

**Run:**

```bash
claude

# From a brief file
/start briefs/brief-export-pdf.docx

# From inline text (single feature)
/start Add PDF export on the reports page. Users can export monthly reports to PDF with company logo and digital signature.

# From inline text (multiple features — will be split into waves)
/start Add 5 new features: (1) PDF export for reports, (2) email notification when a report is ready, (3) real-time analytics dashboard, (4) bulk CSV import, (5) audit log for all admin actions.
```

**What happens:**
1. Orchestrator detects: EXISTING codebase + NEW FEATURE
2. codebase-scout probes the codebase and detects the stack
3. wave-planner: single feature → single wave / multiple features → multi-wave
4. **[APPROVE GATE]**
5. **Foundation is skipped** (project already exists)
6. Wave execution with Agent Teams
7. Auto-merge features → develop
8. QA + final review
9. PR: develop → main

**Checklist before `/start` for New Feature:**
- [ ] `git checkout develop && git pull` (up to date)
- [ ] `.env` with credentials
- [ ] Docker containers UP (`docker compose up -d`)
- [ ] Brief or inline text ready
- [ ] No uncommitted changes (`git status` is clean)

---

### Scenario C: Bug Fix

**When to use**: There is a bug to fix, from a user report, a QA report, or your own discovery.

**Preparation:**

```bash
cd ~/project/apps/existing-project
git checkout develop
git pull origin develop
docker compose up -d
```

**Run:**

```bash
claude

# From a bug description
/start Bug: checkout button errors on mobile view. Clicking "Pay Now" shows a blank screen. Only happens at viewport < 768px.

# From a simulation report
/start docs/user-simulation-report.md has issues that need to be fixed

# From a QA checklist report
/start docs/qa-checklist-report.md has failed test cases that need fixing
```

**What happens:**
1. Orchestrator detects: BUG FIX (keywords: "bug", "error", "fix", "failed")
2. **Skips** convention scout and design direction (not needed for bug fixes)
3. wave-planner: single wave, lightweight (small scope)
4. codebase-scout focuses on root cause analysis
5. **[APPROVE GATE]** — you approve the diagnosis and fix plan
6. Single-session fix (Agent Teams not needed for small bugs)
7. QA: tests only the affected area
8. Auto-merge → develop
9. PR: develop → main

**Note**: If the bug turns out to be large (spanning many files), wave-planner automatically upgrades to multi-wave.

**Checklist before `/start` for Bug Fix:**
- [ ] `git checkout develop && git pull`
- [ ] Docker containers UP
- [ ] Bug description as clear as possible (repro steps, environment, screenshots if available)

---

### Scenario D: Small Edit

**When to use**: Simple change — replace text, update a color, fix a typo, change config.

**Preparation**: Same as Bug Fix.

**Run:**

```bash
claude

/start Change the primary button color from blue to green (#2D6A4F) throughout the application

/start Update the copyright year from 2025 to 2026 in the footer

/start Add a "phone" field to the user registration form (validate Indonesian format: +62xxx)
```

**What happens:**
1. Orchestrator detects: SMALL EDIT (< 3 files changed)
2. **Skips** convention scout, design direction, and wave planning
3. Goes directly: codebase-scout → fix → review → PR
4. Minimal pipeline, finishes quickly

---

### Scenario E: Phase 2+ (Continuing after greenfield)

**When to use**: Greenfield phase 1 is complete and merged. You now want to add a new batch of features (phase 2).

**Preparation:**

```bash
cd ~/project/apps/my-project

# Make sure phase 1 is merged to develop
git checkout develop
git pull origin develop

docker compose up -d
docker compose ps

# Phase 2 brief ready
ls briefs/brief-phase2.docx
```

**Run:**

```bash
claude
/start briefs/brief-phase2.docx
```

**What happens:**
1. Orchestrator detects: EXISTING codebase (from phase 1) + many new features
2. **Foundation is skipped** (already exists from phase 1)
3. convention-scout checks for stack updates since phase 1
4. design-director **inherits** from phase 1 (reads existing `docs/design-direction.md`)
5. wave-planner reads `pipeline-intelligence.md` from phase 1 → **learns from previous patterns**
6. Multi-wave execution
7. PR: develop → main (you merge)

---

### Scenario F: Resume (Continue an interrupted pipeline)

**When to use**: The pipeline stopped mid-way (context exhausted, session timeout, terminal closed).

**Run:**

```bash
claude
/start resume
```

**What happens:**
1. Orchestrator checks `docs/wave-execution-state.md` (file-level state) — this is the primary source
2. If found: displays which wave, how many files are `[x]` done and which is next `[ ]`
3. **Executes immediately** from the last unfinished file — **no re-planning**
4. Files already marked `[x]` are skipped (already on disk)
5. If `wave-execution-state.md` is missing → falls back to `docs/session-handoff.md`

**Example resume display:**

```
RESUME DETECTED
Wave: 2
Files: 35 / 75 completed
Status: stopped-context-limit
Next file: src/services/payment.ts
```

**No special preparation needed** — all state is already saved in `docs/`.

**Why resume is fast**: The planning phase uses 30-50% of context. Resume skips all planning and goes straight to execution, giving 100% of available context to coding.

---

### Scenario G: QA Only

**When to use**: Code is already written (manually or from a previous pipeline) and you only want to test it.

**Run:**

```bash
claude

# Full QA: generate checklist → run → report
/qa-checklist full

# Generate checklist only (do not run yet)
/qa-checklist generate

# Run an existing checklist
/qa-checklist run

# Run from a custom file (supports .md, .xlsx, .docx, .csv)
/qa-checklist run --file docs/my-custom-checklist.md

# Run from an Excel file with test cases
/qa-checklist run --file briefs/test-cases.xlsx

# Run tests with a specific data file (e.g., upload/process during test)
/qa-checklist run --file briefs/test-cases.xlsx --data "C:\Users\you\Downloads\dataset.xlsx"
```

**Supported test file formats:**

| Format | What happens |
|--------|-------------|
| `.md` | Direct — parsed as-is by interpreter |
| `.xlsx` / `.xls` | All sheets extracted to markdown, then parsed |
| `.docx` | Converted to markdown via pandoc, then parsed |
| `.csv` | Converted to markdown table, then parsed |

**The `--data` flag** provides an input file for test cases that need file upload or data processing. Windows paths are auto-resolved to WSL paths (`C:\Users\...` → `/mnt/c/Users/...`).

---

### Scenario H: Review Only

**When to use**: Code is already written and you want a review + fix pass without running the full pipeline.

**Run:**

```bash
claude

# Scope-aware review (only changed files)
/review-and-fix

# Full review (entire codebase)
/review-and-fix --full
```

---

### Scenario I: Retrospective

**When to use**: After several pipelines, you want to see trends and auto-improve.

**Run:**

```bash
claude

# Full retrospective
/retro

# Focus on wave performance only
/retro focus waves

# Focus on hook violations only
/retro focus hooks
```

---

## 14. Docker-First Architecture

The pipeline uses a **Docker-First** approach — all services run in containers by default.

### Phase 0A: Automatic Assessment

At the start of every pipeline, Phase 0A runs two scripts automatically:

1. **Docker Assessment** (`docker-assess.sh`): scans the project, detects the stack, and classifies each service:
   - **Dockerizable**: PHP, Node, Python, MySQL, PostgreSQL, Redis → runs in container
   - **Host-only**: Office Add-in, Electron, React Native, Flutter → host fallback

2. **Dynamic Port Scan** (`port-scan-all.sh`): scans port availability and assigns ports without conflicts:
   ```
   Port 8000 in use → assign 8001
   Port 3000 in use → assign 3001
   All assignments written to .env; docker-compose.yml reads from .env
   ```

3. **.env as Single Source of Truth (SSOT)**: all ports and config are written to `.env` — no other file hardcodes them.

4. **docker-compose.yml is generated AFTER `.env`**: all ports use `${VAR}` syntax.

### Enforcement Rules

- `security-gate.sh` **blocks** bare `npm`, `pip`, and `composer` commands on the host when a Dockerized service is detected
- If the service is in Docker → commands MUST go through `docker exec -it [container] [command]`
- If the service is in Host Services (per assessment result) → host commands are allowed

### Hybrid Mode

When a service cannot run in Docker, the pipeline uses hybrid mode:
- Docker for what can be containerized (backend, DB)
- Host for what cannot (Office Add-in, Electron)
- User is notified via Telegram: "Hybrid Docker Mode active"

### All Commands Must Go Through Docker

```bash
# CORRECT
docker exec -it app php artisan migrate
docker exec -it app composer require vendor/package
docker exec -it node npm install express
docker exec -it python pip install fastapi

# WRONG — never run these directly
php artisan migrate
composer require vendor/package
npm install express
pip install fastapi
```

**Port references**: always read from `.env`, never hardcode:

```bash
# CORRECT
source .env
curl http://localhost:${APP_PORT}/api/health

# WRONG
curl http://localhost:8000/api/health
```

---

## 15. Context Resilience Protocol

Large pipelines (50+ files) can exceed the context window. The **Context Resilience Protocol (CRP)** handles this automatically.

### Auto-Compact Between Waves

After every wave completes, the orchestrator compacts context:
- **Retained**: `wave-execution-state.md`, `wave-plan.md`, `conventions.md`, `.env`
- **Discarded**: conversation history, planning details, file contents already written to disk
- This frees approximately 25-40% of context for the next wave

### File-Level State Tracking

`docs/wave-execution-state.md` tracks progress per file:

```markdown
### Wave 2: Payment System
- [x] src/models/payment.py        ← done
- [x] src/services/stripe.py       ← done
- [ ] src/controllers/checkout.py   ← NEXT (resume from here)
- [ ] tests/test_payment.py
```

### Graceful Exit Under Context Pressure

When context approaches the limit:
1. Finish the file currently being written
2. Update `wave-execution-state.md`: `status = stopped-context-limit`
3. Notify via Telegram: "Context limit reached — run `/start resume`"
4. Stop cleanly — no data is lost

### Context Budget Estimates

| Phase | Approximate Context Usage |
|-------|--------------------------|
| Planning | ~30-50% (heaviest phase) |
| 10-20 files/wave | ~15-25% |
| 20-40 files/wave | ~25-40% |
| 40+ files/wave | automatically split into sub-waves |

### Telegram Notifications for Context Events

| Script | Event |
|--------|-------|
| `notify-wave-complete.sh` | Wave finished — progress update |
| `notify-context-pressure.sh` | Context approaching limit — save and notify |
| `notify-compact.sh` | Context compacted — continuing to next wave |

---

## 16. Environment-Specific Setup

### Multi-Database Testing

If your project needs to test against both MySQL and PostgreSQL, add to `.env`:

```env
DB_ENGINE_PRIMARY=mysql
DB_ENGINE_SECONDARY=postgresql

# MySQL
MYSQL_HOST=mysql
MYSQL_PORT=3306
MYSQL_DATABASE=myapp
MYSQL_USER=root
MYSQL_PASSWORD=secret

# PostgreSQL
PGSQL_HOST=pgsql
PGSQL_PORT=5432
PGSQL_DATABASE=myapp
PGSQL_USER=postgres
PGSQL_PASSWORD=secret
```

Create `docs/test-environment-config.md`:

```markdown
## Test Environments

### Docker Local — MySQL
- Host: mysql (docker service name)
- Port: 3306
- Connection: docker exec mysql mysql -u root -psecret myapp

### Docker Local — PostgreSQL
- Host: pgsql (docker service name)
- Port: 5432
- Connection: docker exec pgsql psql -U postgres myapp

### Staging
- URL: https://staging.myapp.com
- Auth: Bearer token from .env STAGING_API_TOKEN

### Mobile Viewport
- Same as Docker Local, browser resized to 375x812 (iPhone)

### MS Add-ins
- Sideload URL: https://localhost:3000/manifest.xml
- Office version: Microsoft 365
```

### Staging Server

Add to `.env`:

```env
STAGING_URL=https://staging.myapp.com
STAGING_API_TOKEN=Bearer eyJxxxxxxxxxxxx
STAGING_SSH_HOST=staging.myapp.com
STAGING_SSH_USER=deploy
```

### Microsoft Add-ins

Add to `.env`:

```env
ADDIN_MANIFEST_URL=https://localhost:3000/manifest.xml
OFFICE_VERSION=365
ADDIN_SIDELOAD_PATH=/path/to/manifest.xml
```

---

## 17. Quick Reference Card

```
+----------------------------------------------------------+
|                       QUICK START                        |
+----------------------------------------------------------+
|                                                          |
|  GREENFIELD:                                             |
|    mkdir project && cd project && git init               |
|    git checkout -b develop                               |
|    cp -r /path/to/claude-team-agents/.claude .           |
|    # Create .env + remote repo                           |
|    claude  ->  /start briefs/brief.docx                  |
|                                                          |
|  NEW FEATURE:                                            |
|    cd project && git checkout develop && git pull        |
|    docker compose up -d                                  |
|    claude  ->  /start "add feature X"                    |
|                                                          |
|  BUG FIX:                                                |
|    cd project && git checkout develop && git pull        |
|    docker compose up -d                                  |
|    claude  ->  /start "bug: description"                 |
|                                                          |
|  RESUME:                                                 |
|    cd project                                            |
|    claude  ->  /start resume                             |
|                                                          |
|  QA ONLY:                                                |
|    claude  ->  /qa-checklist full                        |
|    claude  ->  /qa-checklist run --file tests.xlsx       |
|    claude  ->  /qa-checklist run --file t.xlsx --data d.xlsx|
|                                                          |
|  REVIEW ONLY:                                            |
|    claude  ->  /review-and-fix                           |
|                                                          |
|  RETRO:                                                  |
|    claude  ->  /retro                                    |
|                                                          |
+----------------------------------------------------------+
|  PREREQUISITES CHECKLIST:                                |
|  [ ] Claude Code v2.1.80+                                |
|  [ ] Docker + Docker Compose v2+                         |
|  [ ] Git 2.35+ (worktree support)                        |
|  [ ] jq (for hooks + scripts)                            |
|  [ ] tmux (for Telegram bidirectional mode)              |
|  [ ] Bun (for native channel plugin)                     |
|  [ ] .env: GITLAB_TOKEN or GITHUB_TOKEN                  |
|  [ ] .env: TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID         |
|  [ ] Remote repo already created                         |
|  [ ] chmod +x .claude/hooks/*.sh                         |
|  [ ] chmod +x .claude/scripts/*.sh                       |
|  [ ] chmod +x .claude/telegram/*.sh                      |
+----------------------------------------------------------+
|  TELEGRAM COMMANDS:                                      |
|  /status  -- view pipeline progress                      |
|  /approve -- approve pipeline from Telegram              |
|  /reject  -- reject & stop pipeline                      |
|  /run     -- start new pipeline remotely                 |
|  /log     -- view last 10 hook events                    |
|  /retro   -- trigger retrospective                       |
+----------------------------------------------------------+
|  TELEGRAM BIDIRECTIONAL MODE:                            |
|  bash .claude/telegram/claude-agent.sh   <- RECOMMENDED  |
|    (auto tmux + daemon + Claude Code)                    |
|                                                          |
|  Manual:                                                 |
|  bash .claude/telegram/manage.sh start                   |
|  bash .claude/telegram/manage.sh status                  |
|  bash .claude/telegram/manage.sh stop                    |
+----------------------------------------------------------+
```

---

## Quick Start Checklist

```
[ ] 1. Copy .claude/ directory to your project
[ ] 2. Clean runtime state files (PIDs, logs)
[ ] 3. chmod +x all .sh scripts
[ ] 4. Add credentials to settings.local.json (or .env)
[ ] 5. Run setup-telegram.sh to register bot commands
[ ] 6. Add settings.local.json and .env to .gitignore
[ ] 7. Start: bash .claude/telegram/claude-agent.sh
[ ] 8. Type /start <your task> in terminal
[ ] 9. Or send /run <task> from Telegram
```
