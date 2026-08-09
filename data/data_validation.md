data_validation.md

## Data Validation Methods
- used VisiData to check actual column values and observe data range and frequency distribution


## Data Validation Findings

Data Source: local county jail current population api at a single point in time
Table Name: pop_snap
Columns: 8, Rows: 888

Expected Columns:
- age: range 18 and up
- sex: M, F
- race: BLACK, WHITE, HISPANIC, ASIAN, OTHER, UNKNOWN
- bmi_lookup: 1, 2, 3, 4, null
- days_served_bins: 2, 7, 30, 180, 365, YEAR_PLUS
- days_served: range 1 and up
- days_left: range 0 and up, null

Actual Columns:
- age: range(18,74)
- sex: M, F
- race: BLACK, WHITE, HISPANIC, OTHER, UNKNOWN
- bmi_lookup: 1, 2, 3, 4, null
- days_served_bins: 2, 7, 30, 180, 365, YEAR_PLUS
- days_served: range(1,2421)
- days_left: range(0,590), null


## Data Issues Repaired/Addressed:

### 2026-08-05
- days_left is "null" for every row (repaired)
- fixed date parsing in the process json rpc
- matched source data key name "expectedRelease"
- 83% of inmates have null days_left (after repair)
- high number of nulls was expected due to inmates awaiting trial and known system quirks
- data distribution can be analyzed as a binary (null or not null) and as a range of values

### 2026-08-06
- days_served has a high standard deviation (237 days) and noticable discrepancy between median and mean (167 vs 72)
- create bins for days_served values: 2 (2 or less), 7 (3-7), 30 (8-30), 180 (31-180), 365 (181-365), year_plus (366+)
- left numeric days_served to allow regression analysis with days_left (both measured in days)

(in progress) issues with data
- only one person in the 6 months to 1 year served bin, at exactly 365 days
- days served bins are listed in order by first digit instead of by amount of time represented (1yr is listed before 7days)
- all bmi is showing up as unrecorded