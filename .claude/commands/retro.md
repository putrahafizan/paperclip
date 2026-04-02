---
description: "Jalankan retrospective analysis — analisis trends dan auto-apply improvements"
---

Jalankan retrospective analysis.

Panggil retro-agent untuk menganalisis performance data dari pipeline-pipeline terakhir.

Input opsional: $ARGUMENTS
- Tanpa argumen: analisis semua data yang tersedia
- "last 3": analisis hanya 3 pipeline terakhir
- "focus hooks": fokus pada hook analytics saja
- "focus waves": fokus pada wave performance saja

---

## LANGKAH

1. Verifikasi data sources ada:
   ```bash
   ls docs/pipeline-intelligence.md 2>/dev/null && echo "PI_EXISTS" || echo "PI_MISSING"
   ls docs/hook-analytics.md 2>/dev/null && echo "HA_EXISTS" || echo "HA_MISSING"
   ls docs/fix-ledger.md 2>/dev/null && echo "FL_EXISTS" || echo "FL_MISSING"
   ls .claude/memory/lessons.md 2>/dev/null && echo "LS_EXISTS" || echo "LS_MISSING"
   ```

2. Jika semua MISSING → report: "Belum ada data. Jalankan minimal 1 pipeline dulu."

3. Jika ada data → panggil retro-agent dengan fokus yang diminta.

4. Setelah retro-agent selesai, tampilkan summary:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   📊 RETRO REPORT
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Pipelines analyzed: [N]
   Trend: [IMPROVING ✅ / STABLE ➡️ / DEGRADING ⚠️]
   Auto-applied updates: [N] items
   Full report: docs/retro-report.md
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```
