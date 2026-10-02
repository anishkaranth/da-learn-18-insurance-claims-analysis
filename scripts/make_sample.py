#!/usr/bin/env python3
"""Build a reproducible raw subset in data/raw/ from data/raw_full/ (deterministic, no randomness).

Rules
  insurance.csv     : keep file rows whose 1-based line number % 10 = 1   (~134 of 1,338 people)
  freMTPL2freq.csv  : keep policies with IDpol % 2000 = 7                (~340 of 678,013 policies)
  freMTPL2sev.csv   : keep the claim rows of exactly those sampled policies
Values are copied verbatim as strings; cleaning happens in sql/02_cleaning.sql.
"""
import pathlib, duckdb

ROOT = pathlib.Path(__file__).resolve().parents[1]
FULL, OUT = ROOT / "data/raw_full", ROOT / "data/raw"
OUT.mkdir(parents=True, exist_ok=True)
con = duckdb.connect()
con.execute("SET preserve_insertion_order = true")
q = {
    "insurance.csv": f"""SELECT * EXCLUDE (rn) FROM (
            SELECT *, ROW_NUMBER() OVER () AS rn FROM read_csv('{(FULL / 'insurance.csv').as_posix()}', header = true, all_varchar = true))
         WHERE rn % 10 = 1 ORDER BY rn""",
    "freMTPL2freq.csv": f"""SELECT * FROM read_csv('{(FULL / 'freMTPL2freq.csv').as_posix()}', header = true, all_varchar = true)
         WHERE CAST(IDpol AS BIGINT) % 2000 = 7 ORDER BY CAST(IDpol AS BIGINT)""",
    "freMTPL2sev.csv": f"""SELECT * FROM read_csv('{(FULL / 'freMTPL2sev.csv').as_posix()}', header = true, all_varchar = true)
         WHERE CAST(IDpol AS BIGINT) % 2000 = 7 ORDER BY CAST(IDpol AS BIGINT), CAST(ClaimAmount AS DOUBLE)""",
}
for name, sql in q.items():
    dst = (OUT / name).as_posix()
    con.execute(f"COPY ({sql}) TO '{dst}' (HEADER, DELIMITER ',')")
    n = con.execute(f"SELECT COUNT(*) FROM read_csv('{dst}', header = true, all_varchar = true)").fetchone()[0]
    print(f"{name:18s} {n:6,d} rows")
