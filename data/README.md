# Data

| Folder | Content | In git? |
|---|---|---|
| `raw/` | **Reproducible subset** of the three raw CSVs (original columns, values copied verbatim) | yes |
| `clean/cleaned/` | Cleaned medical + motor-claim tables from `sql/02_cleaning.sql`, run on the subset | yes |
| `raw_full/` | Full data (~33 MB CSV + source Parquet) - `python scripts/download_full_data.py` | no (`.gitignore`) |
| `clean_full/` | Cleaned + star-schema tables from the full run (`--source full`, ~57 MB) | no (`.gitignore`) |

## Sources
| File | Dataset | Kaggle page | Mirror used | Licence |
|---|---|---|---|---|
| `insurance.csv` | Medical Cost Personal Dataset (1,338 rows x 7) | https://www.kaggle.com/datasets/mirichoi0218/insurance | https://raw.githubusercontent.com/stedy/Machine-Learning-with-R-datasets/master/insurance.csv | Kaggle page: Open Database License (ODbL); data originally published with *Machine Learning with R* (Brett Lantz) |
| `freMTPL2freq.csv` | French motor third-party-liability policies (678,013 rows x 12) | https://www.kaggle.com/datasets/floser/french-motor-claims-datasets-fremtpl2freq | OpenML 41214: https://data.openml.org/datasets/0004/41214/dataset_41214.pq | CC0 (OpenML); originally from the R package CASdatasets (Dutang & Charpentier) |
| `freMTPL2sev.csv` | Claim amounts for those policies (26,639 rows x 2) | (same Kaggle page) | OpenML 41215: https://data.openml.org/datasets/0004/41215/dataset_41215.pq | CC0 (OpenML) |

The motor files are distributed by OpenML as Parquet; `download_full_data.py` pins their SHA-256 and writes CSV
(IDpol as an integer, all other values unchanged), so every engine reads the same CSVs.

**Version note:** OpenML 41214/41215 (uploaded 2018) is the original freMTPL2 release (678,013 policies, 26,639 claim rows).
The current CASdatasets R package ships a corrected version (677,991 policies, 26,444 claims); the 26,444 clean claims here
coincide with that figure after the orphan-claim filter. The policies were observed mostly in 2011-2013 by an unnamed French insurer.

**Dataset choice note:** the brief asked for "a medical insurance cost / car insurance claims dataset". The medical
file alone (1,338 rows) has no claim counts, so it is paired with the standard actuarial motor-claims benchmark
(freMTPL2) to cover claim **frequency** and **severity** on 678k real policies.

## Why a subset in git
This series publishes through a text-only GitHub API, so git holds a documented sample + a checksum-verified
download script. **All numbers in `results/` come from the FULL data.**

## Subset rule (`scripts/make_sample.py`, deterministic)
* `insurance.csv`: file rows whose 1-based row number % 10 = 1 -> **134 people**
* `freMTPL2freq.csv`: `IDpol % 2000 = 7` -> **340 policies**
* `freMTPL2sev.csv`: claim rows of those sampled policies -> **10 claims**
