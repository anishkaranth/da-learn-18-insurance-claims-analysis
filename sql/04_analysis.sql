-- 04_analysis.sql  Business KPI queries (Spark SQL dialect). Each result is materialised as an a_* table
-- and exported by run_pipeline.py to results/tables/<name>.csv.
-- Definitions
--   claim frequency  = SUM(claim_nb) / SUM(exposure)          (claims per policy-year, capped values)
--   severity         = SUM(claim_amount) / COUNT(claims)      (EUR per claim with a recorded amount)
--   pure premium     = SUM(claim_amount_total) / SUM(exposure) (EUR loss cost per policy-year)
--   smoker loading   = avg charges smokers / avg charges non-smokers

-- Q1 Headline KPIs (medical + motor)
CREATE OR REPLACE TABLE a_kpi_headline AS
SELECT
  m.members, m.avg_charges, m.median_charges, m.total_charges, m.smoker_pct,
  m.avg_charges_smoker, m.avg_charges_non_smoker,
  ROUND(m.avg_charges_smoker / m.avg_charges_non_smoker, 2)      AS smoker_loading_x,
  m.obese_pct, m.avg_bmi, m.avg_age,
  p.policies, p.exposure_years, p.claims, p.policies_with_claim_pct,
  ROUND(p.claims / p.exposure_years, 5)                           AS claim_frequency,
  c.claim_records, c.total_claim_amount, c.avg_severity, c.median_severity,
  ROUND(c.total_claim_amount / p.exposure_years, 2)               AS pure_premium,
  c.large_loss_share_pct
FROM (
  SELECT COUNT(*) AS members, ROUND(AVG(charges), 2) AS avg_charges,
         ROUND(percentile_approx(charges, 0.5), 2) AS median_charges, ROUND(SUM(charges), 2) AS total_charges,
         ROUND(100.0 * AVG(smoker_flag), 2) AS smoker_pct,
         ROUND(AVG(CASE WHEN smoker_flag = 1 THEN charges END), 2) AS avg_charges_smoker,
         ROUND(AVG(CASE WHEN smoker_flag = 0 THEN charges END), 2) AS avg_charges_non_smoker,
         ROUND(100.0 * AVG(obese_flag), 2) AS obese_pct, ROUND(AVG(bmi), 2) AS avg_bmi, ROUND(AVG(age), 2) AS avg_age
  FROM fact_medical_member) m
CROSS JOIN (
  SELECT COUNT(*) AS policies, ROUND(SUM(exposure), 2) AS exposure_years, SUM(claim_nb) AS claims,
         ROUND(100.0 * AVG(has_claim), 3) AS policies_with_claim_pct
  FROM fact_motor_policy) p
CROSS JOIN (
  SELECT COUNT(*) AS claim_records, ROUND(SUM(claim_amount), 2) AS total_claim_amount,
         ROUND(AVG(claim_amount), 2) AS avg_severity, ROUND(percentile_approx(claim_amount, 0.5), 2) AS median_severity,
         ROUND(100.0 * SUM(CASE WHEN is_large_loss = 1 THEN claim_amount ELSE 0 END) / SUM(claim_amount), 2) AS large_loss_share_pct
  FROM fact_motor_claim) c;

-- Q2 Medical: smoker vs non-smoker
CREATE OR REPLACE TABLE a_med_smoker AS
SELECT smoker_status, COUNT(*) AS members, ROUND(AVG(charges), 2) AS avg_charges,
       ROUND(percentile_approx(charges, 0.5), 2) AS median_charges, ROUND(SUM(charges), 2) AS total_charges,
       ROUND(100.0 * SUM(charges) / SUM(SUM(charges)) OVER (), 2) AS share_of_total_charges_pct
FROM fact_medical_member GROUP BY smoker_status;

-- Q3 Medical: age band x smoker
CREATE OR REPLACE TABLE a_med_age_smoker AS
SELECT age_band,
       COUNT(*) AS members,
       ROUND(AVG(charges), 2) AS avg_charges,
       ROUND(AVG(CASE WHEN smoker_flag = 0 THEN charges END), 2) AS avg_charges_non_smoker,
       ROUND(AVG(CASE WHEN smoker_flag = 1 THEN charges END), 2) AS avg_charges_smoker
