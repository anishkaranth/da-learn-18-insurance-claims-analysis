#!/usr/bin/env python3
"""Run the SQL pipeline (sql/00..05) on DuckDB and export clean tables, KPI tables, metrics and charts.

Usage
  python run_pipeline.py --source sample     # repo-contained subset (data/raw)      -> data/clean/, powerbi/data, results/sample/
  python run_pipeline.py --source full       # full dataset          (data/raw_full) -> data/clean_full/{cleaned,star}, results/
                                             #   (download first: python scripts/download_full_data.py)
"""
import argparse, csv, json, pathlib, platform, time
import duckdb
from project_config import CONFIG

ROOT = pathlib.Path(__file__).resolve().parent
SQL_FILES = ["00_duckdb_compat.sql", "01_staging.sql", "02_cleaning.sql", "03_model.sql",
             "04_analysis.sql", "05_quality_checks.sql"]


def split_sql(text):
    """Split on ';' at end of line after removing -- comments (scripts contain no ';' inside strings)."""
    stmts, buf = [], []
    for line in text.splitlines():
        i = line.find("--")
        if i >= 0 and line[:i].count("'") % 2 == 0:
            line = line[:i]
        if not line.strip():
            continue
        buf.append(line)
        if line.rstrip().endswith(";"):
            s = "\n".join(buf).strip().rstrip(";").strip()
            if s:
                stmts.append(s)
            buf = []
    return stmts


def rows(con, q):
    cur = con.execute(q)
    cols = [d[0] for d in cur.description]
    return [{c: jsonable(v) for c, v in zip(cols, r)} for r in cur.fetchall()]


def jsonable(v):
    if hasattr(v, "isoformat"):
        return v.isoformat()
    if v.__class__.__name__ == "Decimal":
        return float(v)
    return v


def export(con, table, path, limit=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    cur = con.execute(f"SELECT * FROM {table} ORDER BY ALL" + (f" LIMIT {limit}" if limit else ""))
    cols = [d[0] for d in cur.description]
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(cols)
        for r in cur.fetchall():
            w.writerow(["" if v is None else jsonable(v) for v in r])


def run_sql(raw):
    con = duckdb.connect()
    timings = {}
    for f in SQL_FILES:
        t0 = time.time()
        text = (ROOT / "sql" / f).read_text().replace("{{RAW_DIR}}", raw.as_posix())
        for s in split_sql(text):
            con.execute(s)
        timings[f] = round(time.time() - t0, 3)
        print(f"ran {f:24s} {timings[f]:6.2f}s")
    return con, timings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", choices=["sample", "full"], default="sample")
    ap.add_argument("--no-charts", action="store_true")
    a = ap.parse_args()
    raw = ROOT / ("data/raw" if a.source == "sample" else "data/raw_full")
    clean_dir = ROOT / ("data/clean" if a.source == "sample" else "data/clean_full")
    res = ROOT / ("results/sample" if a.source == "sample" else "results")
    for f in CONFIG["raw_files"]:
        if not (raw / f).exists():
            raise SystemExit(f"missing {raw}/{f}; run scripts/download_full_data.py first")

    con, timings = run_sql(raw)
    if a.source == "full":
        for t in CONFIG["star"]:
            export(con, t, clean_dir / "star" / f"{t}.csv")
        for t in CONFIG["clean"]:
            export(con, t, clean_dir / "cleaned" / f"{t.replace('cln_', '')}.csv")
    else:
        # sample run: star schema -> powerbi/data (Power BI kit), cleaned tables -> data/clean
        for t in CONFIG["star"]:
            export(con, t, ROOT / "powerbi" / "data" / f"{t}.csv")
        for t in CONFIG["clean"]:
            export(con, t, clean_dir / "cleaned" / f"{t.replace('cln_', '')}.csv")
    tables = [r["table_name"] for r in rows(con, "SELECT table_name FROM information_schema.tables "
              "WHERE table_name LIKE 'a\\_%' ESCAPE '\\' OR table_name LIKE 'dq\\_%' ESCAPE '\\' ORDER BY 1")]
    if a.source == "full":
        for t in tables:
            export(con, t, res / "tables" / f"{t}.csv")

    kpi = rows(con, "SELECT * FROM a_kpi_headline")[0]
    dq = {
        "row_counts": rows(con, "SELECT * FROM dq_row_counts"),
        "null_rates": rows(con, "SELECT * FROM dq_null_rates"),
        "issues": {r["check_name"]: r["affected_rows"] for r in rows(con, "SELECT * FROM dq_issues")},
        "assertions": {r["check_name"]: r["status"] for r in rows(con, "SELECT * FROM dq_assertions")},
    }
    metrics = {
        "project": CONFIG["project"],
        "dataset": CONFIG["dataset"],
        "source_mode": a.source,
        "kpis": kpi,
        "breakdowns": {name: rows(con, q) for name, q in CONFIG["breakdowns"].items()},
        "data_quality": dq,
        "engine": {"duckdb": duckdb.__version__, "python": platform.python_version()},
        "sql_timings_s": timings,
    }
    res.mkdir(parents=True, exist_ok=True)
    if a.source == "full":
        (res / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    shot = {
        "snapshot": "headline KPIs + run config",
        "project": CONFIG["project"],
        "source_mode": a.source,
        "config": dict(CONFIG["shot_config"], engine=f"duckdb {duckdb.__version__}",
                       sql_dialect="Spark/Databricks SQL (+ DuckDB shims in 00)"),
        "headline": {k: kpi[k] for k in CONFIG["headline"]},
        "highlights": {name: rows(con, q) for name, q in CONFIG["highlights"].items()},
        "assertions_passed": sum(1 for v in dq["assertions"].values() if v == "PASS"),
        "assertions_total": len(dq["assertions"]),
    }
    (res / "JSON.shot").write_text(json.dumps(shot, indent=2) + "\n")
    print(json.dumps(shot["headline"], indent=2))
    print("assertions", shot["assertions_passed"], "/", shot["assertions_total"])

    if a.source == "full" and not a.no_charts:
        import importlib.util
        spec = importlib.util.spec_from_file_location("make_charts", ROOT / "scripts" / "make_charts.py")
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        mod.make_all(res / "tables", res / "charts")


if __name__ == "__main__":
    main()
