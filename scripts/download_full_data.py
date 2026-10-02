#!/usr/bin/env python3
"""Download the full insurance datasets into data/raw_full/ and verify SHA-256.

1. Medical Cost Personal Dataset (insurance.csv, 1,338 rows)
   Kaggle : https://www.kaggle.com/datasets/mirichoi0218/insurance
   Mirror : https://raw.githubusercontent.com/stedy/Machine-Learning-with-R-datasets/master/insurance.csv
            (the original source used by the Kaggle upload: "Machine Learning with R", Brett Lantz)
2. French Motor Third-Party Liability claims (CASdatasets freMTPL2freq + freMTPL2sev)
   Kaggle : https://www.kaggle.com/datasets/floser/french-motor-claims-datasets-fremtpl2freq
   Mirror : OpenML dataset 41214 (freMTPL2freq, 678,013 policies) and 41215 (freMTPL2sev, 26,639 claims), CC0
            https://data.openml.org/datasets/0004/41214/dataset_41214.pq
            https://data.openml.org/datasets/0004/41215/dataset_41215.pq
   The Parquet files are SHA-256 pinned and converted to CSV (IDpol written as an integer, values otherwise unchanged).
"""
import hashlib, pathlib, urllib.request
import duckdb

FILES = {
    "insurance.csv": ("https://raw.githubusercontent.com/stedy/Machine-Learning-with-R-datasets/master/insurance.csv",
                      "505c1cbc2e63d0363bac59501563df2530aadf4cdb9cfee226f4ef32f5468281"),
    "freMTPL2freq.pq": ("https://data.openml.org/datasets/0004/41214/dataset_41214.pq", "aead80a9ac68baf2c78fc1beaa287441d88d06cc11be60a1f226784d164c6dd7"),
    "freMTPL2sev.pq": ("https://data.openml.org/datasets/0004/41215/dataset_41215.pq", "c721d570c42eeaf4a70cc12f4c1e04095a6046f6cdbc01fad919274879783e60"),
}
out = pathlib.Path(__file__).resolve().parents[1] / "data" / "raw_full"
out.mkdir(parents=True, exist_ok=True)
for name, (url, sha) in FILES.items():
    p = out / name
    if not p.exists():
        print("downloading", name)
        urllib.request.urlretrieve(url, p)
    got = hashlib.sha256(p.read_bytes()).hexdigest()
    print(f"{name:20s} {'OK' if got == sha else 'CHECKSUM MISMATCH ' + got}")
    if got != sha:
        raise SystemExit(1)
con = duckdb.connect()
for stem in ["freMTPL2freq", "freMTPL2sev"]:
    src, dst = (out / f"{stem}.pq").as_posix(), (out / f"{stem}.csv").as_posix()
    con.execute(f"""COPY (SELECT * REPLACE (CAST(IDpol AS BIGINT) AS IDpol) FROM read_parquet('{src}'))
                    TO '{dst}' (HEADER, DELIMITER ',')""")
    n = con.execute(f"SELECT COUNT(*) FROM read_csv('{dst}', all_varchar = true)").fetchone()[0]
    print(f"{stem}.csv {n:,} rows")
