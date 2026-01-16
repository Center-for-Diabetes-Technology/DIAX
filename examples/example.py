import sys
import os
import numpy as np
import matplotlib.pyplot as plt

# Add parent directory to path to import utils module
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from utils.python.DIAX import DIAX

# Load data from JSON file
print("Loading data from example.json...")
subj = DIAX('examples/example.json')

# Display basic info
print(f"\nSubject: {subj.name}")
print(f"Duration: {subj.duration_in_days:.2f} days")
print(f"Number of data points: {len(subj.data)}")

# Show data structure
print(f"\nData columns: {list(subj.data.columns)}")
print(f"\nFirst few rows:")
print(subj.data.head())

# Calculate summary metrics
print("\nCalculating metrics...")
metrics = subj.get_summary_metrics()
print("\nSummary Metrics:")
print(metrics.T)  # Transpose for better readability

# Create a simple plot using the new plot() method
print("\nCreating plot...")

# Option 1: Use plot() without parameters (uses loaded data automatically)
fig = subj.plot()  # Automatically detects single subject and plots individual

# Option 2: Or explicitly provide results
# results = [{
#     'id': subj.id,
#     'name': subj.name,
#     'data': subj.data,
#     'durationInDays': subj.duration_in_days
# }]
# fig = subj.plot(results)  # Also automatically detects single subject

# Option 3: Force individual or group mode
# fig = subj.plot(mode='individual')  # Force individual plot
# fig = subj.plot(mode='group')       # Force group plot (even for single subject)

output_file = 'examples/example_plot.png'
subj.save_fig(fig, output_file.replace('.png', ''))
print(f"Plot saved to {output_file}")

print("\nDone!")