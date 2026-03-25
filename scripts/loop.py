import json
import os
import glob
import logging
from datetime import timezone, timedelta

import numpy as np
import pandas as pd


logger = logging.getLogger(__name__)


CGM_FILES = [
    "LOOPDeviceCGM1.txt",
    "LOOPDeviceCGM2.txt",
    "LOOPDeviceCGM3.txt",
    "LOOPDeviceCGM4.txt",
    "LOOPDeviceCGM5.txt",
    "LOOPDeviceCGM6.txt",
]

BASAL_FILES = [
    "LOOPDeviceBasal1.txt",
    "LOOPDeviceBasal2.txt",
    "LOOPDeviceBasal3.txt",
]


def preprocess_loop(data_source):
    """Load and pre-process Loop source tables.

    Creates per-subject pickles for CGM and basal to avoid re-loading the
    full tables for each subject.
    """

    # CGM (chunked per subject)
    cgm_pkls = glob.glob(os.path.join(data_source, "LOOP_CGM_*.pkl"))
    if not cgm_pkls:
        for fname in CGM_FILES:
            path = os.path.join(data_source, fname)
            if not os.path.exists(path):
                continue
            chunk = pd.read_csv(
                path,
                sep="|",
                usecols=["PtID", "UTCDtTm", "CGMVal", "Units", "OriginDeviceManufact", "OriginDeviceModel"],
            )

            logger.info("Processing CGM %s", fname)
            for subj, df_subj in chunk.groupby("PtID"):
                subj_path = os.path.join(data_source, f"LOOP_CGM_{int(subj)}.pkl")
                if os.path.exists(subj_path):
                    df_existing = pd.read_pickle(subj_path)
                    pd.concat([df_existing, df_subj], ignore_index=True).to_pickle(subj_path)
                else:
                    df_subj.to_pickle(subj_path)
        cgm_pkls = glob.glob(os.path.join(data_source, "LOOP_CGM_*.pkl"))

    # Basal (chunked per subject)
    basal_pkls = glob.glob(os.path.join(data_source, "LOOP_BASAL_*.pkl"))
    if not basal_pkls:
        for fname in BASAL_FILES:
            path = os.path.join(data_source, fname)
            if not os.path.exists(path):
                continue
            chunk = pd.read_csv(
                path,
                sep="|",
                usecols=["PtID", "UTCDtTm", "Rate", "OriginDeviceManufact", "OriginDeviceModel"],
            )
            logger.info("Processing basal chunk from %s", fname)
            for subj, df_subj in chunk.groupby("PtID"):
                subj_path = os.path.join(data_source, f"LOOP_BASAL_{int(subj)}.pkl")
                if os.path.exists(subj_path):
                    df_existing = pd.read_pickle(subj_path)
                    pd.concat([df_existing, df_subj], ignore_index=True).to_pickle(subj_path)
                else:
                    df_subj.to_pickle(subj_path)
        basal_pkls = glob.glob(os.path.join(data_source, "LOOP_BASAL_*.pkl"))

    cgm_subjs = {
        int(os.path.basename(f).replace("LOOP_CGM_", "").replace(".pkl", ""))
        for f in cgm_pkls
    }
    basal_subjs = {
        int(os.path.basename(f).replace("LOOP_BASAL_", "").replace(".pkl", ""))
        for f in basal_pkls
    }

    subjects = sorted(cgm_subjs.intersection(basal_subjs))

    return {
        "subjects": subjects,
        "data_source": data_source,
    }


def _load_pt_timezone_offsets(data_source):
    """Load per-subject timezone offsets (hours) from PtRoster.txt."""

    roster_path = os.path.join(data_source, "PtRoster.txt")
    if not os.path.exists(roster_path):
        logger.warning("PtRoster.txt not found in %s; using UTC.", data_source)
        return {}

    roster = pd.read_csv(
        roster_path,
        sep="|",
        usecols=["PtID", "PtTimezoneOffset"],
    )
    roster = roster.dropna(subset=["PtID"]).copy()
    roster["PtID"] = roster["PtID"].astype(int)
    return dict(zip(roster["PtID"], roster["PtTimezoneOffset"]))


def _read_subject_table(path, usecols, subject_id, chunksize=500_000):
    """Read a delimited file in chunks and filter by subject ID."""

    if not os.path.exists(path):
        return pd.DataFrame(columns=usecols)

    frames = []
    for chunk in pd.read_csv(path, sep="|", usecols=usecols, chunksize=chunksize):
        chunk = chunk[chunk["PtID"] == subject_id]
        if len(chunk):
            frames.append(chunk)

    if frames:
        return pd.concat(frames, ignore_index=True)

    return pd.DataFrame(columns=usecols)


