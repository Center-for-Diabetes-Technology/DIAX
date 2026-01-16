# DIAX Python Class

## Overview
The DIAX class has been transformed from the UVAT1DSimulator class to focus on visualization and analysis of diabetes data from JSON files, removing all simulator execution functionality.

### Features

#### Initialization
```python
# Initialize with JSON file
diax = DIAX('path/to/data.json')

# Or load later
diax = DIAX()
diax.load_json('path/to/data.json')
```

#### JSON Format Expected
```json
{
  "unique_id": "subject_id",
  "cgm": {"time": [...], "value": [...]},
  "bolus": {"time": [...], "value": [...]},
  "basal_rate": {"time": [...], "value": [...]},
  "carbs": {"time": [...], "value": [...]},
  "treat": {"time": [...], "value": [...]}
}
```

The JSON format matches the MATLAB DIAX `toJSON()` export format, with automatic field mapping:
- `carbs` → `meal`
- `carbs_announced` → `carbCounted`
- `basal_inj` → `basal_dose`
- `carbs_category` → `mealCategory`
- `carbs_type` → `mealType`

### Retained Features

#### Plotting Methods
- `plot(results=None, mode='auto', title='Summary')`: **Main plotting method** - automatically chooses individual or group plotting
  - `mode='auto'`: Plot individual if single subject, group if multiple (default)
  - `mode='individual'`: Force individual plot(s)
  - `mode='group'`: Force group/summary plot
  - If `results=None`, uses `self.data`
- `plot_individual_results(results)`: Plot individual subject data with CGM trace, insulin, meals, and metrics table
- `plot_group_results(results, title='Summary')`: Plot population aggregates with percentile bands (AGP-style)
- `save_fig(f, filename)`: Static method to save figures

#### Metrics Methods
- `get_summary_metrics(results=None)`: Calculate diabetes metrics (TIR, TBR, TAR, GMI, CV, insulin totals, etc.)
  - If `results=None`, uses `self.data`
  - Returns pandas DataFrame with metrics for each subject
- `lbgi(cgm)`: Low Blood Glucose Index
- `hbgi(cgm)`: High Blood Glucose Index
- `rl_score(cgm, thresholds=None, hypo_hyper_ratio=2.0, max_score=10.0)`: Risk Level score

## Usage Example

```python
import matplotlib.pyplot as plt
from DIAX import DIAX

# Load data from JSON
diax = DIAX('example_patient_001.json')

# Calculate metrics for this subject
metrics = diax.get_summary_metrics()
print(metrics)

# Simple plotting - uses loaded data automatically
fig = diax.plot()  # Automatically detects single subject, plots individual
plt.show()

# Or force a specific plot type
fig = diax.plot(mode='individual')  # Force individual plot
fig = diax.plot(mode='group')       # Force group plot (even for single subject)

# For multiple subjects, load data into a list
results = []
for json_file in ['patient1.json', 'patient2.json', 'patient3.json']:
    d = DIAX(json_file)
    results.append({
        'id': d.id,
        'name': d.name,
        'data': d.data,
        'durationInDays': d.duration_in_days
    })

# Automatically creates group plot for multiple subjects
fig = diax.plot(results)  # mode='auto' detects multiple subjects
plt.show()

# Or explicitly call individual/group methods
# fig = diax.plot_individual_results(results[0])  # Single subject
# fig = diax.plot_group_results(results, title='Population Summary')  # Multiple subjects
```

## Data Structure

After loading JSON, the DIAX object contains:
- `self.data`: pandas DataFrame with columns:
  - `time`: Days from start (float)
  - `cgm`: Continuous Glucose Monitor values (mg/dL)
  - `bolus`: Insulin bolus doses (U)
  - `basal_rate`: Basal insulin rate (U/hr)
  - `meal`: Carbohydrate intake (g)
  - `treat`: Hypoglycemia treatment (g)
  - Plus other optional fields (carbCounted, mealCategory, mealType, etc.)
- `self.name`: Subject identifier (from JSON `uid` or `subject_id`)
- `self.id`: Subject ID
- `self.duration_in_days`: Duration of data in days

## Notes

- The class uses matplotlib with AGG backend for non-interactive plotting
- Multiprocessing is used for batch plotting (when plotting >10 subjects)
- Time series data is converted to days from start for consistent plotting
- Missing CGM values are stored as NaN, missing event data (bolus, meals) as 0.0