FROM fact_medical_member GROUP BY age_band;

-- Q4 Medical: BMI category x smoker (obesity interacts with smoking)
CREATE OR REPLACE TABLE a_med_bmi_smoker AS
SELECT b.bmi_category, b.bmi_range, COUNT(*) AS members,
       ROUND(AVG(f.charges), 2) AS avg_charges,
       ROUND(AVG(CASE WHEN f.smoker_flag = 0 THEN f.charges END), 2) AS avg_charges_non_smoker,
       ROUND(AVG(CASE WHEN f.smoker_flag = 1 THEN f.charges END), 2) AS avg_charges_smoker,
       SUM(f.smoker_flag) AS smokers
FROM fact_medical_member f JOIN dim_bmi_category b ON f.bmi_key = b.bmi_key
GROUP BY b.bmi_category, b.bmi_range;

-- Q5 Medical: region
CREATE OR REPLACE TABLE a_med_region AS
SELECT r.region_name, COUNT(*) AS members, ROUND(AVG(f.charges), 2) AS avg_charges,
       ROUND(percentile_approx(f.charges, 0.5), 2) AS median_charges,
       ROUND(100.0 * AVG(f.smoker_flag), 2) AS smoker_pct, ROUND(AVG(f.bmi), 2) AS avg_bmi,
       ROUND(AVG(CASE WHEN f.smoker_flag = 0 THEN f.charges END), 2) AS avg_charges_non_smoker
FROM fact_medical_member f JOIN dim_med_region r ON f.med_region_key = r.med_region_key
GROUP BY r.region_name;

-- Q6 Medical: children and sex
CREATE OR REPLACE TABLE a_med_children_sex AS
SELECT children_band, sex, COUNT(*) AS members, ROUND(AVG(charges), 2) AS avg_charges,
       ROUND(100.0 * AVG(smoker_flag), 2) AS smoker_pct
FROM fact_medical_member GROUP BY children_band, sex;

-- Q7 Medical: driver strength (Pearson correlation with charges, and smoker-segment slope per year of age)
CREATE OR REPLACE TABLE a_med_drivers AS
SELECT 'age' AS driver, ROUND(corr(CAST(age AS DOUBLE), charges), 4) AS corr_with_charges FROM fact_medical_member
UNION ALL SELECT 'bmi', ROUND(corr(bmi, charges), 4) FROM fact_medical_member
UNION ALL SELECT 'smoker_flag', ROUND(corr(CAST(smoker_flag AS DOUBLE), charges), 4) FROM fact_medical_member
UNION ALL SELECT 'children', ROUND(corr(CAST(children AS DOUBLE), charges), 4) FROM fact_medical_member
UNION ALL SELECT 'obese_flag', ROUND(corr(CAST(obese_flag AS DOUBLE), charges), 4) FROM fact_medical_member
UNION ALL SELECT 'age (non-smokers)', ROUND(corr(CAST(age AS DOUBLE), charges), 4) FROM fact_medical_member WHERE smoker_flag = 0
UNION ALL SELECT 'bmi (smokers)', ROUND(corr(bmi, charges), 4) FROM fact_medical_member WHERE smoker_flag = 1
UNION ALL SELECT 'bmi (non-smokers)', ROUND(corr(bmi, charges), 4) FROM fact_medical_member WHERE smoker_flag = 0;

-- Q8 Motor: frequency / severity / pure premium by driver age band
CREATE OR REPLACE TABLE a_motor_driver_age AS
SELECT d.driver_age_band, COUNT(*) AS policies, ROUND(SUM(f.exposure), 2) AS exposure_years,
       SUM(f.claim_nb) AS claims, ROUND(SUM(f.claim_nb) / SUM(f.exposure), 5) AS claim_frequency,
       ROUND(SUM(f.claim_amount_total) / NULLIF(SUM(f.claims_with_amount), 0), 2) AS avg_severity,
       ROUND(SUM(f.claim_amount_total) / SUM(f.exposure), 2) AS pure_premium
FROM fact_motor_policy f JOIN dim_driver_age_band d ON f.driver_age_key = d.driver_age_key
GROUP BY d.driver_age_band;

