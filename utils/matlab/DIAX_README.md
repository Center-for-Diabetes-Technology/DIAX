# DIAX MATLAB Class

## Overview
The DIAX (Diabetes Data Exchange Format) class is a MATLAB class for managing, analyzing, and visualizing diabetes data. It uses **timetable** data structures for all time series fields, providing efficient time-based data manipulation and analysis.

## Recent Changes (2025)

### Timetable Migration
- **Changed from matrix convention**: Previously, time series fields were stored as Nx2 matrices (column 1: datenum, column 2: value)
- **Now using timetable**: All time series fields are now MATLAB timetable objects with datetime row times
- Time series data accessed via `.time` (datetime) and `.value` (numeric) properties

### Variable Naming Updates
- **Carbohydrates**: `carb` → `carbs`, `carbActual` → `carbsActual`, `carbAnnounced` → `carbsAnnounced`
- **Carb metadata**: `carbCategory` → `carbsCategory`, `mealType` → `carbsType`
- **Timestamps**: `startTimestamp` → `startDate`, `endTimestamp` → `endDate`
- **Fields list**: `fields` → `timeSeriesFields`

## Data Structure

### Properties

#### Metadata
- `uid`: Unique subject identifier (string)
- `startDate`: Start datetime of data collection
- `endDate`: End datetime of data collection
- `durationInDays`: Duration of data collection in days

#### Time Series Fields (timetable objects)
All time series stored as timetable with `.time` (datetime) and `.value` (numeric):
- `cgm`: Continuous Glucose Monitor data (mg/dL)
- `smbg`: Self-Monitored Blood Glucose (mg/dL)
- `bolus`: Insulin bolus doses (U)
- `basalRate`: Basal insulin rate (U/hr)
- `basalInj`: Basal insulin injections (U)
- `carbs`: Total carbohydrate intake (g)
- `carbsActual`: Actual carbs consumed (g)
- `carbsAnnounced`: Announced/counted carbs (g)
- `carbsCategory`: Meal category codes (numeric)
- `carbsType`: Meal type codes (numeric)
- `treat`: Hypoglycemia treatment carbs (g)

#### Internal Properties
- `timeSeriesFields`: Cell array of time series field names
- `snakeCaseMap`: Containers.Map for JSON field name conversion (lowerCamelCase ↔ snake_case)

## Key Methods

### Construction and I/O
- `DIAX()`: Constructor, creates empty DIAX object
- `fromJSON(filename)`: Static method to load DIAX from JSON file
- `toJSON(filename, options)`: Export DIAX object to JSON file
  - Options: `'addMetadata', true/false` - include metadata in JSON

### Data Access and Manipulation
- `getSampledData(field, period, options)`: Resample time series to regular grid
  - `period`: Sampling period (duration or numeric minutes)
  - Options: `'aggregate', @mean/@sum/@max/@min` - aggregation function
- `getDay(dayNumber)`: Extract data for specific day(s)
  - Returns new DIAX object with subset of data

### Visualization
- `plot()`: Create comprehensive multi-panel plot of all data
- `plotAGP()`: Create Ambulatory Glucose Profile visualization
- `plotCompare(diaxArray, options)`: Compare multiple subjects
  - Options: `'saveFigure', filename` - save comparison plot
- `plotData()`: Plot individual time series data
- `plotOutcomes()`: Plot glucose outcomes and metrics
- `plotSummary()`: Summary plot with key metrics
- `plotWeekly()`: Weekly pattern visualization

### Analysis
- `computeOutcomes()`: Calculate glucose metrics (TIR, TBR, TAR, CV, etc.)
- `generateSummary()`: Generate comprehensive summary statistics
- `compareMetrics(other)`: Compare metrics with another DIAX object
- `compareAGP(other)`: Compare AGP patterns with another DIAX object

## Usage Examples

