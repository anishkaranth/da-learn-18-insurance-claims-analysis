-- 02_cleaning.sql  (Spark SQL dialect; runs on DuckDB via 00_duckdb_compat.sql shims)
-- Steps per entity: trim/standardise text -> TRY_CAST types -> null handling -> dedupe
--                   -> derived bands -> outlier / capping flags -> integrity filters.

-- ---------------------------------------------------------------- medical (insurance.csv)
-- No natural key: duplicates are exact duplicates across all 7 columns; a deterministic member_id
-- is assigned after dedupe.
CREATE OR REPLACE TABLE cln_medical AS
WITH typed AS (
  SELECT
    TRY_CAST(trim(age) AS INT)                                         AS age,
    CASE WHEN lower(trim(sex)) IN ('male', 'm') THEN 'male'
         WHEN lower(trim(sex)) IN ('female', 'f') THEN 'female'
         ELSE NULL END                                                 AS sex,
    TRY_CAST(trim(bmi) AS DOUBLE)                                      AS bmi,
    TRY_CAST(trim(children) AS INT)                                    AS children,
    CASE WHEN lower(trim(smoker)) IN ('yes', 'y', '1', 'true') THEN 1
         WHEN lower(trim(smoker)) IN ('no', 'n', '0', 'false') THEN 0
         ELSE NULL END                                                 AS smoker_flag,
    lower(trim(region))                                                AS region,
    TRY_CAST(trim(charges) AS DOUBLE)                                  AS charges
  FROM stg_medical
), dedup AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY age, sex, bmi, children, smoker_flag, region, charges
                               ORDER BY age) AS rn
  FROM typed
), valid AS (
  SELECT * FROM dedup
  WHERE rn = 1 AND age BETWEEN 18 AND 100 AND sex IS NOT NULL AND smoker_flag IS NOT NULL
    AND region IS NOT NULL AND charges > 0 AND bmi BETWEEN 10 AND 80 AND children >= 0
), bounds AS (
  SELECT percentile_approx(charges, 0.25) AS q1, percentile_approx(charges, 0.75) AS q3,
         percentile_approx(charges, 0.99) AS p99
  FROM valid
)
SELECT
  CAST(ROW_NUMBER() OVER (ORDER BY v.age, v.sex, v.bmi, v.children, v.smoker_flag, v.region, v.charges) AS INT) AS member_id,
  v.age, v.sex, v.bmi, v.children, v.smoker_flag,
  CASE WHEN v.smoker_flag = 1 THEN 'smoker' ELSE 'non-smoker' END     AS smoker_status,
  v.region,
  ROUND(v.charges, 2)                                                 AS charges,
  CASE WHEN v.age < 25 THEN '01: 18-24' WHEN v.age < 35 THEN '02: 25-34' WHEN v.age < 45 THEN '03: 35-44'
       WHEN v.age < 55 THEN '04: 45-54' ELSE '05: 55-64' END          AS age_band,
  CASE WHEN v.bmi < 18.5 THEN '1: Underweight' WHEN v.bmi < 25 THEN '2: Normal'
       WHEN v.bmi < 30 THEN '3: Overweight' ELSE '4: Obese' END       AS bmi_category,
  CASE WHEN v.bmi >= 30 THEN 1 ELSE 0 END                             AS obese_flag,
  CASE WHEN v.children >= 3 THEN '3+' ELSE CAST(v.children AS STRING) END AS children_band,
  CASE WHEN v.charges > b.q3 + 1.5 * (b.q3 - b.q1) THEN 1 ELSE 0 END  AS is_charges_outlier_iqr15,
  CASE WHEN v.charges > b.p99 THEN 1 ELSE 0 END                       AS is_charges_top1pct
FROM valid v CROSS JOIN bounds b;

