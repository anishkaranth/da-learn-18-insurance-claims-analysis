-- 05_quality_checks.sql  Data-quality evidence: before/after counts, issue counts, assertions (Spark SQL dialect)

CREATE OR REPLACE TABLE dq_row_counts AS
SELECT 'medical' AS entity, (SELECT COUNT(*) FROM stg_medical) AS raw_rows,
       (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM stg_medical) d) AS distinct_keys,
       (SELECT COUNT(*) FROM cln_medical) AS clean_rows, 'all 7 columns (no natural key)' AS grain
UNION ALL SELECT 'motor_policy', (SELECT COUNT(*) FROM stg_motor_policy),
       (SELECT COUNT(DISTINCT TRY_CAST(IDpol AS BIGINT)) FROM stg_motor_policy),
       (SELECT COUNT(*) FROM cln_motor_policy), 'IDpol'
UNION ALL SELECT 'motor_claim', (SELECT COUNT(*) FROM stg_motor_claim),
       (SELECT COUNT(DISTINCT TRY_CAST(IDpol AS BIGINT)) FROM stg_motor_claim),
       (SELECT COUNT(*) FROM cln_motor_claim), 'claim row (IDpol repeats)'
UNION ALL SELECT 'fact_medical_member', NULL, NULL, (SELECT COUNT(*) FROM fact_medical_member), 'member'
UNION ALL SELECT 'fact_motor_policy', NULL, NULL, (SELECT COUNT(*) FROM fact_motor_policy), 'policy'
UNION ALL SELECT 'fact_motor_claim', NULL, NULL, (SELECT COUNT(*) FROM fact_motor_claim), 'claim'
UNION ALL SELECT 'dim_med_region', NULL, NULL, (SELECT COUNT(*) FROM dim_med_region), 'US region'
UNION ALL SELECT 'dim_bmi_category', NULL, NULL, (SELECT COUNT(*) FROM dim_bmi_category), 'WHO BMI class'
UNION ALL SELECT 'dim_area', NULL, NULL, (SELECT COUNT(*) FROM dim_area), 'area code A-F'
UNION ALL SELECT 'dim_fr_region', NULL, NULL, (SELECT COUNT(*) FROM dim_fr_region), 'French region'
UNION ALL SELECT 'dim_vehicle', NULL, NULL, (SELECT COUNT(*) FROM dim_vehicle), 'brand + fuel + power'
UNION ALL SELECT 'dim_driver_age_band', NULL, NULL, (SELECT COUNT(*) FROM dim_driver_age_band), 'driver age band';

