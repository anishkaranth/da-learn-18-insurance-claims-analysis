# Power BI build guide

> A `.pbix` cannot be produced on the Linux box this project was built on (Power BI Desktop is Windows-only and has
> no headless authoring mode), so this folder is a **kit**: star-schema CSVs + model + measures + page spec.
> Estimated build time: 45-60 min.

1. **Get the data.** `powerbi/data/` holds the star schema built from the **repo sample** (134 people, 340 policies, 10 claims) -
   enough to build and test visuals. For real numbers regenerate the full star:
   `pip install -r requirements.txt && python scripts/download_full_data.py && python run_pipeline.py --source full`
   then load `data/clean_full/star/*.csv` (9 files).
2. **Load.** Power BI Desktop -> *Get data -> Text/CSV* for each file. Set types as in `model.md`. Locale English (United States).
3. **Model.** Model view -> create the relationships in `model.md` (all *:1, single direction). Hide keys and flags.
4. **Measures.** Create a `_Measures` table and paste the measures from `measures.dax`. Format: currency for charges (USD) and
   claim amounts (EUR), percentage for % measures, 4 decimals for Claim Frequency.
5. **Pages.** Build the 3 pages in `dashboard_spec.md`; compare with `results/charts/dashboard.svg`.
6. **Validate** (full data): Avg Charges $13,279.12; Smoker Loading 3.80x; Claim Frequency 0.10061; Avg Severity EUR 2,265.51.
   Sample-mode expected values are in `results/sample/JSON.shot`.
7. Save as `insurance_claims.pbix` (not committed - binary).
