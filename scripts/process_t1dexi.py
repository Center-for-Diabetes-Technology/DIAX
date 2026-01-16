import pandas as pd
import polars as pl
import numpy as np
import os
import sys
import json
import datetime

epoch_1960 = datetime.datetime(1960, 1, 1, 0, 0, 0)

def process_subject(FAMLPM, DX, CM, FACM, LB, FA, VS, subject, output_path):
    # convert to polars for faster processing
    FAMLPM = pl.from_pandas(FAMLPM)
    FACM = pl.from_pandas(FACM)
    LB = pl.from_pandas(LB)
    FA = pl.from_pandas(FA)
    VS = pl.from_pandas(VS)


    steps_data = (
        FA.filter(pl.col("FATESTCD") == "STEPSTKN")
        .with_columns(
            ((pl.col("FADTC").cast(pl.Float64) * 1000).cast(pl.Duration("ms")) + epoch_1960).alias("time"),  # Convert to datetime
            pl.col("FAORRES").str.strip_chars().cast(pl.Int64).alias("FAORRES")  # Ensure steps are integers
        )
    )
    if steps_data.height == 0:
        print(f"Subject has no steps data, skipping subject: {output_path}")
        return None
    start_time_steps = steps_data["time"][0]

    # FACM Data Processing (Pump Basal, Injected Basal, Bolus)
    #FACM-Basal
    FACM = FACM.with_columns([((pl.col("FADTC").cast(pl.Float64) * 1000).cast(pl.Duration("ms")) + epoch_1960).alias("time")])

    basal_data = (
        FACM
        .filter(pl.col("FATESTCD") == "BASFLRT")
        .with_columns([
            pl.col("FAORRES")
            .cast(pl.Utf8)                # Ensure it's treated as a string
            .str.strip_chars()            # Remove leading/trailing whitespace
            .replace("", None)            # Replace empty strings with nulls
            .cast(pl.Float64)             # Convert to float
            .fill_null(0.0)               # Fill nulls with 0.0  (insulin suspension)
        ])
    )
    if basal_data.height == 0:
        print(f"Subject has no basal data, skipping subject: {output_path}")
        return None

    basal_type = None
    start_time_basal = None

    if basal_data.height > 0:
        start_time_basal = basal_data["time"][0]
        basal_data = basal_data.fill_null(0)
        basal_type = "pump"
    else:
        basal_data = FACM.filter(pl.col("INSDVSRC") == "Injections").with_columns(
            pl.col("FAORRES").str.strip_chars().cast(pl.Float64)
        )
        start_time_basal = basal_data["time"][0]
        basal_data = basal_data.fill_null(0)
        basal_type = "injection"

    #FACM-Bolus
    bolus_data = FACM.filter(pl.col("FATESTCD") == "INSBOLUS").with_columns(
        pl.col("FAORRES").str.strip_chars().cast(pl.Float64)
    )
    if bolus_data.height == 0:
        print(f"Subject has no bolus data, skipping subject: {output_path}")
    start_time_bolus = bolus_data["time"][0]

    # LB Data Processing (CGM)
    # LB-CGM
    cgm_data = LB.filter(pl.col("LBTEST") == "Glucose").with_columns(
        ((pl.col("LBDTC").cast(pl.Float64) * 1000).cast(pl.Duration("ms")) + epoch_1960).alias("time")  # Convert to datetime
    )
    if cgm_data.height == 0:
        print(f"Subject has no CGM data, skipping subject: {output_path}")
    start_time_cgm = cgm_data["time"][0]

    # FAMLPM Data Processing (Carbs)
    carbs_data = FAMLPM
    start_time_carbs = carbs_data["time"].min()

    # VS Data Processing (Heart Rate, Height, Weight)
    heart_rate_data = (
        VS.filter(pl.col("VSCAT") == "VERILY HEART RATE")
        .with_columns([
            ((pl.col("VSDTC").cast(pl.Int64) * 1000).cast(pl.Duration("ms")) + epoch_1960).alias("time"),
            pl.col("VSSTRESC").str.strip_chars().cast(pl.Int32).alias("VSSTRESC")  # Ensure heart rate is integer
        ])
    )
    if heart_rate_data.height == 0:
        print(f"Subject has no heart rate data, skipping subject: {output_path}")
        return None
    
    start_time_heart_rate = heart_rate_data["time"][0]

    # Find first time
    start_time_array = [start_time_basal, start_time_bolus, start_time_cgm, start_time_carbs] # don't include heart rate and steps since they may start much earlier and are very large data
    start_time = min(start_time_array)

    def normalize(data, time_column):
        return (
                data
                .filter(pl.col(time_column) >= start_time)
                .with_columns(pl.col(time_column).dt.strftime('%Y-%m-%d %H:%M:%S').alias(time_column))
                .sort(time_column)
            )


    steps_data = normalize(steps_data, "time")
    basal_data = normalize(basal_data, "time")
    bolus_data = normalize(bolus_data, "time")
    cgm_data = normalize(cgm_data, "time")
    heart_rate_data = normalize(heart_rate_data, "time")
    carbs_data = normalize(carbs_data, "time")

    # Get height and weight from VS
    weight = VS.filter(pl.col("VSTEST") == "Weight").sort("VSDTC", descending=True)
    w = weight["VSORRES"][0]
    if isinstance(w, str):
        w = float(w.strip())
    w_unit = weight["VSORRESU"][0].lower().strip() if weight["VSORRESU"][0] is not None else ""
    if w_unit in ['lbs', 'pounds']:
        w = w * 0.453592  # convert lbs to kg
    elif w_unit in ['kg', 'kilograms', 'kgs']:
        pass  # already in kg
    else:
        print(f"Unknown weight unit '{w_unit}' for subject, assuming kg.")

    height = VS.filter(pl.col("VSTEST") == "Height").sort("VSDTC", descending=True)
    h = height["VSSTRESC"][0]
    if isinstance(h, str):
        h = float(h.strip())
    h_unit = height["VSORRESU"][0].lower().strip() if height["VSORRESU"][0] is not None else ""
    if h_unit in ['in', 'inches']:
        h = h * 2.54  # convert inches to cm
    elif h_unit in ['cm', 'centimeters', 'cms']:
        pass  # already in cm
    else:
        print(f"Unknown height unit '{h_unit}' for subject, assuming cm.")


    output = {
        "metadata": {
            "time": {
                "unit": "Y-m-d H:M:S",
                "description": "Time since start_datetime in seconds. start_datetime is assumed in local timezone."
            },
            "height": {
                "unit": "cm",
                "description": "Height of the patient at the start of the study"
            },
            "weight": {
                "unit": "kg",
                "description": "Weight of the patient at the start of the study"
            },
            "cgm": {
                "unit": "mg/dL",
                "description": "Continuous Glucose Monitoring (CGM) data",
                "device": "UNKNOWN",
                "precision": "1"
            },
            "bolus": {
                "unit": "U",
                "description": "Insulin bolus data, meal and correction, in units",
                "device": "UNKNOWN",
                "insulin": "UNKNOWN"
            },
            "heart_rate": {
                "unit": "bpm",
                "description": "Heart rate of the patient",
                "device": "UNKNOWN"
            },
            "steps": {
                "unit": "steps per 10 seconds",
                "description": "Step count of the patient logged every ten seconds",
                "device": "UNKNOWN"
            },
            "carbs": {
                "unit": "grams",
                "description": "User announced carbohydrate intake"
            },
        },
        "unique_id": subject,
        "height": {
            "time": start_time,
            "value": h
        },
        "weight": {
            "time": start_time,
            "value": w
        },
        "cgm": {
            "time": cgm_data["time"].to_list(),
            "value": cgm_data["LBSTRESC"].cast(pl.Int32).to_list()
        },
        "bolus": {
            "time": bolus_data["time"].to_list(),
            "value": bolus_data["FAORRES"].to_list()
        },
        "heart_rate": {
            "time": heart_rate_data["time"].to_list(),
            "value": heart_rate_data["VSSTRESC"].to_list()
        },
        "steps": {
            "time": steps_data["time"].to_list(),
            "value": steps_data["FAORRES"].to_list()
        },
        "carbs": {
            "time": carbs_data["time"].to_list(),
            "value": carbs_data["FASTRESN"].to_list()
        },
    }

    if basal_type == "pump":
        # get pump type from DX
        pump_type = DX['DXTRT'].unique().tolist()
        if len(pump_type) == 0:
            pump_type = "UNKNOWN"
        else:
            pump_type = ', '.join(pump_type)

        insulin_type = CM['CMTRT'].unique().tolist()
        if len(insulin_type) == 0:
            insulin_type = "UNKNOWN"
        else:
            insulin_type = ', '.join(insulin_type)

        output["metadata"]["basal_rate"] = {
            "unit": "U/h",
            "description": "Basal insulin delivery by pump data",
            "device": pump_type,
            "insulin": insulin_type
        }
        output["basal_rate"] = {
            "time": basal_data["time"].to_list(),
            "value": basal_data["FAORRES"].to_list()
        }

        output['metadata']['bolus']['insulin'] = insulin_type

    elif basal_type == "injection":
        basal_insulin_type = CM[CM['CMSCAT'] == 'MDI, BASAL INSULIN']['CMTRT'].unique().tolist()
        if len(basal_insulin_type) == 0:
            basal_insulin_type = "UNKNOWN"
        else:
            basal_insulin_type = ', '.join(basal_insulin_type)

        bolus_insulin_type = CM[CM['CMSCAT'] == 'MDI, BOLUS INSULIN']['CMTRT'].unique().tolist()
        if len(bolus_insulin_type) == 0:
            bolus_insulin_type = "UNKNOWN"
        else:
            bolus_insulin_type = ', '.join(bolus_insulin_type)

        output["metadata"]["basal_inj"] = {
            "unit": "U/h",
            "description": "Basal insulin delivery by injection data",
            "insulin": basal_insulin_type
        }
        output["basal_inj"] = {
            "time": basal_data["time"].to_list(),
            "value": basal_data["FAORRES"].to_list()
        }

        output['metadata']['bolus']['insulin'] = bolus_insulin_type


    # Save output to JSON
    with open(output_path, 'w') as f:
        print(f"Saving processed data to {output_path}")
        json.dump(output, f, indent=4, default=str)
    
    print(f"Finished processing subject, output saved to {output_path}")
    return output


