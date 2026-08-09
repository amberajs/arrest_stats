README

##ACTIVE DEVELOPMENT

*Arrest Stats is a work in progress. Recent work has focused on data validation.*

###Purpose
1) Create a defensible data pipeline that handles local arrest records through an entire ELT process.
2) Design an application for citizens to query up to date statistics regarding crime and policing in their city.
3) Observe demographic trends to identify potential, relevant areas of concern for government officials and policy makers.  

###Priorities
1) Security: proper authentication and row-level security policies 
2) Privacy: anonymization of records containing personal or identifiable information
3) Data Integrity: strict database definitions
4) Audit Trail: keeping untouched, raw json and hash value of each source 

```mermaid
(insert github repo file tree)
```

###Methods

Data Pipeline 1: Static Snapshot
EXTRACT
- other_scraper.py: scrape static snapshot of current jail population
LOAD
- database (supabase): see most recent timestamp migration snapshot.sql file
- raw_pop (stable): stores raw payload and hash value
TRANSFORM
- database trigger: automatically formats all raw json into snap_pop table

Data Pipeline 2: Dynamic Log
EXTRACT
- scraper.py: automatic hourly scraper to log new arrests
LOAD
- database (supabase): see most recent timestamp migration init.sql file
- raw_json table: stores raw payload and hash value
TRANSFORM
- database trigger: new row wakes up edge function
- format_data/index.ts (supabase edge function): formats raw_json using rpc database function
- rpc database function: atomically updates primary arrests table and lookup/profile tables


###Data Validation

VisiData
- confirm that data was properly loaded and transformed
- summarize findings
- check for unexpected data anomalies or outliers
- adjust data pipeline and re-process as needed

###Results Export and Delivery

-json_agg.sql: anonymized aggregator for static snapshot data
-in progress: anonymized aggregator for dynamic log data
-in progress: dashboard for summarized statistics (github pages and tableau)

