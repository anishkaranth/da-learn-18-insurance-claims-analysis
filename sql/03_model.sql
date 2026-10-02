-- 03_model.sql  Star schemas (Spark SQL dialect)
--   Medical : fact_medical_member (grain: one insured person) -> dim_med_region, dim_bmi_category
--   Motor   : fact_motor_policy (grain: one policy-year) and fact_motor_claim (grain: one claim)
--             -> dim_area, dim_fr_region, dim_vehicle, dim_driver_age_band
-- Surrogate keys are dense INT ranks for Power BI / Lakeview joins.

CREATE OR REPLACE TABLE dim_med_region AS
SELECT CAST(ROW_NUMBER() OVER (ORDER BY region) AS INT) AS med_region_key, region AS region_name
FROM (SELECT DISTINCT region FROM cln_medical) r;

CREATE OR REPLACE TABLE dim_bmi_category AS
SELECT CAST(ROW_NUMBER() OVER (ORDER BY bmi_category) AS INT) AS bmi_key, bmi_category,
       CASE WHEN bmi_category LIKE '1%' THEN '< 18.5' WHEN bmi_category LIKE '2%' THEN '18.5 - 24.9'
            WHEN bmi_category LIKE '3%' THEN '25 - 29.9' ELSE '>= 30' END AS bmi_range
FROM (SELECT DISTINCT bmi_category FROM cln_medical) b;

CREATE OR REPLACE TABLE fact_medical_member AS
SELECT m.member_id, r.med_region_key, b.bmi_key,
       m.age, m.age_band, m.sex, m.bmi, m.obese_flag, m.children, m.children_band,
       m.smoker_flag, m.smoker_status, m.charges, m.is_charges_outlier_iqr15, m.is_charges_top1pct
FROM cln_medical m
JOIN dim_med_region r ON m.region = r.region_name
JOIN dim_bmi_category b ON m.bmi_category = b.bmi_category;

CREATE OR REPLACE TABLE dim_area AS
SELECT CAST(ROW_NUMBER() OVER (ORDER BY area_code) AS INT) AS area_key, area_code,
       CAST(MIN(density) AS INT) AS min_density, CAST(MAX(density) AS INT) AS max_density,
       CAST(percentile_approx(CAST(density AS DOUBLE), 0.5) AS INT) AS median_density
FROM cln_motor_policy GROUP BY area_code;

CREATE OR REPLACE TABLE dim_fr_region AS
SELECT CAST(ROW_NUMBER() OVER (ORDER BY region_code) AS INT) AS fr_region_key, region_code
FROM (SELECT DISTINCT region_code FROM cln_motor_policy) r;

CREATE OR REPLACE TABLE dim_vehicle AS
SELECT CAST(ROW_NUMBER() OVER (ORDER BY veh_brand, veh_gas, veh_power) AS INT) AS vehicle_key,
       veh_brand, veh_gas, veh_power
FROM (SELECT DISTINCT veh_brand, veh_gas, veh_power FROM cln_motor_policy) v;

CREATE OR REPLACE TABLE dim_driver_age_band AS
SELECT CAST(ROW_NUMBER() OVER (ORDER BY driver_age_band) AS INT) AS driver_age_key, driver_age_band,
       MIN(driv_age) AS min_age, MAX(driv_age) AS max_age
FROM cln_motor_policy GROUP BY driver_age_band;

CREATE OR REPLACE TABLE fact_motor_policy AS
SELECT p.policy_id, a.area_key, g.fr_region_key, v.vehicle_key, d.driver_age_key,
       p.claim_nb, p.claim_nb_raw, p.exposure, p.exposure_raw, p.has_claim,
       p.driv_age, p.veh_age, p.vehicle_age_band, p.bonus_malus, p.bonus_malus_band, p.density,
       COALESCE(c.claims_with_amount, 0) AS claims_with_amount,
       COALESCE(c.claim_amount_total, 0) AS claim_amount_total,
       p.is_claim_nb_capped, p.is_exposure_capped, p.is_veh_age_outlier, p.is_driv_age_outlier
FROM cln_motor_policy p
JOIN dim_area a ON p.area_code = a.area_code
JOIN dim_fr_region g ON p.region_code = g.region_code
JOIN dim_vehicle v ON p.veh_brand = v.veh_brand AND p.veh_gas = v.veh_gas AND p.veh_power = v.veh_power
JOIN dim_driver_age_band d ON p.driver_age_band = d.driver_age_band
LEFT JOIN (SELECT policy_id, COUNT(*) AS claims_with_amount, ROUND(SUM(claim_amount), 2) AS claim_amount_total
           FROM cln_motor_claim GROUP BY policy_id) c ON p.policy_id = c.policy_id;

CREATE OR REPLACE TABLE fact_motor_claim AS
SELECT c.claim_id, c.policy_id, f.area_key, f.fr_region_key, f.vehicle_key, f.driver_age_key,
       c.claim_amount, c.claim_size_band, c.is_large_loss
FROM cln_motor_claim c
JOIN fact_motor_policy f ON c.policy_id = f.policy_id;