-- ---------------------------------------------------------------- motor policies (freMTPL2freq)
-- Actuarial conventions (as in the CASdatasets / Noll-Salzmann-Wuthrich case study):
--   Exposure capped at 1 year, ClaimNb capped at 4 per policy; both flagged.
CREATE OR REPLACE TABLE cln_motor_policy AS
WITH typed AS (
  SELECT
    TRY_CAST(trim(IDpol) AS BIGINT)                                    AS policy_id,
    TRY_CAST(trim(ClaimNb) AS INT)                                     AS claim_nb_raw,
    TRY_CAST(trim(Exposure) AS DOUBLE)                                 AS exposure_raw,
    upper(trim(replace(Area, '''', '')))                               AS area_code,
    TRY_CAST(trim(VehPower) AS INT)                                    AS veh_power,
    TRY_CAST(trim(VehAge) AS INT)                                      AS veh_age,
    TRY_CAST(trim(DrivAge) AS INT)                                     AS driv_age,
    TRY_CAST(trim(BonusMalus) AS INT)                                  AS bonus_malus,
    upper(trim(replace(VehBrand, '''', '')))                           AS veh_brand,
    CASE WHEN lower(trim(replace(VehGas, '''', ''))) = 'diesel' THEN 'Diesel'
         WHEN lower(trim(replace(VehGas, '''', ''))) = 'regular' THEN 'Regular'
         ELSE NULL END                                                 AS veh_gas,
    TRY_CAST(trim(Density) AS DOUBLE)                                  AS density,
    upper(trim(replace(Region, '''', '')))                             AS region_code
  FROM stg_motor_policy
), dedup AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY policy_id ORDER BY exposure_raw DESC) AS rn
  FROM typed WHERE policy_id IS NOT NULL
)
SELECT
  policy_id,
  claim_nb_raw,
  LEAST(claim_nb_raw, 4)                                              AS claim_nb,
  exposure_raw,
  LEAST(exposure_raw, 1.0)                                            AS exposure,
  CASE WHEN claim_nb_raw > 4 THEN 1 ELSE 0 END                        AS is_claim_nb_capped,
  CASE WHEN exposure_raw > 1 THEN 1 ELSE 0 END                        AS is_exposure_capped,
  CASE WHEN claim_nb_raw > 0 THEN 1 ELSE 0 END                        AS has_claim,
  area_code, veh_power, veh_age, driv_age, bonus_malus, veh_brand, veh_gas,
  CAST(density AS INT)                                                AS density,
  region_code,
  CASE WHEN driv_age < 21 THEN '01: 18-20' WHEN driv_age < 26 THEN '02: 21-25' WHEN driv_age < 31 THEN '03: 26-30'
       WHEN driv_age < 41 THEN '04: 31-40' WHEN driv_age < 51 THEN '05: 41-50' WHEN driv_age < 61 THEN '06: 51-60'
       WHEN driv_age < 71 THEN '07: 61-70' ELSE '08: 71+' END         AS driver_age_band,
  CASE WHEN veh_age = 0 THEN '01: new (0)' WHEN veh_age <= 2 THEN '02: 1-2' WHEN veh_age <= 5 THEN '03: 3-5'
       WHEN veh_age <= 10 THEN '04: 6-10' WHEN veh_age <= 15 THEN '05: 11-15' ELSE '06: 16+' END AS vehicle_age_band,
  CASE WHEN bonus_malus = 50 THEN '01: 50 (max bonus)' WHEN bonus_malus <= 60 THEN '02: 51-60'
       WHEN bonus_malus <= 80 THEN '03: 61-80' WHEN bonus_malus <= 100 THEN '04: 81-100'
       ELSE '05: 101+ (malus)' END                                    AS bonus_malus_band,
  CASE WHEN veh_age > 30 THEN 1 ELSE 0 END                            AS is_veh_age_outlier,
  CASE WHEN driv_age > 90 THEN 1 ELSE 0 END                           AS is_driv_age_outlier
FROM dedup
WHERE rn = 1
  AND claim_nb_raw IS NOT NULL AND claim_nb_raw >= 0
  AND exposure_raw > 0
  AND driv_age BETWEEN 18 AND 110
  AND veh_age >= 0
  AND bonus_malus BETWEEN 50 AND 350
  AND area_code IS NOT NULL AND region_code IS NOT NULL AND veh_brand IS NOT NULL AND veh_gas IS NOT NULL;

-- ---------------------------------------------------------------- motor claims (freMTPL2sev)
-- One row per claim. Integrity: claims whose IDpol is not in the policy table are dropped
-- (counted in 05). Large-loss flag = top 1 % of claim amounts.
CREATE OR REPLACE TABLE cln_motor_claim AS
WITH typed AS (
  SELECT TRY_CAST(trim(IDpol) AS BIGINT) AS policy_id, TRY_CAST(trim(ClaimAmount) AS DOUBLE) AS claim_amount
  FROM stg_motor_claim
), valid AS (
  SELECT t.* FROM typed t
  WHERE t.policy_id IS NOT NULL AND t.claim_amount > 0
    AND t.policy_id IN (SELECT policy_id FROM cln_motor_policy)
), bounds AS (
  SELECT percentile_approx(claim_amount, 0.99) AS p99 FROM valid
)
SELECT
  CAST(ROW_NUMBER() OVER (ORDER BY v.policy_id, v.claim_amount) AS INT) AS claim_id,
  v.policy_id,
  ROUND(v.claim_amount, 2)                                            AS claim_amount,
  CASE WHEN v.claim_amount < 500 THEN '01: <500' WHEN v.claim_amount < 1000 THEN '02: 500-1k'
       WHEN v.claim_amount < 1500 THEN '03: 1k-1.5k' WHEN v.claim_amount < 5000 THEN '04: 1.5k-5k'
       WHEN v.claim_amount < 20000 THEN '05: 5k-20k' WHEN v.claim_amount < 100000 THEN '06: 20k-100k'
       ELSE '07: 100k+' END                                           AS claim_size_band,
  CASE WHEN v.claim_amount > b.p99 THEN 1 ELSE 0 END                  AS is_large_loss
FROM valid v CROSS JOIN bounds b;
