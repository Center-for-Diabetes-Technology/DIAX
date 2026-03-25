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


def preprocess_iobp2(data_source):
    """Load and pre-process IOBP2 source tables."""
    dset_all = pd.read_csv(os.path.join(data_source, "IOBP2DeviceiLet.txt"), sep="|")

    insulin_all = pd.read_csv(os.path.join(data_source, "IOBP2Insulin.txt"), sep="|")
    insulin_all = insulin_all[insulin_all["InsRoute"] == "Pump"]
    insulin_all["InsTypeStartDt"] = pd.to_datetime(
        insulin_all["InsTypeStartDt"], errors="coerce"
    )
    insulin_all["InsTypeStopDt"] = pd.to_datetime(
        insulin_all["InsTypeStopDt"], errors="coerce"
    )

    height_weight = pd.read_csv(os.path.join(data_source, "IOBP2HeightWeight.txt"), sep="|")

    smbg_all = pd.read_csv(os.path.join(data_source, "IOBP2DeviceBGM.txt"), sep="|")

    subjects = list(set(dset_all["PtID"].unique()))

    return {
        "dset_all": dset_all,
        "insulin_all": insulin_all,
        "height_weight": height_weight,
        "smbg_all": smbg_all,
        "subjects": subjects,
    }


def process_subj_iobp2(dset, insulin, smbg, hw, subject_id, output_file):
    """Process a single IOBP2 subject and write a DIAX JSON file."""
    # get datetime
    dset.loc[:, "time"] = dset["DeviceDtTm"].apply(_parse_mixed)
    smbg.loc[:, "time"] = smbg["DeviceDtTm"].apply(_parse_mixed)

    # get time delta (used for computing basal rate in u/hr)
    dset.loc[:, "time_delta"] = dset.loc[:, "time"].diff()
    dset.iloc[0, dset.columns.get_loc("time_delta")] = pd.Timedelta(minutes=5)

    # Compute current delivery from previous delivery
    dset.loc[:, "BasalDelivNow"] = dset.loc[:, "BasalDelivPrev"].shift(-1)
    dset.loc[:, "BolusDelivNow"] = dset.loc[:, "BolusDelivPrev"].shift(-1)
    dset.loc[:, "BasalDelivNow"] = dset.loc[:, "BasalDelivNow"].fillna(0)
    dset.loc[:, "BolusDelivNow"] = dset.loc[:, "BolusDelivNow"].fillna(0)

    # Extract relevant columns
    cgm_data = dset[["time", "CGMVal"]]
    cgm_data = cgm_data[pd.notna(cgm_data["CGMVal"])]  # drop rows with NaN CGM values

    basal_data = dset[["time", "BasalDelivNow", "time_delta"]].copy()
    basal_data.loc[:, "BasalRate"] = (
        basal_data["BasalDelivNow"]
        / basal_data["time_delta"].dt.total_seconds()
        * 3600
    )

    bolus_data = dset[["time", "BolusDelivNow", "MealBolus"]].copy()
    bolus_data.loc[:, "BolusAmount"] = (
        bolus_data["BolusDelivNow"] + bolus_data["MealBolus"]
    )
    bolus_data = bolus_data[bolus_data["BolusAmount"] > 0]

    carb_data = dset[["time", "MealBolus", "MealSize"]]
    carb_data = carb_data[carb_data["MealBolus"] > 0]

    smbg_data = smbg[["time", "BGMVal"]]

    # Time normalizing
    start_times = [
        cgm_data["time"].min(),
        basal_data["time"].min(),
        bolus_data["time"].min(),
        smbg_data["time"].min(),
        carb_data["time"].min(),
    ]
    # Filter out any NaT values before taking the min
    start_times = [t for t in start_times if pd.notna(t)]
    start_time = min(start_times)

    def normalize(df, col):
        if len(df) == 0:
            return df

        df = df.copy()
        df.loc[:, col] = df[col].dt.strftime("%Y-%m-%d %H:%M:%S")
        return df.sort_values(col).reset_index(drop=True)

    cgm_data = normalize(cgm_data, "time")
    basal_data = normalize(basal_data, "time")
    bolus_data = normalize(bolus_data, "time")
    carb_data = normalize(carb_data, "time")
    smbg_data = normalize(smbg_data, "time")

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
    weight_data = {"value": [], "date": []}
    height_data = {"value": [], "date": []}
    for _, row in hw.iterrows():
        if pd.notna(row["Weight"]):
            w = row["Weight"]
            unit = row["WeightUnits"]
            if unit in ["lbs", "pounds", "lb"]:
                w = w * 0.453592
            elif unit in ["kg", "kilograms", "kg."]:
                pass
            else:
                print(f"Unknown weight units: {unit}, assuming kg.")
            weight_data["value"].append(w)
            weight_data["date"].append(row["WeightAssessDt"])
        if pd.notna(row["Height"]):
            h = row["Height"]
            unit = row["HeightUnits"]
            if unit in ["cm", "centimeters", "cm."]:
                pass
            elif unit in ["inches", "in", "inch"]:
                h = h * 2.54
            else:
                print(f"Unknown height units: {unit}, assuming cm.")

            height_data["value"].append(h)
            height_data["date"].append(row["HeightAssessDt"])

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
                "device": "iLet pump",
                "insulin": ins_string,
            },
            "bolus": {
                "unit": "U",
                "description": "The amount of insulin delivered in a bolus, meal and correction, in units",
                "device": "iLet pump",
                "insulin": ins_string,
            },
            "carb_category": {
                "unit": "String",
                "description": (
                    "User announced carbohydrate intake category associated with bolus. "
                    "Options are: Less, Typical, or More"
                ),
            },
            "smbg": {
                "unit": "mg/dL",
                "description": "Self-Monitoring Blood Glucose readings",
                "device": "Unknown",
                "precision": 1,
            },
            "height": {
                "unit": "cm",
                "description": "Height of the subject on the specific date",
            },
            "weight": {
                "unit": "kg",
                "description": "Weight of the subject on the specific date",
            },
        },
        "unique_id": subject_id,
        "cgm": {"time": cgm_data["time"].tolist(), "value": cgm_data["CGMVal"].tolist()},
        "basal_rate": {
            "time": basal_data["time"].tolist(),
            "value": basal_data["BasalRate"].tolist(),
        },
        "bolus": {
            "time": bolus_data["time"].tolist(),
            "value": bolus_data["BolusAmount"].tolist(),
        },
        "carb_category": {
            "time": carb_data["time"].tolist(),
            "value": carb_data["MealSize"].tolist(),
        },
        "smbg": {"time": smbg_data["time"].tolist(), "value": smbg_data["BGMVal"].tolist()},
        "height": height_data,
        "weight": weight_data,
    }

    with open(output_file, "w") as f:
        json.dump(output, f, indent=2, default=str)


def process_all_iobp2(data_source, output_dir):
    """Process all IOBP2 subjects from the source directory."""
    os.makedirs(output_dir, exist_ok=True)
    prep = preprocess_iobp2(data_source)

    dset_all = prep["dset_all"]
    insulin_all = prep["insulin_all"]
    smbg_all = prep["smbg_all"]
    height_weight = prep["height_weight"]
    subjects = prep["subjects"]

    for subject_id in subjects:
        dset = dset_all[dset_all["PtID"] == subject_id].copy()
        insulin = insulin_all[insulin_all["PtID"] == subject_id].copy()
        smbg = smbg_all[smbg_all["PtID"] == subject_id].copy()
        hw = height_weight[height_weight["PtID"] == subject_id].copy()

        output_file = os.path.join(output_dir, f"IOBP2_subject_{subject_id}.json")
        process_subj_iobp2(dset, insulin, smbg, hw, subject_id, output_file)

    return len(subjects)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Process all IOBP2 subjects.")
    parser.add_argument("--source", required=True, help="Path to IOBP2 data directory.")
    parser.add_argument("--output", required=True, help="Output directory for JSON files.")
    args = parser.parse_args()

    count = process_all_iobp2(args.source, args.output)
    print(f"Processed {count} subjects.")