if __name__ == "__main__":
    data_source = "../../data_raw/T1DEXI - DATA FOR UPLOAD/"

    if not os.path.exists(f"{data_source}/FAMLPM.pkl"):
        # Load the FAMLPM dataset from the SAS XPT file
        # The encoding is set to 'cp1252' to handle special characters correctly
        # This file contains dietary intake data
        print("Loading FAMLPM dataset...")
        FAMLPM_all = pd.read_sas(f"{data_source}/FAMLPM.xpt", encoding="cp1252")
        FAMLPM_all = FAMLPM_all[FAMLPM_all['FATEST'] == 'Dietary Total Carbohydrates']  # get only carb data
        FAMLPM_all = FAMLPM_all[FAMLPM_all['FACAT'] == 'CONSUMED']  # make sure it is consumed
        FAMLPM_all['time'] = pd.to_datetime(FAMLPM_all['FADTC'], unit='s', origin=datetime.datetime(1960, 1, 1))
        # save it to pickle file for faster loading next time
        FAMLPM_all.to_pickle(f"{data_source}/FAMLPM.pkl")
    else:
        print("Loading FAMLPM dataset from pickle...")
        FAMLPM_all = pd.read_pickle(f"{data_source}/FAMLPM.pkl")

    DX_all = pd.read_sas(f"{data_source}/DX.xpt", encoding="cp1252")
    DX_all = DX_all[DX_all['DXTRT'] != 'INSULIN PUMP']  # remove the generic insulin pump entry

    CM_all = pd.read_sas(f"{data_source}/CM.xpt", encoding="cp1252")
    CM_all = CM_all[CM_all['CMSCAT'].isin(['MDI, BOLUS INSULIN', 'MDI, BASAL INSULIN', 'PUMP OR CLOSED LOOP'])] # we care about: 'MDI, BOLUS INSULIN', 'MDI, BASAL INSULIN', 'PUMP OR CLOSED LOOP'
    CM_all = CM_all[~CM_all['CMTRT'].isin(['BASAL INSULIN', 'BOLUS INSULIN', 'PUMP OR CLOSED LOOP INSULIN'])]  # just keep medication names

    if not os.path.exists(f"{data_source}/FA_1.pkl"):
        # FA dataset is too large to fit in memory, so we will process it in chunks and save each subject's data into separate pickle files

        itr = pd.read_sas(f'{data_source}/FA.xpt', chunksize=10000000, encoding="cp1252")
        i = 0
        FA_subjs = set()
        for chunk in itr:
            print(f"Processing FA chunk {i}")
            chunk = chunk[['USUBJID', 'FADTC', 'FATESTCD', 'FAORRES']]  # keep only relevant columns to reduce size
            # save each subject into separate pickle files
            grps = chunk.groupby('USUBJID')
            for subj, df_subj in grps:
                subj_path = f"{data_source}/FA_{subj}.pkl"
                FA_subjs.add(subj)
                if os.path.exists(subj_path):
                    df_existing = pd.read_pickle(subj_path)
                    df_combined = pd.concat([df_existing, df_subj], ignore_index=True)
                    df_combined.to_pickle(subj_path)
                else:
                    df_subj.to_pickle(subj_path)
            i += 1
    else:
        FA_subjs = set()
        import glob
        for f in glob.glob(f"{data_source}/FA_*.pkl"):
            subj = os.path.basename(f).replace("FA_", "").replace(".pkl", "")
            FA_subjs.add(subj)

    if not os.path.exists(f"{data_source}/VS_1.pkl"):
        # VS dataset is too large to fit in memory, so we will process it in chunks and save each subject's data into separate pickle files

        itr = pd.read_sas(f'{data_source}/VS.xpt', chunksize=10000000, encoding="cp1252")
        i = 0
        for chunk in itr:
            print(f"Processing VS chunk {i}")
            chunk = chunk[["USUBJID", "VSDTC", "VSCAT", "VSTEST", "VSSTRESC", "VSORRES", "VSORRESU"]]  # keep only relevant columns to reduce size
            # save each subject into separate pickle files
            grps = chunk.groupby('USUBJID')
            for subj, df_subj in grps:
                subj_path = f"{data_source}/VS_{subj}.pkl"
                if os.path.exists(subj_path):
                    df_existing = pd.read_pickle(subj_path)
                    df_combined = pd.concat([df_existing, df_subj], ignore_index=True)
                    df_combined.to_pickle(subj_path)
                else:
                    df_subj.to_pickle(subj_path)
            i += 1
    else:
        import glob
        for f in glob.glob(f"{data_source}/VS_*.pkl"):
            subj = os.path.basename(f).replace("VS_", "").replace(".pkl", "")
            FA_subjs.add(subj)

    if not os.path.exists(f"{data_source}/FACM.pkl"):
        FACM_all = pd.read_sas(f"{data_source}/FACM.xpt", encoding="cp1252")
        FACM_all.to_pickle(f"{data_source}/FACM.pkl") 
    else:
        FACM_all = pd.read_pickle(f"{data_source}/FACM.pkl")

    if not os.path.exists(f"{data_source}/LB.pkl"):
        LB_all = pd.read_sas(f"{data_source}/LB.xpt", encoding="cp1252")
        LB_all.to_pickle(f"{data_source}/LB.pkl")
    else:
        LB_all = pd.read_pickle(f"{data_source}/LB.pkl")

    # get subjects that are in all datasets
    subjects = set(FAMLPM_all['USUBJID']).\
        intersection(set(DX_all['USUBJID'])).\
        intersection(set(CM_all['USUBJID'])).\
        intersection(set(FACM_all['USUBJID'])).\
        intersection(set(LB_all['USUBJID'])).\
        intersection(FA_subjs).\
        intersection(FA_subjs) 

    print(f"Found {len(subjects)} subjects with all required datasets.")
    subjects = list(subjects)

    output_dir = '../../diax/T1DEXI/'

    if not os.path.exists(output_dir):
        os.makedirs(output_dir)


    args_list = []
    for subject in subjects:
        FAMLPM = FAMLPM_all[FAMLPM_all['USUBJID'] == subject]
        DX = DX_all[DX_all['USUBJID'] == subject]
        CM = CM_all[CM_all['USUBJID'] == subject]
        FACM = FACM_all[FACM_all['USUBJID'] == subject]
        LB = LB_all[LB_all['USUBJID'] == subject]
        FA = pd.read_pickle(f"{data_source}/FA_{subject}.pkl")
        VS = pd.read_pickle(f"{data_source}/VS_{subject}.pkl")
        output_path = os.path.join(output_dir, f"T1Dexi_{subject}.json")

        if (len(FAMLPM) == 0) or (len(DX) == 0) or (len(CM) == 0) or (len(FACM) == 0) or (len(LB) == 0) or (len(FA) == 0) or (len(VS) == 0):
            print(f"Skipping subject {subject} due to missing data in one of the datasets.")
            continue

        args_list.append((FAMLPM, DX, CM, FACM, LB, FA, VS, subject, output_path))
    
    # with multiprocessing.Pool(processes=20) as pool:
    #     pool.starmap(process_subject, args_list)
    for args in args_list:
        process_subject(*args)