CREATE OR REPLACE TABLE dq_null_rates AS
SELECT 'medical' AS entity, 'charges' AS column_name,
  (SELECT ROUND(100.0 * SUM(CASE WHEN charges IS NULL OR trim(charges) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_medical) AS raw_null_pct,
  (SELECT ROUND(100.0 * SUM(CASE WHEN charges IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_medical) AS clean_null_pct,
  'required (> 0)' AS treatment
UNION ALL SELECT 'medical', 'bmi',
  (SELECT ROUND(100.0 * SUM(CASE WHEN bmi IS NULL OR trim(bmi) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_medical),
  (SELECT ROUND(100.0 * SUM(CASE WHEN bmi IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_medical), 'required (10-80)'
UNION ALL SELECT 'motor_policy', 'Exposure',
  (SELECT ROUND(100.0 * SUM(CASE WHEN Exposure IS NULL OR trim(Exposure) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_motor_policy),
  (SELECT ROUND(100.0 * SUM(CASE WHEN exposure IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_motor_policy), 'required (> 0), capped at 1'
UNION ALL SELECT 'motor_policy', 'DrivAge',
  (SELECT ROUND(100.0 * SUM(CASE WHEN DrivAge IS NULL OR trim(DrivAge) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_motor_policy),
  (SELECT ROUND(100.0 * SUM(CASE WHEN driv_age IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_motor_policy), 'required (18-110)'
UNION ALL SELECT 'motor_claim', 'ClaimAmount',
  (SELECT ROUND(100.0 * SUM(CASE WHEN ClaimAmount IS NULL OR trim(ClaimAmount) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_motor_claim),
  (SELECT ROUND(100.0 * SUM(CASE WHEN claim_amount IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_motor_claim), 'required (> 0)';

CREATE OR REPLACE TABLE dq_issues AS
SELECT 'medical: exact duplicate rows dropped' AS check_name,
       (SELECT COUNT(*) FROM stg_medical) - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM stg_medical) d) AS affected_rows
UNION ALL SELECT 'medical: rows dropped in cleaning (total)', (SELECT COUNT(*) FROM stg_medical) - (SELECT COUNT(*) FROM cln_medical)
UNION ALL SELECT 'medical: charges outlier (> Q3 + 1.5*IQR, kept)', (SELECT SUM(is_charges_outlier_iqr15) FROM cln_medical)
UNION ALL SELECT 'medical: charges top 1% (kept)', (SELECT SUM(is_charges_top1pct) FROM cln_medical)
UNION ALL SELECT 'motor_policy: duplicate IDpol', (SELECT COUNT(*) FROM stg_motor_policy) - (SELECT COUNT(DISTINCT TRY_CAST(IDpol AS BIGINT)) FROM stg_motor_policy)
UNION ALL SELECT 'motor_policy: rows dropped in cleaning (total)', (SELECT COUNT(*) FROM stg_motor_policy) - (SELECT COUNT(*) FROM cln_motor_policy)
UNION ALL SELECT 'motor_policy: Exposure > 1 year (capped at 1)', (SELECT SUM(is_exposure_capped) FROM cln_motor_policy)
UNION ALL SELECT 'motor_policy: ClaimNb > 4 (capped at 4)', (SELECT SUM(is_claim_nb_capped) FROM cln_motor_policy)
UNION ALL SELECT 'motor_policy: VehAge > 30 (flagged, kept)', (SELECT SUM(is_veh_age_outlier) FROM cln_motor_policy)
UNION ALL SELECT 'motor_policy: DrivAge > 90 (flagged, kept)', (SELECT SUM(is_driv_age_outlier) FROM cln_motor_policy)
UNION ALL SELECT 'motor_policy: ClaimNb > 0 but no severity record', (SELECT COUNT(*) FROM fact_motor_policy WHERE claim_nb_raw > 0 AND claims_with_amount = 0)
UNION ALL SELECT 'motor_policy: severity records <> ClaimNb (both > 0)', (SELECT COUNT(*) FROM fact_motor_policy WHERE claims_with_amount > 0 AND claims_with_amount <> claim_nb_raw)
UNION ALL SELECT 'motor_claim: orphan claims (IDpol not in policy file, dropped)',
       (SELECT COUNT(*) FROM stg_motor_claim WHERE TRY_CAST(IDpol AS BIGINT) NOT IN (SELECT policy_id FROM cln_motor_policy))
UNION ALL SELECT 'motor_claim: large losses (top 1%, kept)', (SELECT SUM(is_large_loss) FROM cln_motor_claim)
UNION ALL SELECT 'RI: fact_motor_policy rows lost in dim joins', (SELECT COUNT(*) FROM cln_motor_policy) - (SELECT COUNT(*) FROM fact_motor_policy)
UNION ALL SELECT 'RI: fact_medical_member rows lost in dim joins', (SELECT COUNT(*) FROM cln_medical) - (SELECT COUNT(*) FROM fact_medical_member);

CREATE OR REPLACE TABLE dq_assertions AS
WITH c AS (
  SELECT 'fact_medical_member.member_id unique' AS check_name,
         (SELECT COUNT(*) - COUNT(DISTINCT member_id) FROM fact_medical_member) AS failed_rows
  UNION ALL SELECT 'fact_motor_policy.policy_id unique', (SELECT COUNT(*) - COUNT(DISTINCT policy_id) FROM fact_motor_policy)
  UNION ALL SELECT 'fact_motor_claim.claim_id unique', (SELECT COUNT(*) - COUNT(DISTINCT claim_id) FROM fact_motor_claim)
  UNION ALL SELECT 'fact_medical_member.med_region_key -> dim_med_region',
         (SELECT COUNT(*) FROM fact_medical_member WHERE med_region_key NOT IN (SELECT med_region_key FROM dim_med_region))
  UNION ALL SELECT 'fact_motor_policy.vehicle_key -> dim_vehicle',
         (SELECT COUNT(*) FROM fact_motor_policy WHERE vehicle_key NOT IN (SELECT vehicle_key FROM dim_vehicle))
  UNION ALL SELECT 'fact_motor_claim.policy_id -> fact_motor_policy',
         (SELECT COUNT(*) FROM fact_motor_claim WHERE policy_id NOT IN (SELECT policy_id FROM fact_motor_policy))
  UNION ALL SELECT 'exposure in (0, 1]', (SELECT COUNT(*) FROM fact_motor_policy WHERE exposure <= 0 OR exposure > 1)
  UNION ALL SELECT 'claim_nb in 0..4', (SELECT COUNT(*) FROM fact_motor_policy WHERE claim_nb < 0 OR claim_nb > 4)
  UNION ALL SELECT 'claim_amount > 0', (SELECT COUNT(*) FROM fact_motor_claim WHERE claim_amount <= 0)
  UNION ALL SELECT 'medical charges > 0', (SELECT COUNT(*) FROM fact_medical_member WHERE charges <= 0)
  UNION ALL SELECT 'medical smoker_flag in {0,1}', (SELECT COUNT(*) FROM fact_medical_member WHERE smoker_flag NOT IN (0, 1))
  UNION ALL SELECT 'claim amounts reconcile (fact_motor_claim = fact_motor_policy)',
         (SELECT CASE WHEN ABS((SELECT SUM(claim_amount) FROM fact_motor_claim) - (SELECT SUM(claim_amount_total) FROM fact_motor_policy)) < 1 THEN 0 ELSE 1 END)
)
SELECT check_name, failed_rows, CASE WHEN failed_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS status FROM c;
