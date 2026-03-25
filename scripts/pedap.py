import json
import os

import numpy as np
import pandas as pd


def _parse_mixed(x):
    """Parse mixed datetime formats (with/without time)."""
    for fmt in ("%m/%d/%Y %I:%M:%S %p", "%m/%d/%Y"):
        try:
            return pd.to_datetime(x, format=fmt)
        except (ValueError, TypeError):
            continue
    return pd.NaT


def preprocess_pedap(data_source):
    """Load and pre-process PEDAP source tables."""
    basal_all = pd.read_csv(os.path.join(data_source, "PEDAPTandemBASALDELIVERY.txt"), sep="|")
    bolus_all = pd.read_csv(os.path.join(data_source, "PEDAPTandemBolusDelivered.txt"), sep="|")
    cgm_all = pd.read_csv(os.path.join(data_source, "PEDAPTandemCGMDATAGXB.txt"), sep="|")
    phys_all = pd.read_csv(os.path.join(data_source, "PEDAPDiabPhysExam.txt"), sep="|")

    insulin_all = pd.read_csv(os.path.join(data_source, "PEDAPInsulin.txt"), sep="|")
    insulin_all = insulin_all[insulin_all["InsRoute"] == "Pump"]
    insulin_all["InsTypeStartDt"] = pd.to_datetime(
        insulin_all["InsTypeStartDt"], errors="coerce"
    )
    insulin_all["InsTypeStopDt"] = pd.to_datetime(
        insulin_all["InsTypeStopDt"], errors="coerce"
    )

    pt_ids = (
        set(cgm_all["PtID"]).intersection(set(basal_all["PtID"])).intersection(set(bolus_all["PtID"]))
    )
    subjects = list(pt_ids)

    return {
        "basal_all": basal_all,
        "bolus_all": bolus_all,
        "cgm_all": cgm_all,
        "phys_all": phys_all,
        "insulin_all": insulin_all,
        "subjects": subjects,
    }


