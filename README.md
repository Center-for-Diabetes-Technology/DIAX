# Standard Diabetes Time Series Data Format

This repository defines a **standard JSON format for diabetes-related time series data**, covering Continuous Glucose Monitoring (CGM), insulin delivery, carbohydrate intake, and other key events. The format is designed for:

- Interoperability across datasets and tools
- Transparent and reproducible data processing
- Flexibility in sampling rates and data completeness

---

## Goals

- **Unified Data Model:** Store diverse time series in a single, consistent structure.
- **Reproducibility:** Enable transparent conversion scripts from raw datasets.
- **Extensibility:** Allow additional variables (e.g., heart rate) without requiring all datasets to contain them.
- **Simplicity:** Use JSON for readability and ease of parsing.

---

## Format Overview

Each dataset is a collection of JSON files.
One JSON file per-subject, where the name is related to the subject ID.
e.g `subj_MyTrial_001-001.json` for subject 001-001 of MyTrial.

Each JSON file is structured in the same way:

- **Top-level keys**: Representing different data types (e.g., `cgm`, `bolus`, `carbs`, `basal_rate`).
- For each key:
  - `time`: List of datetimes
  - `value`: Corresponding measurements
- **Metadata**: Descriptions, units, device info, and other relevant context

This design avoids imposing a fixed sample frequency or requiring time alignment across keys.

---

## Time Representation

- Timestamps in `time` arrays are ISO 8601 format: Y-m-d H-M-S if timezone is unknown, and Y-m-d H-M-S Z if timezone is known
- (Preferred) example: `2025-09-27 14:02:20 -0400` with timezone information (EDT in this case)
- For example: `2025-09-27 14:02:20` without timezone information


---

## Example File

A complete example can be viewed here:

[example.json](./example.json)

---

## Key Definitions

Below is a summary of standard keys and their meanings:

|     Key                |     Units                   |     Description                                                                                           |
|------------------------|-----------------------------|-----------------------------------------------------------------------------------------------------------|
|     unique_id          |                             |     Unique identifier for the subject                                                                     |
|     cgm                |     mg/dL                   |     CGM values                                                                                            |
|     basal_rate         |     U/h                     |     Basal insulin delivery rate           Assumed constant infusion at   provided rate between samples    |
|     bolus              |     U                       |     Insulin boluses (meal or correction)                                                                  |
|     basal_inj          |     U                       |     Basal injection (for MDI)            Assumed no basal insulin between   samples                       |
|     Optional Fields    |                             |                                                                                                           |
|     carbs              |     g                       |     Carbohydrate intake                                                                                   |
|     carb_category      |     String key based on type<br>‘HT’ – Hypo treatment<br>‘Less’ – less than   usual<br>‘Typical’ – standard   size<br>‘More’ – More than   usual<br>‘Ann’ – Simple   announcement         |     Announced type of meal                                                                                |
|     smbg               |     mg/dL                   |     Self-monitored blood glucose   measurements                                                           |
|     hba1c              |     %                       |     Measured HbA1c value                                                                                  |
|     heart_rate         |     bps                     |     Recorded heart-rate                                                                                   |
|     steps              |     steps per ten seconds   |     Recorded steps in a 10 second   interval                                                              |
|     height             |     cm                      |     Height of subject                                                                                     |
|     weight             |     kg                      |     Weight of subject                                                                                     |

Other keys may be added as needed.

### Metadata
There should be a metadata field with subfields matching the keys in data. 
Each subfield should contain `unit` and `description` for the individual data. 

While the units in each column _should_ be standardized, this helps ensure transparency in units.
Additionally, the description can inform how the data is collected: e.g. for meal data if the carbs are user estimated or by an expert. 

Additional subfields `device` and `insulin` can be added as applicable. 

---

## Repository Contents

- `example.json` – Example dataset in the standard format.
- `scripts/` – Conversion scripts for public datasets.
- `README.md` – Format documentation.

---

## Usage Workflow

1. **Download raw data** from the original source.
2. **Run a conversion script** to produce standardized JSON.
3. Use the standardized file for downstream analysis, visualization, or replay.

