# Dashboard specification (3 pages)

Validate against full-data SQL (`results/metrics.json`): Members **1,337**, Avg charges **$13,279.12**, Smoker loading **3.80x**,
Policies **678,013**, Exposure **358,360.11** policy-years, Claim frequency **0.10061**, Avg severity **EUR 2,265.51**, Pure premium **EUR 167.18**.

## Page 1 - Medical cost drivers
* KPI cards: Members, Avg Charges, Median Charges, Smoker %, Smoker Loading x, Obese %
* Clustered column: Avg Charges by `fact_medical_member[age_band]`, legend `smoker_status`
* Clustered column: Avg Charges by `dim_bmi_category[bmi_category]`, legend `smoker_status`
* Bar: Avg Charges by `dim_med_region[region_name]` with tooltip Smoker %
* Scatter: `age` (X) vs `charges` (Y), legend `smoker_status`, size = `bmi` (shows the three charge bands)

## Page 2 - Motor claim frequency
* KPI cards: Policies, Exposure Years, Claims, Claim Frequency, Policies With Claim %
* Column: Claims per 100 Policy-Years by `dim_driver_age_band[driver_age_band]`
* Column: Claims per 100 Policy-Years by `fact_motor_policy[bonus_malus_band]`
* Column: Claims per 100 Policy-Years by `dim_area[area_code]` (tooltip `median_density`)
* Filled map / bar: Claim Frequency by `dim_fr_region[region_code]`

## Page 3 - Motor severity & pure premium
* KPI cards: Avg Severity, Median Severity, Pure Premium, Large Loss Share
* Combo: `claim_size_band` - columns Claim Records, line % of Claim Amount (shows tail concentration)
* Matrix: `dim_vehicle[veh_brand]` x `veh_gas` -> Claim Frequency, Policies
* Column: Pure Premium by `fact_motor_policy[vehicle_age_band]`
