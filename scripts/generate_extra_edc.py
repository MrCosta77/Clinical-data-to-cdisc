"""Generate the remaining synthetic EDC domains from the cohort timeline."""

from datetime import datetime, timedelta
from pathlib import Path
import random

import pandas as pd


RANDOM_SEED = 20260822
RAW_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"


def _date(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%d")


def _clamp(value: datetime, lower: datetime, upper: datetime) -> datetime:
    return min(max(value, lower), upper)


def generate_extras() -> None:
    rng = random.Random(RANDOM_SEED)
    dm_path = RAW_DIR / "raw_demog.csv"
    vs_path = RAW_DIR / "raw_vitals.csv"
    if not dm_path.exists() or not vs_path.exists():
        raise FileNotFoundError("Run scripts/generate_raw_edc.py before this generator.")

    dm = pd.read_csv(dm_path, dtype={"SITE": str})
    visits = pd.read_csv(vs_path)
    ex_records, lb_records, cm_records, mh_records, eg_records = [], [], [], [], []
    cm_meds = ["Paracetamol", "Ibuprofen", "Omeprazole", "Lisinopril", "Atorvastatin", "Aspirin"]
    lab_tests = ["Glucose", "Hemoglobin", "ALT", "AST"]
    mh_conditions = ["Hypertension", "Type 2 Diabetes", "Asthma", "Depression", "Hyperlipidemia", "Osteoarthritis"]
    eg_tests = ["Heart Rate", "QT Duration", "RR Duration"]

    for _, subject in dm.iterrows():
        if subject["RANDOMIZED_ARM"] == "Not Randomized":
            continue

        subject_id = subject["SUBJ_ID"]
        consent = _date(subject["ICF_DAT"])
        study_end = _date(subject["STUDY_END_DAT"])
        subject_visits = visits.loc[visits["PT_ID"] == subject_id].sort_values("VISIT_NUM")

        actual_treatment = subject["RANDOMIZED_ARM"]
        if rng.random() < 0.05:
            actual_treatment = "Placebo" if actual_treatment == "Active Drug 50mg" else "Active Drug 50mg"
        dose_start = min(consent + timedelta(days=rng.randint(1, 5)), study_end)
        ex_records.append(
            {
                "PATIENT": subject_id,
                "TREATMENT": actual_treatment,
                "DOSE": 50 if actual_treatment == "Active Drug 50mg" else 0,
                "UNIT": "mg",
                "START_DATE": dose_start.strftime("%d/%m/%Y"),
                "END_DATE": study_end.strftime("%d/%m/%Y") if rng.random() >= 0.05 else "",
            }
        )

        for _, visit in subject_visits.iterrows():
            visit_date = datetime.strptime(visit["VS_DATE"], "%d-%b-%Y")
            lab_date = _clamp(visit_date + timedelta(days=rng.randint(-2, 2)), consent, study_end)
            for test in lab_tests:
                if test == "Glucose":
                    result, unit = round(rng.uniform(70.0, 120.0), 1), rng.choice(["mg/dL", "MG/DL"])
                elif test == "Hemoglobin":
                    result, unit = round(rng.uniform(11.0, 16.5), 1), "g/dL"
                else:
                    result, unit = rng.randint(10, 45), "U/L"
                lb_records.append(
                    {
                        "SUBJ": subject_id,
                        "VISIT_NAM": visit["VISIT"],
                        "VISIT_NUM": int(visit["VISIT_NUM"]),
                        "LAB_DAT": lab_date.strftime("%Y-%m-%d"),
                        "TEST_NAME": test,
                        "RESULT": result,
                        "UNIT": unit,
                    }
                )

        for _ in range(rng.randint(0, 3)):
            cm_start = consent - timedelta(days=rng.randint(10, 365))
            # ONGOING is assessed at the subject's study_end boundary. The SDTM
            # transform therefore uses DM.RFENDTC as CMENTPT, not as CMENDTC.
            ongoing = rng.random() < 0.40
            cm_end = None if ongoing else consent + timedelta(days=rng.randint(10, max(10, (study_end - consent).days)))
            if cm_end:
                cm_end = min(cm_end, study_end)
            cm_records.append(
                {
                    "SUBJECT": subject_id,
                    "MEDICATION": rng.choice(cm_meds),
                    "DOSE": rng.choice(["10 mg", "20 mg", "500 mg", "1000 mg"]),
                    "START_DT": cm_start.strftime("%d/%m/%Y"),
                    "END_DT": cm_end.strftime("%d/%m/%Y") if cm_end else "",
                    "ONGOING": "N" if cm_end else "Y",
                }
            )

        for _ in range(rng.randint(0, 2)):
            mh_records.append(
                {
                    "SUBJECT": subject_id,
                    "CONDITION": rng.choice(mh_conditions),
                    "DIAGNOSIS_DATE": (consent - timedelta(days=rng.randint(365, 5000))).strftime("%Y-%m-%d"),
                }
            )

        baseline = subject_visits.iloc[0]
        eg_date = datetime.strptime(baseline["VS_DATE"], "%d-%b-%Y")
        for test in eg_tests:
            if test == "Heart Rate":
                result, unit = rng.randint(60, 100), "beats/min"
            elif test == "QT Duration":
                result, unit = rng.randint(350, 450), "msec"
            else:
                result, unit = rng.randint(600, 1000), "msec"
            eg_records.append(
                {
                    "SUBJECT": subject_id,
                    "VISIT_NAM": baseline["VISIT"],
                    "VISIT_NUM": int(baseline["VISIT_NUM"]),
                    "TEST_NAME": test,
                    "RESULT": result,
                    "UNIT": unit,
                    "DATE": eg_date.strftime("%Y-%m-%d"),
                }
            )

    outputs = {
        "raw_exposure.csv": ex_records,
        "raw_lab.csv": lb_records,
        "raw_conmeds.csv": cm_records,
        "raw_mh.csv": mh_records,
        "raw_ecg.csv": eg_records,
    }
    for filename, records in outputs.items():
        pd.DataFrame(records).to_csv(
            RAW_DIR / filename,
            index=False,
            lineterminator="\n",
        )
        print(f"Generated {filename}: {len(records)} records")


if __name__ == "__main__":
    generate_extras()
