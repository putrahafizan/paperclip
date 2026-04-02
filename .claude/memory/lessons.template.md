# Agent Lessons — [PROJECT NAME]
> File ini di-generate otomatis saat first run.
> Format key: [STACK:CONTEXT] — grep efisien per agent.
>
> Cara grep yang benar (gunakan ini, bukan cat full file):
>   grep -A 6 "^### BE:Node\|^### BE:Laravel" .claude/memory/lessons.md
>   grep -A 6 "^### FE:React\|^### FE:Vanilla" .claude/memory/lessons.md
>   grep -A 6 "^### QA:\|^### INFRA:" .claude/memory/lessons.md

---

<!-- FORMAT ENTRY — copy template ini saat tambah lesson baru:

### [STACK:CONTEXT] — [deskripsi error singkat]
Konteks  : [file/fungsi/kondisi spesifik]
Dicoba   : ❌ [fix yang gagal] — [kenapa gagal]
Solusi   : ✅ [fix yang berhasil] ATAU ⏳ Belum ditemukan — eskalasi
Tanggal  : [YYYY-MM-DD]

PREFIX STACK yang valid:
  BE:Node / BE:Laravel / BE:Python
  FE:React / FE:Next / FE:Vanilla
  DB:Postgres / DB:MySQL / DB:SQLite
  QA:Smoke / QA:E2E
  INFRA:Docker / INFRA:Git
-->

<!-- SEARCH-BEFORE-WRITE PROTOCOL — WAJIB sebelum tulis entry baru:
1. grep -i "[keyword dari error]" .claude/memory/lessons.md
2. Jika match + status ✅ → SKIP, jangan tulis duplikat
3. Jika match + status ⏳ → UPDATE entry yang ada
4. Jika tidak ada match → Tulis entry baru

CEK UKURAN: grep -c "^### " .claude/memory/lessons.md
Jika >= 50 → tambahkan <!-- COMPACTION_NEEDED --> di akhir file
Orchestrator akan auto-run /compact-lessons saat deteksi flag ini.

ARCHIVE: Entry lama yang sudah solved > 30 hari → .claude/memory/lessons-archive.md
-->
