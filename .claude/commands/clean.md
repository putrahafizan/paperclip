Jalankan prosedur clean session — pastikan semua state tersimpan sebelum context di-clear.

---

## LANGKAH 1 — Verifikasi State Tersimpan

```bash
echo "=== Pipeline State ===" && cat docs/pipeline-state.md 2>/dev/null || echo "❌ TIDAK ADA"
echo "" && echo "=== Session Handoff ===" && cat docs/session-handoff.md 2>/dev/null || echo "❌ TIDAK ADA"
```

---

## LANGKAH 2 — Update session-handoff.md (Pastikan Terkini)

Tulis ulang `docs/session-handoff.md` dengan state TERKINI:

```markdown
# Session Handoff
> Dibuat oleh /clean — [YYYY-MM-DD HH:MM]
> Baca file ini setelah /clear untuk resume pipeline.

## Identitas Pipeline
Branch   : [dari pipeline-state.md]
Tipe     : [dari pipeline-state.md]
Brief    : [dari pipeline-state.md]
Dibuat   : [created_at dari pipeline-state.md]

## Status Stage Terakhir
[salin tabel Stage Progress dari pipeline-state.md]

## Stage Berikutnya
→ [stage pertama yang masih ⏳ pending]

## Keputusan yang Sudah Disetujui Programmer
[pertahankan semua keputusan dari session-handoff.md yang sudah ada]

## Cara Resume
Setelah /clear, ketik: /start resume
```

---

## LANGKAH 3 — Tampilkan Konfirmasi

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ PROGRESS TERSIMPAN — SIAP CLEAN CONTEXT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Semua progress sudah aman di file:

  📄 docs/pipeline-state.md   — status tiap stage
  📄 docs/session-handoff.md  — ringkasan untuk resume

Branch aktif : [nama branch]
Stage selesai: [daftar stage ✅]
Selanjutnya  : [stage berikutnya yang ⏳ pending]

Langkah selanjutnya:

  1. Ketik /clear  → membersihkan context window
  2. Ketik /start resume  → melanjutkan pipeline dari
     [stage berikutnya] dengan context yang segar

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Catatan: `.claude/memory/lessons.md` tetap tersimpan (tidak di-clear).
Orchestrator akan inject lessons ke ACP saat `/start resume`.

Setelah menampilkan ini — STOP. Tunggu user ketik `/clear`.
