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


def preprocess_dclp5(data_source):
    """Load and pre-process DCLP5 source tables."""
    cgm1 = pd.read_csv(os.path.join(data_source, "DexcomClarityCGM.txt"), sep="|")
    cgm1.rename(columns={"DataDtTm_adj": "DataDtTm_adjusted"}, inplace=True)
    cgm2 = pd.read_csv(os.path.join(data_source, "DCLP5TandemCGMDATAGXB_b.txt"), sep="|")
    cgm2.rename(columns={"CGMValue": "CGM"}, inplace=True)
    cgm3 = pd.read_csv(os.path.join(data_source, "OtherCGM.txt"), sep="|")
    cgm_all = pd.concat([cgm1, cgm2, cgm3])

    basal_all = pd.read_csv(os.path.join(data_source, "DCLP5TandemBASALRATECHG_b.txt"), sep="|")
    bolus_all = pd.read_csv(
        os.path.join(data_source, "DCLP5TandemBolus_Completed_Combined_b.txt"), sep="|"
    )

    smbg_all = pd.read_csv(os.path.join(data_source, "RocheMeter.txt"), sep="|")

    phys_all = pd.read_csv(os.path.join(data_source, "DiabPhysExam.txt"), sep="|")
    insulin_all = pd.read_csv(os.path.join(data_source, "Insulin.txt"), sep="|")
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
        "cgm_all": cgm_all,
        "basal_all": basal_all,
        "bolus_all": bolus_all,
        "smbg_all": smbg_all,
        "phys_all": phys_all,
        "insulin_all": insulin_all,
        "subjects": subjects,
    }


def process_subj_dclp5(cgm, basal, bolus, insulin, smbg, phys, subject_id, output_file):
    """Process a single DCLP5 subject and write a DIAX JSON file."""
    cgm.loc[:, "time"] = cgm["DataDtTm_adjusted"].fillna(cgm["DataDtTm"]).apply(_parse_mixed)
    cgm_data = cgm

    # Basal
    basal.loc[:, "time"] = basal["DataDtTm_adjusted"].fillna(basal["DataDtTm"]).apply(_parse_mixed)
    basal_data = basal

    # Bolus
    bolus.loc[:, "time"] = bolus["DataDtTm_adjusted"].fillna(bolus["DataDtTm"]).apply(_parse_mixed)
    bolus_data = bolus

    # SMBG
    smbg.loc[:, "time"] = pd.to_datetime(smbg["DataDtTm"], format="%Y-%m-%d %H:%M:%S")
    smbg_data = smbg

    def normalize(df, col):
        df = df.copy()
        df.loc[:, col] = df[col].dt.strftime("%Y-%m-%d %H:%M:%S")
        return df.sort_values(col).reset_index(drop=True)

    cgm_data = normalize(cgm_data, "time")
    basal_data = normalize(basal_data, "time")
    bolus_data = normalize(bolus_data, "time")
    smbg_data = normalize(smbg_data, "time")

    start_times = [
        cgm_data["time"].min(),
        basal_data["time"].min(),
        bolus_data["time"].min(),
        smbg_data["time"].min(),
    ]
    start_time = min(start_times)

    ins_string = "UNKNOWN"
    if len(insulin) > 1:
        start_date = start_time.strftime("%Y-%m-%d")
        dates = (
            insulin["InsTypeStartDt"].dt.strftime("%Y-%m-%d").fillna(start_date).tolist()
        )
        ins = insulin["ParentInsulinListID"].tolist()

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
        ins_string = insulin["ParentInsulinListID"].iloc[0]

    # Get height and weight from phys exam data
    weight = phys["Weight"].values[0]
    height = phys["Height"].values[0]

    # correct units if needed
    weight_units = phys["WeightUnits"].values[0].lower().strip()
    if weight_units in ["lbs", "pounds", "lb"]:
        weight = weight * 0.453592
    elif weight_units in ["kg", "kilograms", "kg."]:
        pass
    else:
        print(f"Unknown weight units: {weight_units}, assuming kg.")

    height_units = phys["HeightUnits"].values[0].lower().strip()
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
            "smbg": {
                "unit": "mg/dL",
                "description": "Self-Monitored Blood Glucose readings",
                "device": "Roche Meter",
                "precision": 1,
            },
            "height": {
                "unit": "cm",
                "description": "Height of the subject at the start of the study",
            },
            "weight": {
                "unit": "kg",
                "description": "Weight of the subject at the start of the study",
            },
        },
        "unique_id": subject_id,
        "height": {"time": start_time, "value": height},
        "weight": {"time": start_time, "value": weight},
        "cgm": {"time": cgm_data["time"].tolist(), "value": cgm_data["CGM"].tolist()},
        "basal_rate": {
            "time": basal_data["time"].tolist(),
            "value": basal_data["CommandedBasalRate"].tolist(),
        },
        "bolus": {
            "time": bolus_data["time"].tolist(),
            "value": bolus_data["BolusAmount"].tolist(),
        },
        "smbg": {"time": smbg_data["time"].tolist(), "value": smbg_data["BG"].tolist()},
    }

    with open(output_file, "w") as f:
        json.dump(output, f, indent=2, default=str)


def process_all_dclp5(data_source, output_dir):
    """Process all DCLP5 subjects from the source directory."""
    os.makedirs(output_dir, exist_ok=True)
    prep = preprocess_dclp5(data_source)

    cgm_all = prep["cgm_all"]
    basal_all = prep["basal_all"]
    bolus_all = prep["bolus_all"]
    insulin_all = prep["insulin_all"]
    smbg_all = prep["smbg_all"]
    phys_all = prep["phys_all"]
    subjects = prep["subjects"]

    for subject_id in subjects:
        cgm = cgm_all[cgm_all["PtID"] == subject_id].copy()
        basal = basal_all[basal_all["PtID"] == subject_id].copy()
        bolus = bolus_all[bolus_all["PtID"] == subject_id].copy()
        insulin = insulin_all[insulin_all["PtID"] == subject_id].copy()
        smbg = smbg_all[smbg_all["PtID"] == subject_id].copy()
        phys = phys_all[phys_all["PtID"] == subject_id].copy()

        output_file = os.path.join(output_dir, f"DCLP5_subject_{subject_id}.json")
        process_subj_dclp5(cgm, basal, bolus, insulin, smbg, phys, subject_id, output_file)

    return len(subjects)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Process all DCLP5 subjects.")
    parser.add_argument("--source", required=True, help="Path to DCLP5 data directory.")
    parser.add_argument("--output", required=True, help="Output directory for JSON files.")
    args = parser.parse_args()

    count = process_all_dclp5(args.source, args.output)
    print(f"Processed {count} subjects.")
