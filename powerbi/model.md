# Power BI model

Two independent star schemas share one report. Files in `powerbi/data/` are produced by
`python run_pipeline.py --source sample` (repo subset). For the full model run `--source full` and load
`data/clean_full/star/*.csv` instead (fact_motor_policy is 678,013 rows / ~57 MB).

## Tables
| Table | Grain | Keys / important columns |
|---|---|---|
| `fact_medical_member` | one insured person | `member_id`, `med_region_key`, `bmi_key`, `age`, `age_band`, `sex`, `bmi`, `children`, `smoker_flag`, `charges` |
| `dim_med_region` | US region (4) | `med_region_key`, `region_name` |
| `dim_bmi_category` | WHO BMI class (4) | `bmi_key`, `bmi_category`, `bmi_range` |
| `fact_motor_policy` | one motor TPL policy | `policy_id`, `area_key`, `fr_region_key`, `vehicle_key`, `driver_age_key`, `claim_nb`, `exposure`, `claims_with_amount`, `claim_amount_total`, `bonus_malus_band`, `vehicle_age_band` |
| `fact_motor_claim` | one claim with an amount | `claim_id`, `policy_id`, same dimension keys, `claim_amount`, `claim_size_band`, `is_large_loss` |
| `dim_area` | area code A-F (6) | `area_key`, `area_code`, `median_density` |
| `dim_fr_region` | French region (22) | `fr_region_key`, `region_code` |
| `dim_vehicle` | brand x fuel x power | `vehicle_key`, `veh_brand`, `veh_gas`, `veh_power` |
| `dim_driver_age_band` | driver age band (8) | `driver_age_key`, `driver_age_band`, `min_age`, `max_age` |

## Relationships (*:1, single direction)
1. `fact_medical_member[med_region_key]` -> `dim_med_region[med_region_key]`
2. `fact_medical_member[bmi_key]` -> `dim_bmi_category[bmi_key]`
3. `fact_motor_policy[area_key]` -> `dim_area[area_key]` (same for `fact_motor_claim`)
4. `fact_motor_policy[fr_region_key]` -> `dim_fr_region[fr_region_key]` (same for `fact_motor_claim`)
5. `fact_motor_policy[vehicle_key]` -> `dim_vehicle[vehicle_key]` (same for `fact_motor_claim`)
6. `fact_motor_policy[driver_age_key]` -> `dim_driver_age_band[driver_age_key]` (same for `fact_motor_claim`)
7. Optional: `fact_motor_claim[policy_id]` -> `fact_motor_policy[policy_id]` (*:1) - only if you need policy attributes on claims; keep it inactive otherwise to avoid ambiguous paths.

## Data types
* Keys, counts, ages, `claim_nb`, flags: Whole number
* `charges`, `bmi`, `exposure`, `claim_amount`, `claim_amount_total`: Decimal number
* Band / label columns: Text (sort `*_band` columns by themselves - the `NN:` prefix keeps order)
* No date table: neither source has calendar dates (motor exposure is a fraction of one policy year).

Hide key, `is_*` flag and `*_raw` columns from report view.