def _parse_time_utc(df, time_col="UTCDtTm"):
    """Parse UTC timestamps, drop invalid rows, and return a copy."""

    df = df.copy()
    df.loc[:, "time"] = pd.to_datetime(df[time_col], errors="coerce", utc=True)
    df = df[df["time"].notna()].copy()
    return df


def _apply_timezone(series, offset_hours):
    """Convert UTC timestamps to a fixed-offset timezone when provided."""

    if offset_hours is None or pd.isna(offset_hours):
        return series.tz_localize("UTC")
    tz = timezone(timedelta(hours=float(offset_hours)))
    converted = series.dt.tz_convert(tz)
    return converted


def _convert_glucose_to_mgdl(values, units):
    """Convert glucose values to mg/dL when units are mmol/L."""

    unit_norm = units.astype(str).str.lower().str.strip()
    return np.where(
        unit_norm.isin(["mmol/l"]),
        (values.astype(float) * 18.0182).round(),
        values.astype(float),
    )


def _infer_device(mfg_series, model_series):
    """Infer device string from manufacturer and model columns."""

    mfg = mfg_series.dropna().astype(str).str.strip()
    model = model_series.dropna().astype(str).str.strip()

    mfg_val = mfg[mfg != ""].iloc[0] if (mfg != "").any() else ""
    model_val = model[model != ""].iloc[0] if (model != "").any() else ""

    if mfg_val and model_val:
        return f"{mfg_val} ({model_val})"
    if mfg_val:
        return mfg_val
    if model_val:
        return model_val
    return "UNKNOWN"


def _iso_with_colon(series):
    """Format timestamps as ISO 8601 with timezone colon."""

    return (
        series.dt.strftime("%Y-%m-%d %H:%M:%S %Z").tolist()
    )


def _start_end_duration(series_list):
    """Compute start, end, and duration (days) for all time series."""

    times = [s for s in series_list if len(s)]
    if not times:
        return None, None, None

    start_time = min(s.min() for s in times)
    end_time = max(s.max() for s in times)
    duration_days = (end_time - start_time).total_seconds() / 86400.0
    return start_time, end_time, duration_days


def process_subj_loop(cgm, basal, bolus, bgm, carbs, subject_id, output_file, tz_offset_hours=None):
    """Process a single Loop subject and write a DIAX JSON file."""
    logger.info("Processing subject %s", subject_id)

    cgm = _parse_time_utc(cgm)
    bgm = _parse_time_utc(bgm)
    bolus = _parse_time_utc(bolus)
    basal = _parse_time_utc(basal)
    carbs = _parse_time_utc(carbs)

    cgm["time"] = _apply_timezone(cgm["time"], tz_offset_hours)
    bgm["time"] = _apply_timezone(bgm["time"], tz_offset_hours)
    bolus["time"] = _apply_timezone(bolus["time"], tz_offset_hours)
    basal["time"] = _apply_timezone(basal["time"], tz_offset_hours)
    carbs["time"] = _apply_timezone(carbs["time"], tz_offset_hours)

    cgm.loc[:, "value_mgdl"] = _convert_glucose_to_mgdl(cgm["CGMVal"], cgm["Units"])
    bgm.loc[:, "value_mgdl"] = _convert_glucose_to_mgdl(bgm["BGMVal"], bgm["Units"])

    bolus.loc[:, "Normal"] = pd.to_numeric(bolus["Normal"], errors="coerce").fillna(0.0)
    bolus.loc[:, "Extended"] = pd.to_numeric(bolus["Extended"], errors="coerce").fillna(0.0)
    bolus.loc[:, "value_u"] = bolus["Normal"] + bolus["Extended"]

    basal.loc[:, "value_u_hr"] = pd.to_numeric(basal["Rate"], errors="coerce")

    carbs.loc[:, "CarbsNet"] = pd.to_numeric(carbs["CarbsNet"], errors="coerce")
    carb_units = carbs["CarbUnits"].astype(str).str.lower().str.strip()
    carbs.loc[:, "value_g"] = np.where(
        carb_units.isin(["g", "gram", "grams", ""]),
        carbs["CarbsNet"],
        carbs["CarbsNet"],
    )

    cgm_device = _infer_device(cgm["OriginDeviceManufact"], cgm["OriginDeviceModel"])
    bgm_device = _infer_device(bgm["OriginDeviceManufact"], bgm["OriginDeviceModel"])
    bolus_device = _infer_device(bolus["OriginDeviceManufact"], bolus["OriginDeviceModel"])
    basal_device = _infer_device(basal["OriginDeviceManufact"], basal["OriginDeviceModel"])

    insulin_device = bolus_device if bolus_device != "UNKNOWN" else basal_device
    insulin_device = f"Loop: {insulin_device if insulin_device else 'UNKNOWN'}"

    start_time, end_time, duration_days = _start_end_duration(
        [
            cgm["time"],
            bgm["time"],
            bolus["time"],
            basal["time"],
            carbs["time"],
        ]
    )

    time_meta = {
        "unit": "ISO 8601",
        "description": "Timestamps in local time with timezone info when available",
    }
    if tz_offset_hours is None or pd.isna(tz_offset_hours):
        time_meta["description"] = "Timestamps in UTC for each measurement"
        time_meta["timezone_offset_hours"] = 0
    else:
        time_meta["timezone_offset_hours"] = float(tz_offset_hours)

    output = {
        "metadata": {
            "unique_id": "id number of the subject",
            "time": time_meta,
            "cgm": {
                "unit": "mg/dL",
                "description": "Continuous Glucose Monitor readings",
                "device": cgm_device,
                "precision": 1,
            },
            "smbg": {
                "unit": "mg/dL",
                "description": "Self-Monitored Blood Glucose readings",
                "device": bgm_device,
                "precision": 1,
            },
            "basal_rate": {
                "unit": "U/hr",
                "description": "Basal insulin rate",
                "device": insulin_device,
            },
            "bolus": {
                "unit": "U",
                "description": "Bolus insulin delivered (normal + extended)",
                "device": insulin_device,
            },
            "carbs": {
                "unit": "g",
                "description": "Carbohydrate intake",
            },
        },
        "unique_id": subject_id,
        "cgm": {"time": _iso_with_colon(cgm["time"]), "value": cgm["value_mgdl"].tolist()},
        "smbg": {"time": _iso_with_colon(bgm["time"]), "value": bgm["value_mgdl"].tolist()},
        "bolus": {"time": _iso_with_colon(bolus["time"]), "value": bolus["value_u"].tolist()},
        "basal_rate": {
            "time": _iso_with_colon(basal["time"]),
            "value": basal["value_u_hr"].tolist(),
        },
        "carbs": {"time": _iso_with_colon(carbs["time"]), "value": carbs["value_g"].tolist()},
    }

    if start_time is not None:
        output["start_date"] = start_time.isoformat()
        output["end_date"] = end_time.isoformat()
        output["duration_in_days"] = duration_days

    with open(output_file, "w") as f:
        json.dump(output, f, indent=2)


