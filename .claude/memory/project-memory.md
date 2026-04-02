# Project Memory — Active Project State
# Updated by orchestrator after each pipeline completion.
# Tracks current sprint goals, environment status, and pending work.

---

## Current State
<!-- Updated after each pipeline run:
Last pipeline: [date] — [type: greenfield/feature/bugfix] — [result: success/partial/failed]
Branch: [current active branch]
Wave progress: [N/M waves completed]
Open issues: [count]
-->

---

## Environment Status
<!-- Updated by docker-manager and env-configurator:
Docker: [running/stopped/not-configured]
Database: [engine] [version] [status]
Ports: [list of allocated ports]
Last health check: [date]
-->

---

## Pending Decisions
<!-- Items that need programmer input before next pipeline:
### [decision-name]
Question: [what needs to be decided]
Options: [A, B, C]
Raised by: [agent name]
Date: [when raised]
-->

---

## Pipeline History (last 5)
<!-- Append-only log of recent pipeline runs:
| Date | Type | Features | Waves | Duration | Result |
|------|------|----------|-------|----------|--------|
-->