### Basic Usage
```matlab
% Create from JSON
diax = DIAX.fromJSON('example_patient_001.json');

% Access time series data (timetable)
cgmData = diax.cgm;
cgmTimes = cgmData.time;      % datetime array
cgmValues = cgmData.value;    % numeric array

% Get metadata
fprintf('Subject: %s\n', diax.uid);
fprintf('Duration: %.1f days\n', diax.durationInDays);
fprintf('Start: %s\n', diax.startDate);
fprintf('End: %s\n', diax.endDate);
```

### Data Manipulation
```matlab
% Resample CGM to 5-minute intervals
cgm5min = diax.getSampledData('cgm', minutes(5));

% Get data for specific day
day1 = diax.getDay(1);      % First day
day2to4 = diax.getDay(2:4); % Days 2-4

% Access resampled data
times = cgm5min(:,1);  % datenum format
values = cgm5min(:,2); % numeric values
```

### Analysis
```matlab
% Compute glucose metrics
outcomes = diax.computeOutcomes();
fprintf('TIR: %.1f%%\n', outcomes.tir);
fprintf('Mean glucose: %.1f mg/dL\n', outcomes.mean);
fprintf('CV: %.1f%%\n', outcomes.cv);

% Generate comprehensive summary
summary = diax.generateSummary();
```

### Visualization
```matlab
% Create comprehensive plot
figure;
diax.plot();

% Create AGP visualization
figure;
diax.plotAGP();

% Compare multiple subjects
diaxArray = [diax1, diax2, diax3];
DIAX.plotCompare(diaxArray, 'saveFigure', 'comparison.png');
```

### Export to JSON
```matlab
% Export with metadata
diax.toJSON('output.json', 'addMetadata', true);

% Export without metadata
diax.toJSON('output_minimal.json', 'addMetadata', false);
```

## JSON Format

The DIAX JSON format uses snake_case field names:
```json
{
  "unique_id": "subject_id",
  "start_date": "2025-01-25T12:00:00-05:00",
  "end_date": "2025-01-26T12:00:00-05:00",
  "duration_in_days": 1.0,
  "cgm": {
    "time": ["2025-01-25T12:00:00-05:00", ...],
    "value": [100, 102, 105, ...]
  },
  "bolus": {
    "time": ["2025-01-25T12:08:32-05:00", ...],
    "value": [3.5, 2.02, ...]
  },
  "basal_rate": {
    "time": [...],
    "value": [...]
  },
  "carbs": {
    "time": [...],
    "value": [...]
  }
}
```

Field name mapping (MATLAB ↔ JSON):
- `cgm` ↔ `cgm`
- `smbg` ↔ `smbg`
- `bolus` ↔ `bolus`
- `basalRate` ↔ `basal_rate`
- `basalInj` ↔ `basal_inj`
- `carbs` ↔ `carbs`
- `carbsActual` ↔ `carbs_actual`
- `carbsAnnounced` ↔ `carbs_announced`
- `carbsCategory` ↔ `carbs_category`
- `carbsType` ↔ `carbs_type`
- `treat` ↔ `treat`

## Implementation Notes

### Timetable Architecture
- All time series use `timetable` with `datetime` row times
- Access time: `obj.cgm.time` (returns datetime array)
- Access values: `obj.cgm.value` (returns numeric array)
- Regular time grid: Use `retime()` for resampling
- Duration arithmetic: Use MATLAB duration objects

### Date Handling
- Internal times are `datetime` objects with timezone awareness
- `datenum()` conversion used for arithmetic when needed
- JSON export uses ISO 8601 format with timezone

### Field Management
- `timeSeriesFields` property lists all time series field names
- Iterate over fields: `for i = 1:numel(obj.timeSeriesFields)`
- Check field existence: `~isempty(obj.cgm)`

### Performance
- Timetables provide optimized time-based indexing
- Use `retime()` for efficient resampling
- `getSampledData()` handles missing data and aggregation

## Compatibility

- **MATLAB Version**: R2025a or later (requires timetable support)
- **Dependencies**: None (uses built-in MATLAB functions)
- **Python Interoperability**: JSON format compatible with Python DIAX class (see `utils/python/DIAX_README.md`)
