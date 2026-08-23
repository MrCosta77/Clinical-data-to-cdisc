"""Generate a deterministic, internally consistent synthetic EDC cohort."""

from datetime import datetime, timedelta
from pathlib import Path
import random

import pandas as pd


NUM_PATIENTS = 50
SITES = ["701", "702", "703", "704"]
STUDY_START_DATE = datetime(2023, 1, 1)
STUDY_DURATION_DAYS = 84
RANDOM_SEED = 20260821
RAW_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"


def _date(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%d")


def generate_patients(rng: random.Random) -> pd.DataFrame:
    patients = []
    arms = ["Placebo", "Active Drug 50mg"]

    for number in range(1, NUM_PATIENTS + 1):
        site = rng.choice(SITES)
        subject_id = f"{site}-{number:03d}"
        dob = STUDY_START_DATE - timedelta(days=rng.randint(65 * 365, 85 * 365))
        consent_date = STUDY_START_DATE + timedelta(days=rng.randint(0, 30))
        randomized = rng.random() >= 0.10

        if not randomized:
            arm = "Not Randomized"
            enrolled = "N"
            disposition = "SCREEN FAILURE"
            disposition_reason = "SCREEN FAILURE"
            study_end_date = consent_date + timedelta(days=rng.randint(0, 7))
        else:
            arm = rng.choice(arms)
            enrolled = "Y"
            if rng.random() < 0.15:
                disposition = "EARLY TERMINATION"
                disposition_reason = rng.choice(
                    ["ADVERSE EVENT", "WITHDRAWAL BY SUBJECT", "LOST TO FOLLOW-UP"]
                )
                study_end_date = consent_date + timedelta(days=rng.randint(20, 70))
            else:
                disposition = "COMPLETED"
                disposition_reason = "COMPLETED"
                study_end_date = consent_date + timedelta(days=STUDY_DURATION_DAYS)

        patients.append(
            {
                "SUBJ_ID": subject_id,
                "SITE": site,
                "BRTH_DT": dob.strftime("%d/%m/%Y"),
                "GENDER": rng.choice(["M", "F", "Male", "Female"]),
                "RACE_TXT": rng.choices(
                    ["White", "Black", "Asian", "Other"],
                    weights=[0.70, 0.15, 0.10, 0.05],
                )[0],
                "ICF_DAT": consent_date.strftime("%Y-%m-%d"),
                "STUDY_END_DAT": study_end_date.strftime("%Y-%m-%d"),
                "RANDOMIZED_ARM": arm,
                "ENROLLED": enrolled,
                "DISPOSITION": disposition,
                "DISPOSITION_REASON": disposition_reason,
            }
        )

    return pd.DataFrame(patients)


def generate_vitals(patients: pd.DataFrame, rng: random.Random) -> pd.DataFrame:
    vitals = []
    planned_days = {1: 0, 2: 30, 3: 60}

    for _, subject in patients.iterrows():
        consent = _date(subject["ICF_DAT"])
        study_end = _date(subject["STUDY_END_DAT"])
        visit_numbers = [1] if subject["RANDOMIZED_ARM"] == "Not Randomized" else [1, 2, 3]

        for visit_num in visit_numbers:
            planned = consent + timedelta(days=planned_days[visit_num])
            if visit_num > 1 and planned > study_end:
                continue
            jitter = rng.randint(0, 1) if visit_num == 1 else rng.randint(-2, 2)
            visit_date = planned + timedelta(days=jitter)
            visit_date = min(max(visit_date, consent), study_end)
            vitals.append(
                {
                    "PT_ID": subject["SUBJ_ID"],
                    "VISIT": f"Visit {visit_num}",
                    "VISIT_NUM": visit_num,
                    "VS_DATE": visit_date.strftime("%d-%b-%Y"),
                    "SYS_BP": rng.randint(110, 160),
                    "DIA_BP": rng.randint(70, 100),
                    "HR_BPM": rng.randint(60, 100),
                    "WEIGHT_KG": round(rng.uniform(55.0, 95.0), 1),
                }
            )

    return pd.DataFrame(vitals)


def generate_adverse_events(patients: pd.DataFrame, rng: random.Random) -> pd.DataFrame:
    ae_dictionary = [
        "Headache",
        "Nausea",
        "Dizziness",
        "Insomnia",
        "Fatigue",
        "Application site erythema",
    ]
    randomized = patients.loc[patients["RANDOMIZED_ARM"] != "Not Randomized"]
    sampled = randomized.sample(frac=0.60, random_state=RANDOM_SEED)
    events = []

    for _, subject in sampled.iterrows():
        consent = _date(subject["ICF_DAT"])
        study_end = _date(subject["STUDY_END_DAT"])
        for _ in range(rng.randint(1, 3)):
            start = consent + timedelta(days=rng.randint(0, (study_end - consent).days))
            end = min(start + timedelta(days=rng.randint(1, 14)), study_end)
            events.append(
                {
                    "ID": subject["SUBJ_ID"],
                    "AE_TERM": rng.choice(ae_dictionary),
                    "START": start.strftime("%d/%m/%Y"),
                    "END": end.strftime("%d/%m/%Y") if rng.random() >= 0.10 else "",
                    "SEV": rng.choice(["MILD", "MODERATE", "SEVERE"]),
                    "RELATED": rng.choice(["Y", "N"]),
                    "SERIOUS": "Y" if rng.random() < 0.05 else "N",
                }
            )

    return pd.DataFrame(events)


def main() -> None:
    rng = random.Random(RANDOM_SEED)
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    dm = generate_patients(rng)
    vs = generate_vitals(dm, rng)
    ae = generate_adverse_events(dm, rng)
    dm.to_csv(RAW_DIR / "raw_demog.csv", index=False, lineterminator="\n")
    vs.to_csv(RAW_DIR / "raw_vitals.csv", index=False, lineterminator="\n")
    ae.to_csv(RAW_DIR / "raw_ae.csv", index=False, lineterminator="\n")
    print(f"Generated {len(dm)} subjects, {len(vs)} visits and {len(ae)} adverse events.")


if __name__ == "__main__":
    main()
