# Session Handoff
> Di-generate otomatis saat first run.
> Diupdate oleh orchestrator setelah setiap agent selesai.
> Gunakan /start resume untuk lanjut dari session sebelumnya.

updated_at  : —
written_by  : —

## Pipeline State
type        : —
branch      : —
approved    : PENDING

## Progress
done        : []
current     : —
next        : —
blocked     : none

## Locked Decisions
<!-- Keputusan yang sudah dibuat dan TIDAK perlu ditanya lagi -->
<!-- Format: key : value — contoh: framework : Vanilla HTML -->

## Active Task
—

## Approved Manifest
<!-- Diisi saat programmer APPROVE. Ini adalah kontrak eksekusi. -->
<!-- Security-check dan scope-check.sh enforce ini saat runtime. -->
files_modify  : []
files_create  : []
files_delete  : []
db_changes    : none
dependencies  : none
env_changes   : none

## Files Touched
modified : []
created  : []

## Open Flags
none

## Cara Resume
Ketik: /start resume
Orchestrator akan baca file ini dan lanjut dari `next` stage.

## Context Resilience State

### Last Compact
- Timestamp: [when]
- Reason: [post-planning | wave-transition | context-pressure]
- Wave at compact: [N]

### Resume Point
- Wave: [N]
- File: [path/to/next/file]
- Files completed: [M] / [total]
- Instruction: "Skip to Wave [N], start from [file]. All files marked [x] in wave-execution-state.md are on disk."

### Context Pressure History
- [timestamp] Compact #1: after planning (freed ~40% context)
- [timestamp] Compact #2: after Wave 1 (freed ~25% context)
