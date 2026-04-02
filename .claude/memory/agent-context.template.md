# Agent Context Package (ACP)
> Di-generate oleh orchestrator setiap pipeline start.
> SEMUA execution agent hanya perlu baca file ini sebagai bootstrap.
> Jangan baca ulang: lessons.md penuh, design-decisions.md penuh,
> project-context.md penuh — semua sudah di-summarize di sini.

generated_at  : —
pipeline_type : —
branch        : —

## Stack & Environment
stack         : —
framework_fe  : —
docker        : —
test_suite    : —

## Scope
scope_be      : []
scope_fe      : []
scope_db      : none

## Allowed Files (File Scope Contract)
<!-- Diisi oleh code-architect setelah blueprint selesai -->
<!-- Enforced oleh .claude/hooks/scope-check.sh via PreToolUse hook -->
<!-- Agent DILARANG menyentuh file di luar list ini -->
modify  : []
create  : []
delete  : []
forbidden_note : Semua file lain di project ini adalah FORBIDDEN.

## Convention Flags
<!-- Keputusan konvensi yang sudah locked — jangan re-assess -->
<!-- Contoh: "CommonJS kept as-is (risk >80%, lihat tech-debt.md)" -->

## Relevant Lessons
<!-- Hanya lessons yang relevan dengan stack + scope pipeline ini -->
<!-- Di-filter dari .claude/memory/lessons.md oleh orchestrator -->
<!-- Format: copy entry dari lessons.md yang relevan saja -->

## Design Summary
<!-- Ringkasan dari design-decisions.md — maksimal 5 baris -->
<!-- Hanya keputusan yang aktif dan relevan untuk pipeline ini -->
