import pandas as pd
import numpy as np
import json
import datetime
from typing import Any, Callable, Dict, Iterable, List, Optional, Union



def time_align(
                diax_data: Union[Dict[str, Any], str],
                sampling_period: float,
                start_time: Optional[Union[datetime.datetime, str]] = None,
                end_time: Optional[Union[datetime.datetime, str]] = None,
                columns: Optional[Iterable[str]] = None,
                resample_strategy: Optional[Dict[str, str]] = None,
                missing_strategy: Optional[Union[str, Dict[str, Union[str, Callable]]]] = None,
                missing_tolerance: Optional[Union[float, Dict[str, float]]] = None,
            ) -> pd.DataFrame:
    """
    Align multiple diax-style time series onto a common time axis.

    Parameters
    ----------
    diax_data : dict or str
        Dictionary of signals or path to a JSON file containing them.
        Each signal must include 'time' and 'value'.
    sampling_period : float
        Output sampling period in minutes.
    start_time, end_time : datetime or str, optional
        Optional overrides for the time span. If omitted, min/max across
        inputs are used.
    columns : iterable of str, optional
        Subset of signals to process. If omitted, all valid time-series keys
        are used.
    resample_strategy : str or dict, optional
        Per-column or global resampling rule. Supported: 'ffill', 'mean', 'sum'.
        Default:
            cgm -> mean  
            basal_rate -> mean  
            basal_inj -> sum  
            bolus -> sum  
            carbs -> sum  
            heart_rate -> mean  
            steps -> sum  
            default -> ffill
    missing_strategy : str, dict, or callable, optional
        Strategy for handling gaps after resampling. Supported strings:
            'interpolate', 'interpolate_inside', 'ffill', 'mean', 'none',
            'fill<X>' (e.g., 'fill0', X must be processable as float).
        A callable may also be provided with signature
            (series, tolerance, sampling_period) -> Series.
        Default:
            cgm -> interpolate  
            basal_rate -> ffill  
            basal_inj -> none  
            bolus -> none  
            carbs -> none  
            heart_rate -> interpolate  
            steps -> none  
            default -> interpolate
    missing_tolerance : float or dict, optional
        Maximum fill/interpolation gap in minutes. Converted to a sample limit.
        Default:
            cgm -> 60  
            basal_rate -> 1440  
            basal_inj -> 1440  
            bolus -> None (infinity)
            carbs -> None (infinity)
            heart_rate -> 15  
            steps -> None (infinity)
            default -> sampling_period * 3
    Returns
    -------
    DataFrame
        Indexed by the common DateTimeIndex at the given sampling period,
        containing aligned, resampled, and gap-filled signals.

    Notes
    -----
    - Time inputs may be ISO strings or datetime objects.
    - Each signal is handled independently using its assigned strategies.
    """


    # If a path was provided, load the JSON file
    if isinstance(diax_data, str):
        with open(diax_data, "r") as fh:
            diax_data = json.load(fh)

    if columns is None:
        time_keys = [col for col in diax_data.keys() if 'metadata' not in col and 'time' in diax_data[col]]
    else:
        time_keys = columns

    # set default strategies if not provided
    rs_default = {  'cgm': 'mean', 
                    'basal_rate': 'mean', 'basal_inj': 'sum', 
                    'bolus': 'sum', 'carbs': 'sum',
                    'heart_rate': 'mean', 'steps': 'sum',
                    'default': 'ffill'}
    
    ms_default = {  'cgm': 'interpolate', 
                    'basal_rate': 'ffill', 'basal_inj': 'none', 
                    'bolus': 'none', 'carbs': 'none',
                    'heart_rate': 'interpolate', 'steps': 'none',
                    'default': 'interpolate'}
    mt_default = {  'cgm': 60, 
                    'basal_rate': 60*24,   # one basal rate per day
                    'basal_inj': 60*24,    # one basal injection per day
                    'bolus': None, 'carbs': None,
                    'heart_rate': 15, 'steps': None,
                    'default': sampling_period * 3}
    
    if resample_strategy is None:
        resample_strategy = rs_default
    elif isinstance(resample_strategy, dict):
        rs_default.update(resample_strategy)
        resample_strategy = rs_default
    else:
        resample_strategy = resample_strategy

    if missing_strategy is None:
        missing_strategy = ms_default
    elif isinstance(missing_strategy, dict):
        ms_default.update(missing_strategy)
        missing_strategy = ms_default
    else:
        missing_strategy = missing_strategy

    if missing_tolerance is None:
        missing_tolerance = mt_default
    elif isinstance(missing_tolerance, dict):
        mt_default.update(missing_tolerance)
        missing_tolerance = mt_default
    else:
        missing_tolerance = missing_tolerance

    for col in time_keys:
        if 'time' in diax_data[col]:
            dat = diax_data[col]['time']
            # make sure it is in datetime format, and is a list
            if not isinstance(dat[0], datetime.datetime):
                if isinstance(dat, list):
                    diax_data[col]['time'] = [datetime.datetime.fromisoformat(d) for d in dat]
                else:
                    diax_data[col]['time'] = [datetime.datetime.fromisoformat(dat)]
                    diax_data[col]['value'] = [diax_data[col]['value']]
            else:
                print(f"{col} time data already in datetime format")
        else:
            raise ValueError(f"No time data found for column: {col}")

    if start_time is None:
        start_time = min(min(diax_data[col]['time']) for col in time_keys)

    if end_time is None:
        end_time = max(max(diax_data[col]['time']) for col in time_keys)

    # create the common time axis
    common_time_index = pd.date_range(start=start_time, end=end_time, freq=pd.Timedelta(minutes=sampling_period))

    # resample each time series to the common time axis
    combined_df = pd.DataFrame(index=common_time_index)

    # now fill_missing according to strategy
    for col in time_keys:
        dat = diax_data[col]
        df = pd.DataFrame(data=dat['value'], index=pd.to_datetime(dat['time']), columns=[col])
        
        # get strategies
        if isinstance(resample_strategy, dict):
            resample_strategy_col = resample_strategy.get(col, resample_strategy.get('default', 'ffill'))  # first try column-specific, then default, else 'ffill'
        else:
            resample_strategy_col = resample_strategy

        if isinstance(missing_strategy, dict):
            missing_strategy_col = missing_strategy.get(col, missing_strategy.get('default', 'none'))  # first try column-specific, then default, else 'interpolate'
        else:
            missing_strategy_col = missing_strategy

        if isinstance(missing_tolerance, dict):
            missing_tolerance_col = missing_tolerance.get(col, missing_tolerance.get('default', sampling_period * 3))  # first try column-specific, then default, else 3x sampling_period
        else:
            missing_tolerance_col = missing_tolerance

        if (missing_tolerance_col is None) or (missing_tolerance_col <= 0) or (np.isinf(missing_tolerance_col)):
            missing_limit = None
        else:
            missing_limit = missing_tolerance_col // sampling_period

        # Resample to common time index
        if resample_strategy_col == 'mean':
            resampled = df.resample(f'{sampling_period}min', label='right', closed='right').mean()
        elif resample_strategy_col == 'ffill':
            resampled = df.resample(f'{sampling_period}min', label='right', closed='right').ffill()
        elif resample_strategy_col == 'sum':
            resampled = df.resample(f'{sampling_period}min', label='right', closed='right').sum()
        else:
            raise ValueError(f"Unknown resample strategy: {resample_strategy_col}")

        # Reindex to common time index
        resampled = resampled.reindex(common_time_index)

        # now interpolate missing data according to missing_strategy
        if callable(missing_strategy_col):  # custom interpolation function
            combined_df[col] = missing_strategy_col(resampled[col], missing_tolerance, sampling_period)
        else:  # predefined strategies
            if missing_strategy_col == 'mean':
                combined_df[col] = resampled[col].fillna(resampled[col].mean(), limit=missing_limit)
            elif missing_strategy_col == 'ffill':
                combined_df[col] = resampled[col].ffill(limit=missing_limit)
            elif missing_strategy_col == 'interpolate_inside':
                combined_df[col] = resampled[col].interpolate(method='linear', limit_area='inside', limit=missing_limit)
            elif missing_strategy_col == 'interpolate':  # interpolate and zero-order-hold out-of-bounds
                combined_df[col] = resampled[col].interpolate(method='linear', limit=missing_limit, limit_direction='both')
            elif 'fill' in missing_strategy_col:
                fill_value = float(missing_strategy_col.replace('fill', ''))
                combined_df[col] = resampled[col].fillna(fill_value, limit=missing_limit)
            else:  # no interpolation or filling
                combined_df[col] = resampled[col]

    # Drop rows where all columns are NaN
    combined_df.dropna(how='all', inplace=True)

    return combined_df


if __name__ == "__main__":
    # Example usage
    diax_data = json.load(open('../../../diax/T1DEXI/T1Dexi_145.json', 'r'))

    resample_strategy = {'cgm': 'mean', 'basal_rate': 'mean', 'basal_inj': 'sum', 'bolus': 'sum', 'heart_rate': 'mean', 'steps': 'sum', 'carbs': 'sum'}
    missing_strategy = {'cgm': 'interpolate', 'basal_rate': 'ffill', 'basal_inj': 'fill0', 'bolus': 'none', 'heart_rate': 'interpolate', 'steps': 'fill0', 'carbs': 'none'}
    missing_tolerance = {'cgm': 60, 'basal_rate': 60*24, 'basal_inj': 60*24, 'bolus': 60, 'heart_rate': 15, 'steps': 60, 'carbs': None}

    df = time_align(diax_data, sampling_period=5, resample_strategy=resample_strategy, missing_strategy=missing_strategy, missing_tolerance=missing_tolerance)
    print(df.head(20))
    df.to_csv('example_aligned_output.csv')