def process_subj_pedap(cgm, basal, bolus, insulin, phys, subject_id, output_file):
    """Process a single PEDAP subject and write a DIAX JSON file."""
    cgm["time"] = cgm["DeviceDtTm"].apply(_parse_mixed)
    cgm = cgm.dropna(subset="time")
    cgm_data = cgm

    # Basal
    basal["time"] = basal["DeviceDtTm"].apply(_parse_mixed)
    basal = basal.dropna(subset="time")
    basal_data = basal

    # Bolus
    bolus["time"] = bolus["DeviceDtTm"].apply(_parse_mixed)
    bolus = bolus.dropna(subset="time")
    bolus_data = bolus

    meal_data = bolus[bolus["CarbAmount"] > 0].copy()

    # Time normalizing
    start_times = [
        cgm_data["time"].min(),
        basal_data["time"].min(),
        bolus_data["time"].min(),
    ]
    start_time = min(start_times)

    def normalize(df, col):
        df = df.copy()
        df.loc[:, col] = df[col].dt.strftime("%Y-%m-%d %H:%M:%S")
        return df.sort_values(col).reset_index(drop=True)

    cgm_data = normalize(cgm_data, "time")
    basal_data = normalize(basal_data, "time")
    bolus_data = normalize(bolus_data, "time")

    ins_string = "UNKNOWN"
    if len(insulin) > 1:
        start_date = start_time.strftime("%Y-%m-%d")
        dates = (
            insulin["InsTypeStartDt"].dt.strftime("%Y-%m-%d").fillna(start_date).tolist()
        )
        ins = insulin["InsulinName"].tolist()

        # if the insulin is the same as the previous one, skip it
        for i in range(1, len(ins)):
            if ins[i] == ins[i - 1]:
                dates[i] = np.nan
        # remove the nan entries
        idx_keep = [i for i in range(len(dates)) if pd.notna(dates[i])]
        dates = [dates[i] for i in idx_keep]
        ins = [ins[i] for i in idx_keep]

        if len(ins) == 1:
            ins_string = ins[0]
        else:
            ins_string = {"date": dates, "insulin": ins}
    elif len(insulin) == 1:
        ins_string = insulin["InsulinName"].iloc[0]

    # Get height and weight from phys exam data
    weight = phys["Weight"].values[0]
    height = phys["Height"].values[0]

    # correct units if needed
    weight_units = phys["WeightUnits"].values[0]
    if pd.notna(weight_units):
        weight_units = weight_units.lower().strip()
    else:
        weight_units = ""

    # convert weight if needed
    if weight_units in ["lbs", "pounds", "lb"]:
        weight = weight * 0.453592
    elif weight_units in ["kg", "kilograms", "kg."]:
        pass
    else:
        print(f"Unknown weight units: {weight_units}, assuming kg.")

    # get the height units
    height_units = phys["HeightUnits"].values[0]
    if pd.notna(height_units):
        height_units = height_units.lower().strip()
    else:
        height_units = ""
    # convert height if needed
    if height_units in ["in", "inches", "inch"]:
        height = height * 2.54
    elif height_units in ["cm", "centimeters", "cms"]:
        pass
    else:
        print(f"Unknown height units: {height_units}, assuming cm.")

    output = {
        "metadata": {
            "unique_id": "id number of the subject",
            "time": {
                "unit": "Y-m-d H:M:S",
                "description": "Timestamps for each measurement, assumed to be in local time",
            },
            "cgm": {
                "unit": "mg/dL",
                "description": "Continuous Glucose Monitor readings",
                "device": "UNKOWN",
                "precision": 1,
            },
            "basal_rate": {
                "unit": "U/hr",
                "description": "The rate of insulin delivery from the pump",
                "device": "Tandem pump",
                "insulin": ins_string,
            },
            "bolus": {
                "unit": "U",
                "description": "The amount of insulin delivered in a bolus, meal and correction, in units",
                "device": "Tandem pump",
                "insulin": ins_string,
            },
            "carbs": {
                "unit": "grams",
                "description": "User announced carbohydrate intake associated with bolus",
            },
        },
        "unique_id": subject_id,
        "cgm": {"time": cgm_data["time"].tolist(), "value": cgm_data["CGMValue"].tolist()},
        "basal_rate": {
            "time": basal_data["time"].tolist(),
            "value": basal_data["BasalRate"].tolist(),
        },
        "bolus": {
            "time": bolus_data["time"].tolist(),
            "value": bolus_data["BolusAmount"].tolist(),
        },
        "carbs": {
            "time": meal_data["time"].tolist(),
            "value": meal_data["CarbAmount"].tolist(),
        },
    }

    with open(output_file, "w") as f:
        json.dump(output, f, indent=2, default=str)


def process_all_pedap(data_source, output_dir):
    """Process all PEDAP subjects from the source directory."""
    os.makedirs(output_dir, exist_ok=True)
    prep = preprocess_pedap(data_source)

    cgm_all = prep["cgm_all"]
    basal_all = prep["basal_all"]
    bolus_all = prep["bolus_all"]
    insulin_all = prep["insulin_all"]
    phys_all = prep["phys_all"]
    subjects = prep["subjects"]

    for subject_id in subjects:
        cgm = cgm_all[cgm_all["PtID"] == subject_id].copy()
        basal = basal_all[basal_all["PtID"] == subject_id].copy()
        bolus = bolus_all[bolus_all["PtID"] == subject_id].copy()
        insulin = insulin_all[insulin_all["PtID"] == subject_id].copy()
        phys = phys_all[phys_all["PtID"] == subject_id].copy()

        output_file = os.path.join(output_dir, f"PEDAP_subject_{subject_id}.json")
        process_subj_pedap(cgm, basal, bolus, insulin, phys, subject_id, output_file)

    return len(subjects)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Process all PEDAP subjects.")
    parser.add_argument("--source", required=True, help="Path to PEDAP data directory.")
    parser.add_argument("--output", required=True, help="Output directory for JSON files.")
    args = parser.parse_args()

    count = process_all_pedap(args.source, args.output)
    print(f"Processed {count} subjects.")
