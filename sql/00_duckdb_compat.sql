-- 00_duckdb_compat.sql  (DuckDB ONLY - do NOT run on Databricks)
-- Spark / Databricks SQL function shims so that 02-05 can be written in Spark SQL dialect
-- and still execute unchanged on DuckDB. On Databricks these functions are built in.
CREATE OR REPLACE MACRO unix_timestamp(ts) AS CAST(epoch(CAST(ts AS TIMESTAMP)) AS BIGINT);
CREATE OR REPLACE MACRO datediff(end_d, start_d) AS date_diff('day', CAST(start_d AS DATE), CAST(end_d AS DATE));
CREATE OR REPLACE MACRO percentile_approx(x, p) AS quantile_cont(x, p);
CREATE OR REPLACE MACRO dayofweek(d) AS (isodow(CAST(d AS DATE)) % 7) + 1;