def process_all_loop(data_source, output_dir):
    """Process all Loop subjects from the source directory."""

    os.makedirs(output_dir, exist_ok=True)
    prep = preprocess_loop(data_source)
    subjects = prep["subjects"]
    tz_offsets = _load_pt_timezone_offsets(data_source)

    for subject_id in subjects:
        cgm_path = os.path.join(data_source, f"LOOP_CGM_{subject_id}.pkl")
        basal_path = os.path.join(data_source, f"LOOP_BASAL_{subject_id}.pkl")

        if os.path.exists(cgm_path):
            cgm = pd.read_pickle(cgm_path)
        else:
            logger.warning("CGM data not found for subject %s, skipping.", subject_id)
            continue

        if os.path.exists(basal_path):
            basal = pd.read_pickle(basal_path)
        else:
            logger.warning("Basal data not found for subject %s, skipping.", subject_id)
            continue

        bgm = _read_subject_table(
            os.path.join(data_source, "LOOPDeviceBGM.txt"),
            ["PtID", "UTCDtTm", "BGMVal", "Units", "OriginDeviceManufact", "OriginDeviceModel"],
            subject_id,
        )
        bolus = _read_subject_table(
            os.path.join(data_source, "LOOPDeviceBolus.txt"),
            ["PtID", "UTCDtTm", "Normal", "Extended", "OriginDeviceManufact", "OriginDeviceModel"],
            subject_id,
        )
        carbs = _read_subject_table(
            os.path.join(data_source, "LOOPDeviceFood.txt"),
            ["PtID", "UTCDtTm", "CarbsNet", "CarbUnits"],
            subject_id,
        )

        output_file = os.path.join(output_dir, f"LOOP_subject_{subject_id}.json")
        process_subj_loop(
            cgm,
            basal,
            bolus,
            bgm,
            carbs,
            subject_id,
            output_file,
            tz_offset_hours=tz_offsets.get(subject_id),
        )

    return len(subjects)


if __name__ == "__main__":
    import argparse

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s - %(message)s",
    )

    parser = argparse.ArgumentParser(description="Process all Loop subjects.")
    parser.add_argument("--source", required=True, help="Path to Loop data directory (Data Tables).")
    parser.add_argument("--output", required=True, help="Output directory for JSON files.")
    args = parser.parse_args()

    count = process_all_loop(args.source, args.output)
    logger.info("Processed %s subjects.", count)
