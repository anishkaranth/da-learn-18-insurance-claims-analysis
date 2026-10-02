-- 01_staging.sql
-- Land the three raw CSVs as all-STRING staging tables (no type inference; casting happens in 02).
-- {{RAW_DIR}} is substituted by run_pipeline.py.
-- DuckDB : read_csv(path, header = true, all_varchar = true)
-- Databricks equivalent (used in databricks/insurance_pipeline_notebook.sql):
--   SELECT * FROM read_files('/Volumes/workspace/da_learn_18/raw/<file>.csv', format => 'csv',
--          header => true, inferColumnTypes => false)
CREATE OR REPLACE TABLE stg_medical AS
SELECT * FROM read_csv('{{RAW_DIR}}/insurance.csv', header = true, all_varchar = true);

CREATE OR REPLACE TABLE stg_motor_policy AS
SELECT * FROM read_csv('{{RAW_DIR}}/freMTPL2freq.csv', header = true, all_varchar = true);

CREATE OR REPLACE TABLE stg_motor_claim AS
SELECT * FROM read_csv('{{RAW_DIR}}/freMTPL2sev.csv', header = true, all_varchar = true);
