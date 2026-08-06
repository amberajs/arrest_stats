data_validation.md 

## VisiData Analysis

data source: local county jail api
table name: pop_snap
columns: 8, rows: 888

No Issue:
- column types

Issue: days_left is "null" for every row
- fixed date parsing in the process json rpc
- matched source data key name "expectedRelease"

Potential Issue: 83% of inmates do not have a days_left because expectedRelease is null
- could make this a binary variable- do they have release date assigned yet or not?

Potential Issue: large standard deviation in days_left and days_served
- sort these values into bins?