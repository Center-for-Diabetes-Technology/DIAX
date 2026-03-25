import argparse
import json
import os
from typing import Iterable, List, Optional
import pandas as pd
import tqdm


def _read_parquet(source_dir: str, study_name: str, data_type: str) -> pd.DataFrame:
    """Read a single study/data_type parquet dataset."""
    path = os.path.join(source_dir, f"study_name={study_name}", f"data_type={data_type}")
    if not os.path.isdir(path):
        raise FileNotFoundError(f"Missing dataset directory: {path}")
    # Read per-data_type to avoid schema conflicts across partitions.
    return pd.read_parquet(path)


def process_subj(cgm_data, basal_data, bolus_data, subject_id, output_file):
    """Process a single subject's data and write to DIAX format."""

    def normalize(df, col):
        df = df.copy()
        df.loc[:, 'time'] = df[col].dt.strftime("%Y-%m-%d %H:%M:%S")
        return df.sort_values(col).reset_index(drop=True)
    
    # ensure datetime columns are in datetime format
    cgm_data = normalize(cgm_data, 'datetime')
    basal_data = normalize(basal_data, 'datetime')
    bolus_data = normalize(bolus_data, 'datetime')

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
                "device": "UNKOWN",
                "insulin": "UNKOWN",
            },
            "bolus": {
                "unit": "U",
                "description": "The amount of insulin delivered in a bolus, meal and correction, in units",
                "device": "UNKOWN",
                "insulin": "UNKOWN",
            },
            "smbg": {
                "unit": "mg/dL",
                "description": "Self-Monitored Blood Glucose readings",
                "device": "UNKOWN",
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
        "cgm": {"time": cgm_data["time"].tolist(), "value": cgm_data["cgm"].tolist()},
        "basal_rate": {
            "time": basal_data["time"].tolist(),
            "value": basal_data["basal_rate"].tolist(),
        },
        "bolus": {
            "time": bolus_data["time"].tolist(),
            "value": bolus_data["bolus"].tolist(),
        },
    }

    with open(output_file, "w") as f:
        json.dump(output, f, indent=2, default=str)


def convert_study(source_dir: str, output_dir: str, study_name: str) -> None:
    """Convert one study into standardized CSV outputs."""
    study_out = os.path.join(output_dir, study_name)
    os.makedirs(study_out, exist_ok=True)

    cgm_all = _read_parquet(source_dir, study_name, 'cgm')
    basal_all = _read_parquet(source_dir, study_name, 'basal')
    bolus_all = _read_parquet(source_dir, study_name, 'bolus')

    # Find patients with all three data types.
    pt_ids = set(cgm_all['patient_id']).intersection(basal_all['patient_id']).intersection(bolus_all['patient_id'])

    for pt_id in tqdm.tqdm(pt_ids, desc=f"Processing subjects for study: {study_name}"):
        cgm = cgm_all[cgm_all['patient_id'] == pt_id].copy()
        basal = basal_all[basal_all['patient_id'] == pt_id].copy()
        bolus = bolus_all[bolus_all['patient_id'] == pt_id].copy()

        output_file = os.path.join(study_out, f"subject_{pt_id}.json")
        process_subj(cgm, basal, bolus, pt_id, output_file)

        
def convert_all(source_dir: str, output_dir: str, studies: Optional[Iterable[str]]) -> int:
    """Convert all requested studies. Returns the number of studies processed."""

    if studies is None:  # No specific studies provided, process all found in the source directory.
        studies = []
        for entry in os.listdir(source_dir):
            if entry.startswith("study_name="):
                studies.append(entry.split("=", 1)[1])

    count = 0
    for study_name in studies:
        convert_study(source_dir, output_dir, study_name)
        count += 1

    return count


def _parse_studies(value: Optional[str]) -> Optional[List[str]]:
    """Parse comma-separated study list from CLI (or return None)."""
    if not value:
        return None
    return [item.strip() for item in value.split(",") if item.strip()]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Convert BabelBetes parquet outputs into standardized CSV histories."
    )
    parser.add_argument(
        "--source",
        default="/home/elliottp/data/data_raw/babelbetes_out",
        help="Path to BabelBetes parquet root.",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output directory for standardized history CSVs.",
    )
    parser.add_argument(
        "--studies",
        default=None,
        help="Comma-separated list of study names (default: all).",
    )

    args = parser.parse_args()
    study_list = _parse_studies(args.studies)

    processed = convert_all(args.source, args.output, study_list)
    print(f"Processed {processed} studies.")