-- Q9 Motor: bonus-malus band (past claims experience)
CREATE OR REPLACE TABLE a_motor_bonus_malus AS
SELECT bonus_malus_band, COUNT(*) AS policies, ROUND(SUM(exposure), 2) AS exposure_years,
       SUM(claim_nb) AS claims, ROUND(SUM(claim_nb) / SUM(exposure), 5) AS claim_frequency,
       ROUND(SUM(claim_amount_total) / NULLIF(SUM(claims_with_amount), 0), 2) AS avg_severity,
       ROUND(SUM(claim_amount_total) / SUM(exposure), 2) AS pure_premium
FROM fact_motor_policy GROUP BY bonus_malus_band;

-- Q10 Motor: vehicle age band
CREATE OR REPLACE TABLE a_motor_vehicle_age AS
SELECT vehicle_age_band, COUNT(*) AS policies, ROUND(SUM(exposure), 2) AS exposure_years,
       SUM(claim_nb) AS claims, ROUND(SUM(claim_nb) / SUM(exposure), 5) AS claim_frequency,
       ROUND(SUM(claim_amount_total) / SUM(exposure), 2) AS pure_premium
FROM fact_motor_policy GROUP BY vehicle_age_band;

-- Q11 Motor: area (A = rural ... F = dense urban)
CREATE OR REPLACE TABLE a_motor_area AS
SELECT a.area_code, a.median_density, COUNT(*) AS policies, ROUND(SUM(f.exposure), 2) AS exposure_years,
       SUM(f.claim_nb) AS claims, ROUND(SUM(f.claim_nb) / SUM(f.exposure), 5) AS claim_frequency,
       ROUND(SUM(f.claim_amount_total) / NULLIF(SUM(f.claims_with_amount), 0), 2) AS avg_severity,
       ROUND(SUM(f.claim_amount_total) / SUM(f.exposure), 2) AS pure_premium
FROM fact_motor_policy f JOIN dim_area a ON f.area_key = a.area_key
GROUP BY a.area_code, a.median_density;

-- Q12 Motor: French region
CREATE OR REPLACE TABLE a_motor_region AS
SELECT g.region_code, COUNT(*) AS policies, ROUND(SUM(f.exposure), 2) AS exposure_years,
       SUM(f.claim_nb) AS claims, ROUND(SUM(f.claim_nb) / SUM(f.exposure), 5) AS claim_frequency,
       ROUND(SUM(f.claim_amount_total) / SUM(f.exposure), 2) AS pure_premium
FROM fact_motor_policy f JOIN dim_fr_region g ON f.fr_region_key = g.fr_region_key
GROUP BY g.region_code;

-- Q13 Motor: brand x fuel
CREATE OR REPLACE TABLE a_motor_brand_gas AS
SELECT v.veh_brand, v.veh_gas, COUNT(*) AS policies, ROUND(SUM(f.exposure), 2) AS exposure_years,
       SUM(f.claim_nb) AS claims, ROUND(SUM(f.claim_nb) / SUM(f.exposure), 5) AS claim_frequency
FROM fact_motor_policy f JOIN dim_vehicle v ON f.vehicle_key = v.vehicle_key
GROUP BY v.veh_brand, v.veh_gas;

-- Q14 Motor: claim-count distribution per policy (raw, before capping)
CREATE OR REPLACE TABLE a_motor_claim_count_dist AS
SELECT CASE WHEN claim_nb_raw >= 4 THEN '4+' ELSE CAST(claim_nb_raw AS STRING) END AS claims_on_policy,
       COUNT(*) AS policies, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 3) AS policies_pct
FROM fact_motor_policy
GROUP BY CASE WHEN claim_nb_raw >= 4 THEN '4+' ELSE CAST(claim_nb_raw AS STRING) END;

-- Q15 Motor: severity distribution - how concentrated are losses?
CREATE OR REPLACE TABLE a_motor_severity_bands AS
SELECT claim_size_band, COUNT(*) AS claims, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS claims_pct,
       ROUND(SUM(claim_amount), 2) AS claim_amount,
       ROUND(100.0 * SUM(claim_amount) / SUM(SUM(claim_amount)) OVER (), 2) AS amount_pct
FROM fact_motor_claim GROUP BY claim_size_band;
