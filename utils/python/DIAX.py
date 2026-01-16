import json
import logging
import multiprocessing
import os
from datetime import datetime

import matplotlib
matplotlib.use('AGG')

import matplotlib.pyplot as plt
plt.style.use('default')

import numpy as np
import pandas as pd

logger = logging.getLogger("DIAX")
if os.environ.get('NUMBER_OF_PROCESSORS'):
    cpu_count = int(os.environ['NUMBER_OF_PROCESSORS'])
elif os.environ.get('SLURM_CPUS_PER_TASK'):
    cpu_count = int(os.environ['SLURM_CPUS_PER_TASK'])
else:
    cpu_count = multiprocessing.cpu_count()


class DIAX:
    """
    DIAX: Diabetes Data Exchange Format
    
    A class for loading, analyzing, and visualizing diabetes data from JSON files.
    """
    MINUTES_IN_DAY = 1440.0

    def __init__(self, json_file=None, plot_in_one_axis=True):
        """
        Initialize DIAX object from a JSON file.
        
        Args:
            json_file: Path to JSON file containing diabetes data
            plot_in_one_axis: Whether to plot all data in one axis (True) or separate axes (False)
        """
        self.plot_in_one_axis = plot_in_one_axis
        self.data = None
        self.name = None
        self.id = None
        self.duration_in_days = None
        
        if json_file is not None:
            self.load_json(json_file)
    
    def load_json(self, json_file):
        """
        Load diabetes data from JSON file.
        
        Expected JSON format:
        {
            "unique_id": "subject_id",
            "cgm": {"time": [...], "value": [...]},
            "bolus": {"time": [...], "value": [...]},
            "basal_rate": {"time": [...], "value": [...]},
            "carbs": {"time": [...], "value": [...]},
            "treat": {"time": [...], "value": [...]}
        }
        """
        with open(json_file, 'r') as f:
            json_data = json.load(f)
        
        # Extract metadata
        self.name = json_data.get('unique_id', json_data.get('subject_id', 'unknown'))
        self.id = json_data.get('id', self.name)
        
        # Convert JSON data to pandas DataFrame
        data_dict = {'time': []}
        
        # Map JSON field names to internal names
        field_mapping = {
            'cgm': 'cgm',
            'bg': 'bg', 
            'smbg': 'smbg',
            'bolus': 'bolus',
            'basal_rate': 'basal_rate',
            'basal_inj': 'basal_dose',
            'carbs': 'meal',
            'carbs_announced': 'carbCounted',
            'carbs_actual': 'meal',
            'treat': 'treat',
            'carbs_category': 'mealCategory',
            'carbs_type': 'mealType'
        }
        
        # Find all time points
        all_times = []
        for json_field in field_mapping.keys():
            if json_field in json_data and json_data[json_field] is not None:
                if 'time' in json_data[json_field]:
                    times = json_data[json_field]['time']
                    if isinstance(times, list):
                        # Convert string times to pandas datetime
                        all_times.extend([pd.to_datetime(t) for t in times])
        
        if not all_times:
            raise ValueError("No time series data found in JSON file")
        
        # Create regular time grid
        all_times = sorted(set(all_times))
        start_time = all_times[0]
        end_time = all_times[-1]
        
        # Calculate duration in days
        self.duration_in_days = (end_time - start_time).total_seconds() / (60 * 60 * 24)
        
        # Create time array in days from start
        time_array = [(t - start_time).total_seconds() / (60 * 60 * 24) for t in all_times]
        data_dict['time'] = time_array
        
        # Extract each field
        for json_field, internal_field in field_mapping.items():
            if json_field in json_data and json_data[json_field] is not None:
                if 'time' in json_data[json_field] and 'value' in json_data[json_field]:
                    times = [pd.to_datetime(t) for t in json_data[json_field]['time']]
                    values = json_data[json_field]['value']
                    
                    # Create a mapping from time to value
                    time_value_map = dict(zip(times, values))
                    
                    # Map values to our regular grid
                    field_values = [time_value_map.get(t, 0.0 if internal_field not in ['cgm', 'bg', 'smbg'] else np.nan) 
                                   for t in all_times]
                    data_dict[internal_field] = field_values
        
        # Create DataFrame
        self.data = pd.DataFrame(data_dict)
        
        logger.info(f"Loaded data for {self.name}: {self.duration_in_days:.1f} days, {len(self.data)} time points")
        
        return self
    
    def get_summary_metrics(self, results=None):
        """
        Calculate summary metrics for diabetes data.
        
        Args:
            results: List of result dictionaries or None (uses self.data if None)
        
        Returns:
            pandas DataFrame with summary metrics for each subject
        """
        # If no results provided, use self.data
        if results is None:
            if self.data is None:
                raise ValueError("No data loaded. Call load_json() first or provide results parameter.")
            results = [{
                'id': self.id,
                'name': self.name,
                'data': self.data,
                'durationInDays': self.duration_in_days
            }]
        
        if not isinstance(results, list):  # if it is a single sample
            results = [results]
        out = {
            'Dur (days)': [],
            'TBR2 (%)': [],
            'TBR1 (%)': [],
            'TIR (%)': [],
            'TAR1 (%)': [],
            'TAR2 (%)': [],
            'GMI (%)': [],
            'Mean (mg/dL)': [],
            'SD (mg/dL)': [],
            'CV (%)': [],
            'Insulin (U)': [],
            'Basal (U)': [],
            'Bolus (U)': [],
            'Meal (g)': [],
            'Counted (g)': [],
            'Treat (g)': [],
            'Hypos (#)': [],
            'LBGI': [],
            'HBGI': [],
        }
        row_names = []
        for res in results:
            if 'id' not in res or 'data' not in res:
                continue

            row_names.append(res['id'])
            data = res['data']

            out['Dur (days)'].append(np.max(data['time']))
            if 'cgm' in data:
                out['TIR (%)'].append(100.0 * np.mean(np.logical_and(data['cgm'] >= 70.0, data['cgm'] <= 180.0)))
                out['TBR1 (%)'].append(100.0 * np.mean(data['cgm'] < 70.0))
                out['TAR1 (%)'].append(100.0 * np.mean(data['cgm'] > 180.0))
                out['TBR2 (%)'].append(100.0 * np.mean(data['cgm'] < 54.0))
                out['TAR2 (%)'].append(100.0 * np.mean(data['cgm'] > 250.0))
                out['GMI (%)'].append(3.31 + 0.02392 * np.mean(data['cgm']))
                out['Mean (mg/dL)'].append(np.mean(data['cgm']))
                out['SD (mg/dL)'].append(np.std(data['cgm']))
                out['CV (%)'].append(100.0 * np.std(data['cgm']) / np.mean(data['cgm']))
                out['LBGI'].append(self.lbgi(data['cgm']))
                out['HBGI'].append(self.hbgi(data['cgm']))
            else:
                out['TIR (%)'].append(0.0)
                out['TBR1 (%)'].append(100.0)
                out['TAR1 (%)'].append(100.0)
                out['TBR2 (%)'].append(100.0)
                out['TAR2 (%)'].append(100.0)
                out['GMI (%)'].append(float('inf'))
                out['Mean (mg/dL)'].append(float('inf'))
                out['SD (mg/dL)'].append(float('inf'))
                out['CV (%)'].append(float('inf'))
                out['LBGI'].append(float('inf'))
                out['HBGI'].append(float('inf'))

            if 'basal' in data:
                if res['units']['basal'] == 'u/hr':
                    out['Basal (U)'].append(np.mean(data['basal']) * 24)
                elif res['units']['basal'] == 'u' and 'time' in data and np.max(data['time']) > 0:
                    out['Basal (U)'].append(np.sum(data['basal']) / np.max(data['time']))
                else:
                    out['Basal (U)'].append(0)
            elif 'basal_dose' in data and 'time' in data and np.max(data['time']) > 0:
                out['Basal (U)'].append(np.sum(data['basal_dose']) / np.max(data['time']))
            elif 'basal_rate' in data:
                out['Basal (U)'].append(np.mean(data['basal_rate']) * 24)
            else:
                out['Basal (U)'].append(0)

            if 'bolus' in data and 'time' in data and np.max(data['time']) > 0:
                out['Bolus (U)'].append(np.sum(data['bolus']) / np.max(data['time']))
            else:
                out['Bolus (U)'].append(0)

            out['Insulin (U)'].append(out['Basal (U)'][-1] + out['Bolus (U)'][-1])

            if 'meal' in data and 'time' in data and np.max(data['time']) > 0:
                out['Meal (g)'].append(np.sum(data['meal']) / np.max(data['time']))
            else:
                out['Meal (g)'].append(0)

            if 'treat' in data and 'time' in data and np.max(data['time']) > 0:
                out['Treat (g)'].append(np.sum(data['treat']) / np.max(data['time']))
                out['Hypos (#)'].append(np.sum(data['treat'] > 0) / np.max(data['time']))
            else:
                out['Treat (g)'].append(0)
                out['Hypos (#)'].append(0)

            if 'carbCounted' in data and 'time' in data and np.max(data['time']) > 0:
                out['Counted (g)'].append(np.sum(data['carbCounted']) / np.max(data['time']))
            else:
                out['Counted (g)'].append(0)

        df = pd.DataFrame(out)
        df.index = row_names

        return df

    def convert_to_new(self, results_old):
        results = []
        for i in range(len(results_old)):
            res = results_old[i]
            ptID = res['id']
            time = []
            cgm = []
            basal = []
            bolus = []
            treat = []
            meal = []

            units = {
                'cgm': 'mg/dL',
                'time': 'min',
                'bolus': 'u',
                'meal': 'g',
                'treat': 'g'
            }

            if 'outputs' in res:
                time = res['outputs']['cgm {mgPerdl}'][:, 0]
                cgm = res['outputs']['cgm {mgPerdl}'][:, 1]

            if 'inputs' in res:
                r = res['inputs']

                if 'basal {unitsPerh}' in r:
                    basal = r['basal {unitsPerh}'][:, 1]
                    units['basal'] = 'u/hr'
                elif 'basal {units}' in r:
                    basal = r['basal {units}'][:, 1]
                    units['basal'] = 'u'
                else:
                    basal = np.zeros(len(time))
                    units['basal'] = 'u'

                if 'bolus {units}' in r:
                    bolus = r['bolus {units}'][:, 1]
                else:
                    bolus = np.zeros(len(time))

                if 'treat {g}' in r:
                    treat = r['treat {g}'][:, 1]
                else:
                    treat = np.zeros(len(time))

                if 'meal {g}' in r:
                    treat = r['meal {g}'][:, 1]
                else:
                    np.zeros(len(time))

            l = len(time)
            if len(basal) != l or len(bolus) != l or len(cgm) != l or len(treat) != l or len(meal) != l:
                raise Exception("Length of arrays is not consistent")

            log = []
            for i in range(l):
                r = {'cgm': cgm[i], 'time': time[i], 'bolus': bolus[i], 'basal': basal[i], 'treat': treat[i],
                     'meal': meal[i]}
                log.append(r)

            if log:
                results.append(
                    {
                        "id": ptID,
                        "data": pd.DataFrame.from_dict(log),
                        "durationInDays": int(max(time) / self.MINUTES_IN_DAY),
                        "units": units,
                    }
                )
            else:
                results.append({"id": ptID})

        return results

    def plot(self, results=None, mode='auto', title='Summary'):
        """
        Plot diabetes data - automatically chooses individual or group plotting.
        
        Args:
            results: List of result dictionaries, single result dict, or None (uses self.data if None)
            mode: 'auto' (default), 'individual', or 'group'
                - 'auto': Plot individual if single result, group if multiple
                - 'individual': Force individual plot(s)
                - 'group': Force group/summary plot
            title: Title for group plots (default: 'Summary')
        
        Returns:
            matplotlib figure or list of figures
        """
        # If no results provided, use self.data
        if results is None:
            if self.data is None:
                raise ValueError("No data loaded. Call load_json() first or provide results parameter.")
            results = [{
                'id': self.id,
                'name': self.name,
                'data': self.data,
                'durationInDays': self.duration_in_days
            }]
        
        # Normalize to list
        if not isinstance(results, list):
            results = [results]
        
        # Determine plotting mode
        if mode == 'auto':
            if len(results) == 1:
                mode = 'individual'
            else:
                mode = 'group'
        
        # Plot accordingly
        if mode == 'individual':
            if len(results) == 1:
                return self.plot_individual_results(results[0])
            else:
                return self.plot_individual_results(results)
        elif mode == 'group':
            return self.plot_group_results(results, title=title)
        else:
            raise ValueError(f"Invalid mode: {mode}. Use 'auto', 'individual', or 'group'.")
    
    @staticmethod
    def save_fig(f, filename):
        f.savefig(filename + '.png', dpi=100)
        plt.close(f)
        logger.info(f'Saved results in {filename}.')

    def plot_individual_results(self, results):
        if isinstance(results, list):
            if len(results) > 10:
                with multiprocessing.Pool(cpu_count - 1) as p:
                    return p.map(self.plot_individual_results, [res for res in results])
            return [self.plot_individual_results(res) for res in results]

        f = plt.figure(constrained_layout=True)
        f.set_size_inches(16, 9)
        results_df = results['data']
        duration_in_days = len(results_df["time"]) / 288.0
        name = results["id"]
        times = results_df['time']
        f.suptitle(f'Simulation of P{name} for {round(duration_in_days)} days', fontsize=16,
                   fontweight='bold')

        if self.plot_in_one_axis:
            ax = f.subplot_mosaic(
                """
                ps
                """,
                gridspec_kw={
                    "width_ratios": [12.0, 1.0],
                },
                sharex=True,
            )
            # plot outputs and inputs
            ax['p'].set_title('Outputs')
            ax['p'].set_yticks(np.arange(0, 500, step=20))
            ax['p'].set_ylim(0, 500)
            ax['p'].axhline(y=54, color='r', linestyle='--')
            ax['p'].axhline(y=300, color='r', linestyle='--')
            ax['p'].axhline(y=70, color='g', linestyle='--')
            ax['p'].axhline(y=180, color='g', linestyle='--')
            ax['p'].axhline(y=40, color='k', linestyle='--')
            ax['p'].axhline(y=400, color='k', linestyle='--')
            ax['p'].grid(visible=True, which='both', alpha=0.3)
            ax['p'].grid(linewidth=1.5, which='major', axis='x', color='k')

            # Set x ticks
            if duration_in_days < 7:
                scale = 1.0 / 24.0
                ax['p'].set_xlabel('time (hours)')
            elif duration_in_days < 4 * 7:
                scale = 1.0
                ax['p'].set_xlabel('time (days)')
            else:
                scale = 7.0
                ax['p'].set_xlabel('time (weeks)')

            ax['p'].set_xlim(0, duration_in_days)
            # Set major ticks
            ax['p'].set_xticks(np.arange(0, duration_in_days, step=scale),
                               labels=np.arange(0, duration_in_days / scale, step=1).astype(int))
            # Set minor ticks
            if scale == 1.0:
                ax['p'].set_xticks(np.arange(0, duration_in_days, step=1.0 / 6.0), minor=True)
            elif scale == 7.0:
                ax['p'].set_xticks(np.arange(0, duration_in_days, step=1.0), minor=True)

            # Plot cgm
            color = 'tab:red'
            marker = '.'
            ax['p'].plot(times, results_df['cgm'], color=color, marker=marker, linewidth=2,
                         label="cgm (mg/dL)")
            ax['p'].legend()

            # Plot inputs
            for idx, (key, value) in enumerate(results_df.items()):
                if 'mealCategoryIndex' in key:
                    continue
                elif 'mealCategory' in key:
                    color = 'tab:purple'
                    marker = '^'
                    position_marker = 460
                    position_text = 440
                    precision_text = -1
                    units = ''
                elif 'mealAnnounced' in key:
                    color = 'tab:purple'
                    marker = '^'
                    position_marker = 460
                    position_text = 440
                    precision_text = 0
                    units = ''
                elif 'meal' in key:
                    color = 'tab:brown'
                    marker = '^'
                    position_marker = 430
                    position_text = 410
                    precision_text = 0
                    units = 'g'
                elif 'carbCounted' in key:
                    color = 'tab:purple'
                    marker = '^'
                    position_marker = 460
                    position_text = 440
                    precision_text = 0
                    units = 'g'
                elif 'treat' in key:
                    color = 'tab:purple'
                    marker = '^'
                    position_marker = 340
                    position_text = 320
                    precision_text = 0
                    units = 'g'
                elif 'bolus' in key:
                    color = 'tab:blue'
                    marker = 'v'
                    position_marker = 380
                    position_text = 390
                    precision_text = 1
                    units = 'u'
                elif 'basal_dose' in key:
                    color = 'tab:blue'
                    marker = 'o'
                    position_marker = 350
                    position_text = 360
                    precision_text = 1
                    units = 'u'
                else:
                    continue

                if pd.api.types.is_string_dtype(value):
                    idx_valid = ~value.eq('')
                else:
                    idx_valid = value > 0
                val = value[idx_valid]
                t = times[idx_valid]
                for i in range(val.shape[0]):
                    if i == 0:
                        ax['p'].plot(t.iloc[i], position_marker, color=color, marker=marker, markersize=12,
                                     label=f'{key} ({units})')
                    else:
                        ax['p'].plot(t.iloc[i], position_marker, color=color, marker=marker, markersize=12)
                    if precision_text >= 0:
                        ax['p'].text(t.iloc[i], position_text, f'{val.iloc[i]:.{precision_text}f}{units}',
                                     color=color, fontsize=12, fontweight='bold', horizontalalignment='center')
                    else:
                        ax['p'].text(t.iloc[i], position_text, f'{val.iloc[i]}{units}', color=color, fontsize=12,
                                     fontweight='bold', horizontalalignment='center')
                ax['p'].legend()

            if 'basal_rate' in results_df:
                if pd.api.types.is_string_dtype(results_df['basal_rate']):
                    idx_valid = ~results_df['basal_rate'].eq('')
                else:
                    idx_valid = results_df['basal_rate'] > 0
                val = results_df['basal_rate'][idx_valid]
                t = times[idx_valid]
                ax2 = ax['p'].twinx()
                ax2.set_yticks(np.arange(0, 500 / 20, step=1))
                ax2.set_ylim(0, 500 / 20)
                color = 'tab:cyan'
                ax2.stairs(val, edges=np.insert(t.to_numpy(), 0, 0), color=color, fill=True,
                           label="basal (u/hr)")
                ax2.legend()
        else:
            ax = f.subplot_mosaic(
                """
                os
                is
                """,
                gridspec_kw={
                    "width_ratios": [15.0, 1.0],
                },
                sharex=True,
            )
            # plot outputs
            ax['o'].set_title('Outputs')
            ax['o'].set_yticks(np.arange(0, 500, step=40))
            ax['o'].axhline(y=54, color='r', linestyle='--')
            ax['o'].axhline(y=300, color='r', linestyle='--')
            ax['o'].axhline(y=70, color='g', linestyle='--')
            ax['o'].axhline(y=180, color='g', linestyle='--')
            ax['o'].axhline(y=40, color='k', linestyle='--')
            ax['o'].axhline(y=400, color='k', linestyle='--')
            ax['o'].grid(visible=True, which='both', alpha=0.3)
            ax['o'].grid(linewidth=1.5, which='major', axis='x', color='k')
            if 'outputs' in results_df:
                for idx, (key, val) in enumerate(results_df['outputs'].items()):
                    if 'cgm' in key:
                        color = 'tab:red'
                        marker = '.'
                    elif 'smbg' in key:
                        color = 'tab:purple'
                        marker = '*'
                    else:
                        color = 'k'
                        marker = ''
                    ax['o'].plot(val[:, 0], val[:, 1], color=color, marker=marker, linewidth=2,
                                 label=key.replace('{', '(').replace('}', ')').replace('Per', '/'))
                ax['o'].legend()

            # plot inputs
            if duration_in_days < 7:
                scale = 1.0 / 24.0
                ax['i'].set_xlabel('time (hours)')
            elif duration_in_days < 4 * 7:
                scale = 1.0
                ax['i'].set_xlabel('time (days)')
            else:
                scale = 7.0
                ax['i'].set_xlabel('time (weeks)')

            ax['i'].set_title('Inputs')
            ax['i'].set_xlim(0, duration_in_days)
            # Set major ticks
            ax['i'].set_xticks(np.arange(0, duration_in_days, step=scale),
                               labels=np.arange(0, duration_in_days / scale, step=1).astype(int))
            # Set minor ticks
            if scale == 1.0:
                ax['i'].set_xticks(np.arange(0, duration_in_days, step=1.0 / 6.0), minor=True)
            elif scale == 7.0:
                ax['i'].set_xticks(np.arange(0, duration_in_days, step=1.0), minor=True)
            ax['i'].grid(visible=True, which='both', alpha=0.3)
            ax['i'].grid(linewidth=1.5, which='major', axis='x', color='k')
            if 'inputs' in results_df:
                for idx, (key, val) in enumerate(results_df['inputs'].items()):
                    if 'category' in key:
                        color = 'tab:gray'
                        width = 0.07
                    elif 'meal' in key:
                        color = 'tab:brown'
                        width = 0.05
                    elif 'treat' in key:
                        color = 'tab:purple'
                        width = 0.05
                    elif 'basal' in key:
                        color = 'tab:cyan'
                        width = 0.14
                    elif 'bolus' in key:
                        color = 'tab:blue'
                        width = 0.10
                    else:
                        color = 'k'
                        width = 0.1
                    ax['i'].bar(val[:, 0], val[:, 1], color=color, width=width * duration_in_days / 14,
                                alpha=0.8,
                                label=key.replace('{', '(').replace('}', ')').replace('Per', '/'))
                ax['i'].legend()

        metrics_df = self.get_summary_metrics(results)

        metrics = metrics_df.values
        metrics_mean = metrics.mean(axis=0)  # get the mean of each outcome
        metrics_sd = metrics.std(axis=0)  # get the sd of each outcome
        tab_data = [['%.1f (%.1f)' % (metrics_mean[i], metrics_sd[i])] for i in range(len(metrics_mean))]
        tab_names = list(metrics_df.keys())

        if tab_data:
            tbl = ax['s'].table(
                cellText=tab_data,
                rowColours=plt.cm.BuPu(np.full(len(tab_data), 0.1)),
                rowLabels=tab_names,
                colLabels=['Outcome', 'Value'],
                colColours=plt.cm.BuPu(np.full(2, 0.1)),
                cellLoc='center',
                loc='center',
            )
            tbl.auto_set_font_size(False)
            tbl.set_fontsize(14)
            tbl.scale(1, 2.0)
            ax['s'].axis("off")

        return f

    def plot_group_results(self, results, title='Summary'):
        if not isinstance(results, list):
            logger.warning("Attempting to plot group results of an individual, plotting individual figure instead")
            return self.plot_individual_results(results)

        # handy function to pad matrix with zeros
        def pad_to_dense(M):
            maxlen = max(len(r) for r in M)
            Z = np.zeros((len(M), maxlen))
            for i, row in enumerate(M):
                Z[i, :len(row)] += row
            return Z

        # handy function to add an element
        def add_elem(key, val, d):
            if key not in d:
                d[key] = [val]
            else:
                a = d[key]
                a.append(val)
                d[key] = a
            return d

        insulin_traces = []
        cgm_traces = []  # list of cgm traces of each patient. Possibly ragged (if someone died)
        times = []
        for res in results:
            if 'data' not in res:
                continue
            if 'cgm' in res['data']:
                cgm_traces.append(res['data']['cgm'])
            if 'basal_rate' in res['data']:
                insulin_traces.append(res['data']['basal_rate'])
            if len(res['data']['time']) > len(times):
                times = res['data']['time']

        if not cgm_traces or all(len(trace) == 0 for trace in cgm_traces):
            logger.warning("Attempting to plot empty results nothing to do ...")
            return

        cgm_traces = pad_to_dense(cgm_traces)  # make not jagged by padding with zero
        cgm_traces = np.transpose(cgm_traces)  # make [time, ptID]
        if insulin_traces:
            insulin_traces = pad_to_dense(insulin_traces)  # make not jagged by padding with zero
            insulin_traces = np.transpose(insulin_traces)  # make [time, ptID]

        f = plt.figure(constrained_layout=True)
        f.set_size_inches(16, 9)
        f.suptitle(title, fontsize=16,
                   fontweight='bold')
        ax = f.subplot_mosaic(
            """
            ps
            """,
            gridspec_kw={
                "width_ratios": [12.0, 1.5],
            },
            sharex=True,
        )
        # plot config
        ax['p'].set_title('CGM/Insulin')
        ax['p'].set_yticks(np.arange(0, 480, step=20))
        ax['p'].set_ylim(0, 440)
        ax['p'].axhline(y=54, color='r', linestyle='--')
        ax['p'].axhline(y=250, color='r', linestyle='--')
        ax['p'].axhline(y=70, color='g', linestyle='--')
        ax['p'].axhline(y=180, color='g', linestyle='--')
        ax['p'].axhline(y=40, color='k', linestyle='--')
        ax['p'].axhline(y=400, color='k', linestyle='--')
        ax['p'].grid(visible=True, which='both', alpha=0.3)
        # ax['p'].grid(linewidth=1.5, which='major', axis='x', color='k')  # make x-axis lines darker

        # Get metrics for every patient
        plot_me = {}
        for t in range(len(cgm_traces)):
            row = cgm_traces[t, :]
            add_elem('median', np.median(row), plot_me)
            add_elem('25%', np.quantile(row, 0.25), plot_me)
            add_elem('75%', np.quantile(row, 0.75), plot_me)
            add_elem('5%', np.quantile(row, 0.05), plot_me)
            add_elem('95%', np.quantile(row, 0.95), plot_me)

        color = 'tab:blue'
        marker = '.'
        ax['p'].plot(times, plot_me['median'], color=color, marker=marker, linewidth=2, label="cgm (mg/dL)")
        ax['p'].legend()
        ax['p'].fill_between(times, plot_me['25%'], plot_me['75%'], color=color, alpha=0.3)  # fill quartile range
        ax['p'].fill_between(times, plot_me['25%'], plot_me['5%'], color=color, alpha=0.15)  # fill 25% quartile range
        ax['p'].fill_between(times, plot_me['75%'], plot_me['95%'], color=color, alpha=0.15)  # fill 75% quartile range

        # Set x-axis ticks/limits
        duration_in_days = round(len(cgm_traces) / 288)
        if duration_in_days < 7:
            scale = 1.0 / 24.0  # major scale in hours
            ax['p'].set_xlabel('time (hours)')
        elif duration_in_days < 4 * 7:
            scale = 1.0  # major scale in days
            ax['p'].set_xlabel('time (days)')
        else:
            scale = 7.0  # major scale in weeks
            ax['p'].set_xlabel('time (weeks)')
        ax['p'].set_xlim(0, duration_in_days)
        ax['p'].set_xticks(np.arange(0, duration_in_days, step=scale),
                           labels=np.arange(0, duration_in_days / scale, step=1).astype(int))
        if scale == 1.0:
            ax['p'].set_xticks(np.arange(0, duration_in_days, step=1.0 / 6.0), minor=True)
        elif scale == 7.0:
            ax['p'].set_xticks(np.arange(0, duration_in_days, step=1.0), minor=True)

        if np.any(insulin_traces):
            ax2 = ax['p'].twinx()
            ax2.set_yticks(np.arange(0, 480 / 20, step=1))
            ax2.set_ylim(0, 440 / 20)
            color = 'tab:cyan'
            plot_me = {}
            for t in range(len(insulin_traces)):
                row = insulin_traces[t, :]
                add_elem('median', np.median(row), plot_me)
                add_elem('25%', np.quantile(row, 0.25), plot_me)
                add_elem('75%', np.quantile(row, 0.75), plot_me)
                add_elem('5%', np.quantile(row, 0.05), plot_me)
                add_elem('95%', np.quantile(row, 0.95), plot_me)
            marker = ','
            ax2.plot(times, plot_me['median'], color=color, marker=marker, linewidth=2, label="cgm (mg/dL)")
            ax2.legend()
            ax2.fill_between(times, plot_me['25%'], plot_me['75%'], color=color, alpha=0.3)  # fill quartile range
            ax2.fill_between(times, plot_me['25%'], plot_me['5%'], color=color, alpha=0.15)  # fill outer quartile range
            ax2.fill_between(times, plot_me['75%'], plot_me['95%'], color=color,
                             alpha=0.15)  # fill outer quartile range

        metrics_df = self.get_summary_metrics(results)

        metrics = metrics_df.values
        metrics_mean = metrics.mean(axis=0)  # get the mean of each outcome
        metrics_sd = metrics.std(axis=0)  # get the sd of each outcome
        tab_data = [['%.1f (%.1f)' % (metrics_mean[i], metrics_sd[i])] for i in range(len(metrics_mean))]
        tab_names = list(metrics_df.keys())

        tbl = ax['s'].table(
            cellText=tab_data,
            rowColours=plt.cm.BuPu(np.full(len(tab_data), 0.1)),
            rowLabels=tab_names,
            colLabels=['Outcome', 'Value'],
            colColours=plt.cm.BuPu(np.full(2, 0.1)),
            cellLoc='center',
            loc='center',
        )
        tbl.auto_set_font_size(False)
        tbl.set_fontsize(14)
        tbl.scale(1, 2.0)
        ax['s'].axis("off")

        ax['p'].margins(x=0)  # make it go all the way to the edge. This has to be done after the table for some reason?

        return f

    @staticmethod
    def lbgi(cgm):
        if np.array(cgm).size:
            risk = np.log(np.array(cgm)) ** 1.084 - 5.381
            risk[risk > 0] = 0
            return 22.77 * np.mean(risk ** 2)
        else:
            return 0.0

    @staticmethod
    def hbgi(cgm):
        if np.array(cgm).size:
            risk = np.log(np.array(cgm)) ** 1.084 - 5.381
            risk[risk < 0] = 0
            return 22.77 * np.mean(risk ** 2)
        else:
            return 0.0
