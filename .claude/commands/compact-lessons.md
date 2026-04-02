Kompaksi lessons — arsipkan entry lama yang sudah solved, merge duplikat.

---

## LANGKAH 1 — Analisis

```bash
TOTAL=$(grep -c "^### " .claude/memory/lessons.md 2>/dev/null || echo 0)
SOLVED=$(grep -c "Solusi   : ✅" .claude/memory/lessons.md 2>/dev/null || echo 0)
UNSOLVED=$(grep -c "Solusi   : ⏳" .claude/memory/lessons.md 2>/dev/null || echo 0)
echo "Total: $TOTAL | Solved: $SOLVED | Unsolved: $UNSOLVED"
```

---

## LANGKAH 2 — Identifikasi Kandidat Arsip

Baca `.claude/memory/lessons.md` dan identifikasi entry yang memenuhi kriteria arsip:

**Kriteria arsip (harus memenuhi SEMUA):**
- Status `✅` (sudah solved)
- Tanggal > 30 hari dari sekarang
- Atau memiliki "Update : ✅ Dikonfirmasi"

**Kriteria TIDAK boleh diarsip:**
- Status `⏳` (belum solved) — tetap di file utama
- Entry < 30 hari — masih relevan untuk agent aktif
- Entry yang di-referensi oleh entry `⏳` lain

**Duplikat detection:**
- Entry dengan prefix STACK + konteks yang sama
- Merge: pertahankan entry terbaru, gabungkan semua `Dicoba` lines

---

## LANGKAH 3 — Eksekusi

### 3A — Buat/update archive file

```bash
ls .claude/memory/lessons-archive.md 2>/dev/null && echo "ARCHIVE EXISTS" || echo "ARCHIVE NEW"
```

Jika ARCHIVE NEW → buat header:
```markdown
# Agent Lessons — Archive
> Entry yang sudah solved dan berumur > 30 hari.
> Dipindahkan oleh /compact-lessons.
> Untuk referensi saja — agent tidak membaca file ini secara rutin.

---
```

Pindahkan entry arsip ke `.claude/memory/lessons-archive.md`:
- Tambahkan `Diarsipkan : [YYYY-MM-DD]` di setiap entry yang dipindahkan

### 3B — Merge duplikat

Untuk entry duplikat yang tersisa di file utama:
- Pertahankan entry dengan tanggal terbaru
- Gabungkan semua baris `Dicoba` dari kedua entry
- Tambahkan `Merged : [YYYY-MM-DD] — digabung dari [N] entry`

### 3C — Hapus flag compaction

```bash
sed -i '/<!-- COMPACTION_NEEDED -->/d' .claude/memory/lessons.md
```

---

## LANGKAH 4 — Report

```bash
TOTAL_AFTER=$(grep -c "^### " .claude/memory/lessons.md 2>/dev/null || echo 0)
ARCHIVED=$(grep -c "^### " .claude/memory/lessons-archive.md 2>/dev/null || echo 0)
echo "AFTER: $TOTAL_AFTER active | $ARCHIVED archived"
```

Tampilkan:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ LESSONS COMPACTION SELESAI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Before  : [TOTAL] entries
After   : [TOTAL_AFTER] active + [ARCHIVED] archived
Merged  : [N] duplikat digabung
Removed : [N] entry dipindahkan ke archive

File utama  : .claude/memory/lessons.md
File arsip  : .claude/memory/lessons-archive.md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
