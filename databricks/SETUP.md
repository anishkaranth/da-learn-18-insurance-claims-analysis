# Databricks setup and run record

The pipeline runs on a Databricks **serverless SQL warehouse** (Unity Catalog) and a Lakeview (AI/BI) dashboard is
published over the resulting tables. The shared warehouse is left to auto-stop.

| Object | Workspace location |
|---|---|
| Raw CSVs (full) | UC volume `/Volumes/workspace/da_learn_18/raw/` (`insurance.csv`, `freMTPL2freq.csv`, `freMTPL2sev.csv`) |
| Tables (stg_*, cln_*, dim_*, fact_*, a_*, dq_*) | `workspace.da_learn_18` |
| Notebook | `/Workspace/Shared/da-learn-18-insurance-claims-analysis/insurance_pipeline_notebook` |
| Dashboard (published) | **da-learn-18 Insurance claims analysis** (2 pages, 8 visuals) |

## DuckDB vs Databricks
Executed 2026-10-02, 21:25-21:35 IST on the Serverless Starter Warehouse (45 statements, ~558 s of statement time).
All **15 stg/cln/dim/fact tables have identical row counts** on both engines (stg_motor_policy / cln / fact 678,013;
stg_motor_claim 26,639 -> cln/fact 26,444; medical 1,338 -> 1,337; dims 4/4/6/22/235/8). `dq_assertions` 12/12 PASS on both.
Only percentile-based values differ, because Spark's `percentile_approx` is approximate: medical top-1 % flags 13 (Databricks) vs 14 (DuckDB),
large-loss flags 266 vs 265, so `large_loss_share_pct` is 38.04 vs 38.01. Details: `run_outputs/duckdb_vs_databricks.json`.

## Files here
| File | What it is |
|---|---|
| `insurance_pipeline_notebook.sql` | Databricks SQL notebook source (exported from the workspace after import; generated from `sql/`) |
| `insurance_claims_dashboard.lvdash.json` | Lakeview dashboard definition exported from the workspace (2 pages: medical cost drivers, motor frequency/severity) |
| `run_outputs/` | Tables queried back from Databricks, `duckdb_vs_databricks.json`, `databricks_run.json` (statement log) |

## Re-run it yourself
1. `CREATE SCHEMA IF NOT EXISTS workspace.da_learn_18; CREATE VOLUME IF NOT EXISTS workspace.da_learn_18.raw;`
2. `python scripts/download_full_data.py`, then upload the three CSVs from `data/raw_full/` to the volume
   (Catalog Explorer -> volume -> *Upload*, or `databricks fs cp`).
3. Workspace -> *Import* -> `insurance_pipeline_notebook.sql`; attach a SQL warehouse -> *Run all*. `dq_assertions` should show 12 x PASS.
4. Dashboards -> *Import dashboard from file* -> `insurance_claims_dashboard.lvdash.json` -> pick a warehouse -> *Publish*.

## Dialect notes (DuckDB vs Databricks)
| Topic | DuckDB run | Databricks |
|---|---|---|
| CSV load | `read_csv(path, header = true, all_varchar = true)` | `read_files(..., inferColumnTypes => false)` minus `_rescued_data` |
| `percentile_approx` | exact (`quantile_cont` shim in `00_duckdb_compat.sql`) | approximate - medians/percentile-based flags can differ slightly |
| `corr`, `LEAST`, window functions, `TRY_CAST` | same | same |
