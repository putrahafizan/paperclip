---
description: "QA Checklist pipeline — generate, run, atau full cycle"
---

# /qa-checklist — QA Pipeline

## SUB-MODES
- `/qa-checklist generate` — auto-generate checklist dari codebase
- `/qa-checklist run [--env docker-mysql|docker-pgsql|staging|mobile|addin]` — run existing checklist
- `/qa-checklist run --file path/to/checklist.md` — run specific checklist
- `/qa-checklist full [--env all]` — generate + run + report
- `/qa-checklist config` — setup/update qa-project-config.md
- `/qa-checklist run --file path/to/tests.xlsx --data path/to/dataset.xlsx` — run with test data file
- `/qa-checklist interactive` — guided mode

## TEST DATA PARAMETER
- `--data path/to/file` — file yang digunakan sebagai test input (upload, processing)
- File ini akan di-resolve ke WSL path jika Windows path diberikan (C:\Users\... → /mnt/c/Users/...)
- Path disimpan ke variabel `{{test_data_file}}` yang bisa dipakai di setiap TC
- Jika TC memiliki file upload step → gunakan file ini
- Jika TC memiliki data processing step → gunakan file ini sebagai dataset

Contoh:
```
/qa-checklist run --file briefs/tests.xlsx --data /mnt/c/Users/user/Downloads/dataset.xlsx
```

## ENVIRONMENT PARAMETER (NEW)
- `--env docker-mysql` (default): test di Docker MySQL
- `--env docker-pgsql`: test di Docker PostgreSQL
- `--env staging`: test di staging server
- `--env mobile`: test dengan mobile viewport
- `--env addin`: test Office Add-in
- `--env all`: run environment-matrix-runner untuk test di semua environments

## FIX-LEDGER INTEGRATION (NEW)
- Sebelum run: baca `docs/fix-ledger.md` untuk known issues
- Mark known-issue TCs sebagai ⚠️ (bukan ❌)
- Setelah run: update fix-ledger dengan hasil baru
- Jika ada failure baru → trigger fix-strategist

## PIPELINE
1. **qa-checklist-generator**: analyze codebase → generate checklist + config
2. **qa-checklist-interpreter**: normalize format, resolve ambiguities
3. PREVIEW + APPROVE gate
4. **qa-checklist-runner**: execute TCs per environment
5. Fix loop (fix-strategist + be/fe-developer, max 3 cycles)
6. Final report → `docs/qa-checklist-report.md`