---

## Existing datasets
| Dataset Name | Number of subjects | Available keys                                                         | Source                                                       | Reference                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
|--------------|--------------------|------------------------------------------------------------------------|--------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| DCLP3        | 125                | cgm basal_rate bolus smbg height weight                                | jaeb.org - DCLP3 Public Dataset - Release 3 - 2022-08-04.zip | Brown, S. A., Kovatchev, B. P., Dan, R., Lum, J. W., Buckingham, B. A.,   Kudva, Y. C., Laffel, L. M., Levy, C. J., Pinsker, J. E., Wadwa, P. R., Eyal,   D., Doyle, F. J., Anderson, S. M., Mei, C. M., Vikash, D., Laya, E.,   Forlenza, G. P., Elvira, I., Lam, D. W., … Beck, R. W. (2019). Six-Month   Randomized, Multicenter Trial of Closed-Loop Control in Type 1 Diabetes. New England Journal of Medicine, 381(18), 1707–1717.   https://doi.org/10.1056/NEJMoa1907863             |
| DCLP5        | 100                | cgm basal_rate bolus smbg height weight                                | jaeb.org - DCLP5_Dataset_2022-01-20.zip                      | Breton, M. D., Kanapka, L. G., Beck, R. W., Laya, E., Forlenza, G. P.,   Eda, C., Melissa, S., Ruedy, K. J., Emily, J., Lori, C., Emma, E., Hsu, L.   J., Mary, O., Kollman, C. C., Dokken, B. B., Weinzimer, S. A., DeBoer, M. D.,   Buckingham, B. A., Daniel, C., & Paul, W. R. (2020). A Randomized Trial   of Closed-Loop Control in Children with Type 1 Diabetes. New   England Journal of Medicine, 383(9), 836–845.   https://doi.org/10.1056/NEJMoa2004736                          |
| PEDAP        | 99                 |  cgm basal_rate bolus smbg carbs   height weight                       | jaeb.org - PEDAP Public Dataset - Release 5 - 2025-05-12.zip | Wadwa, R. P., Reed, Z. W., Buckingham, B. A., DeBoer, M. D., Ekhlaspour,   L., Forlenza, G. P., Schoelwer, M., Lum, J., Kollman, C., Beck, R. W., &   Breton, M. D. (2023). Trial of Hybrid Closed-Loop Control in Young Children   with Type 1 Diabetes. New England Journal of Medicine, 388(11),   991–1001. https://doi.org/10.1056/nejmoa2210834                                                                                                                                         |
| T1DEXI       | 404                |  cgm basal_rate basal_inj bolus heart_rate   steps carbs height weight |                                                              | Riddell, M. C., Li, Z., Gal, R. L., Calhoun, P., Jacobs, P. G., Clements,   M. A., Martin, C. K., Doyle III, F. J., Patton, S. R., Castle, J. R.,   Gillingham, M. B., Beck, R. W., Rickels, M. R., & Group, T. S. (2023).   Examining the Acute Glycemic Effects of Different Types of Structured   Exercise Sessions in Type 1 Diabetes in a Real-World Setting: The Type 1   Diabetes and Exercise Initiative (T1DEXI). Diabetes Care, 46(4),   704–713. https://doi.org/10.2337/dc22-1721 |
| IOBP2        | 343                |  cgm basal_rate bolus smbg   carb_category height weight               | jaeb.org - IOBP2 RCT Public Dataset.zip                      | Bionic Pancreas Research Group. (2022). Multicenter, Randomized Trial of   a Bionic Pancreas in Type 1 Diabetes. New England Journal   of Medicine, 387(13), 1161–1172. https://doi.org/10.1056/NEJMoa2205225                                                                                                                                                                                                                                                                                 |

---

## Planned Extensions
- Integration with online data repositories.
- Reference implementations in Python and Matlab
- A publication describing the format in detail.
- JSON Schema for validation

---


## Contact

For questions, suggestions, or collaboration:

- **Maintainer:** Elliott Pryor
- **Email:** elliott.pryor@virginia.edu
