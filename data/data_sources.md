# Demographic Baseline & Comparison Matrix

Sources for mutually exclusive demographic populations to match race classifications in the county jail that was studied (`White`, `Black`, `Hispanic`, `Other/Unknown`).

---

## General Population Baselines

**Source:** U.S. Census Bureau, *American Community Survey (ACS)* 1-Year Estimates, Table `B03002` (*Hispanic or Latino Origin by Race*), 2024.
**Access Date:** August 7, 2026.

### Category Mapping Logic
* **White:** Line 3 (`Not Hispanic or Latino: White alone`)
* **Black:** Line 4 (`Not Hispanic or Latino: Black or African American alone`)
* **Hispanic:** Line 12 (`Hispanic or Latino of any race`)
* **Other / Unknown:** Sum of Lines 5, 6, 7, and 8
  $$\text{Other/Unknown} = \text{Line 5 (AIAN)} + \text{Line 6 (Asian)} + \text{Line 7 (NHPI)} + \text{Line 8 (Some Other / Two+ Races)}$$

### Data Breakdown

| Geographic Scope | Category | Line Item | Raw Count | Calculated % |
| :--- | :--- | :--- | :--- | :--- |
| **United States**<br>*(Total Base: 334,922,499)* | White | Line 3 | 192,214,378 | **57.39%** |
| | Black | Line 4 | 39,896,127 | **11.91%** |
| | Hispanic | Line 12 | 64,759,370 | **19.34%** |
| | Other / Unknown | Lines 5, 6, 7, 8 | 23,812,622 | **7.11%** |
| **Kentucky**<br>*(Total Base: 4,534,824)* | White | Line 3 | 3,698,087 | **81.55%** |
| | Black | Line 4 | 342,570 | **7.55%** |
| | Hispanic | Line 12 | 226,744 | **5.00%** |
| | Other / Unknown | Lines 5, 6, 7, 8 | 92,737 | **2.05%** |
| **Fayette County, KY**<br>*(Total Base: 323,725)* | White | Line 3 | 216,082 | **66.75%** |
| | Black | Line 4 | 46,573 | **14.39%** |
| | Hispanic | Line 12 | 30,824 | **9.52%** |
| | Other / Unknown | Lines 5, 6, 7, 8 | 15,121 | **4.67%** |

---

## Incarcerated Population Benchmarks

### National Incarcerated Population
* **Source:** Bureau of Justice Statistics (BJS), *Correctional Populations in the United States, 2023*, Table 7.
* **Access Date:** August 7, 2026.
* **URL:** `https://bjs.ojp.gov/document/cpus23st.pdf`

$$\text{Implied Category \%} = \left(\frac{\text{Group Rate}}{\text{Total Combined Rate (3,900)}}\right) \times 100$$

| Category | Incarceration Rate (per 100k US Residents) | Implied Distribution % |
| :--- | :--- | :--- |
| **White** | 420 | **10.77%** |
| **Black** | 1,940 | **49.74%** |
| **Hispanic** | 800 | **20.51%** |
| **Other / Unknown** | 740 | **18.97%** |
| **Total Combined Rate Base** | **3,900** | **100.00%** |

### Kentucky State Incarcerated Population
* **Source:** Kentucky Department of Corrections (KY DOC), *2025 Annual Report*, Page 4.
* **Access Date:** August 7, 2026.
* **URL:** `https://corrections.ky.gov/public-information/researchandstats/Documents/Annual%20Reports/DOC%202025%20Annual%20Report%20-%20Final.pdf`

| Category | KY DOC Reported Percentage |
| :--- | :--- |
| **White** | **74.00%** |
| **Black** | **22.00%** |
| **Hispanic** | **2.00%** |
| **Other / Unknown** | **2.00%** |
| **Total Base** | **100.00%** |

---

## Comparison Matrix

| Demographic Group | USA Pop. % (Census) | KY Pop. % (Census) | Fayette Co. Pop. % (Census) | BJS National Incarcerated % | KY DOC Incarcerated % | Fayette Jail Snapshot % |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **White** | 57.39% | 81.55% | 66.75% | 10.77% | 74.00% | Calculated from Snapshot |
| **Black** | 11.91% | 7.55% | 14.39% | 49.74% | 22.00% | Calculated from Snapshot |
| **Hispanic** | 19.34% | 5.00% | 9.52% | 20.51% | 2.00% | Calculated from Snapshot |
| **Other / Unknown** | 7.11% | 2.05% | 4.67% | 18.97% | 2.00% | Calculated from Snapshot |
