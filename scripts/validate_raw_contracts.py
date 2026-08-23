"""Validate the deterministic synthetic EDC inputs before SAS execution."""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RAW_DIR = PROJECT_ROOT / "data" / "raw"
DEFAULT_MANIFEST = DEFAULT_RAW_DIR / "golden_manifest.json"

REQUIRED_COLUMNS = {
    "raw_demog.csv": ["SUBJ_ID", "SITE", "BRTH_DT", "GENDER", "RACE_TXT", "ICF_DAT", "STUDY_END_DAT", "RANDOMIZED_ARM", "ENROLLED", "DISPOSITION", "DISPOSITION_REASON"],
    "raw_ae.csv": ["ID", "AE_TERM", "START", "END", "SEV", "RELATED", "SERIOUS"],
    "raw_vitals.csv": ["PT_ID", "VISIT", "VISIT_NUM", "VS_DATE", "SYS_BP", "DIA_BP", "HR_BPM", "WEIGHT_KG"],
    "raw_exposure.csv": ["PATIENT", "TREATMENT", "DOSE", "UNIT", "START_DATE", "END_DATE"],
    "raw_lab.csv": ["SUBJ", "VISIT_NAM", "VISIT_NUM", "LAB_DAT", "TEST_NAME", "RESULT", "UNIT"],
    "raw_conmeds.csv": ["SUBJECT", "MEDICATION", "DOSE", "START_DT", "END_DT", "ONGOING"],
    "raw_mh.csv": ["SUBJECT", "CONDITION", "DIAGNOSIS_DATE"],
    "raw_ecg.csv": ["SUBJECT", "VISIT_NAM", "VISIT_NUM", "TEST_NAME", "RESULT", "UNIT", "DATE"],
}

SUBJECT_FIELDS = {
    "raw_ae.csv": "ID",
    "raw_vitals.csv": "PT_ID",
    "raw_exposure.csv": "PATIENT",
    "raw_lab.csv": "SUBJ",
    "raw_conmeds.csv": "SUBJECT",
    "raw_mh.csv": "SUBJECT",
    "raw_ecg.csv": "SUBJECT",
}


@dataclass(frozen=True)
class ValidationResult:
    row_counts: dict[str, int]
    sha256: dict[str, str]


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _read_inputs(raw_dir: Path) -> dict[str, pd.DataFrame]:
    frames: dict[str, pd.DataFrame] = {}
    for filename, columns in REQUIRED_COLUMNS.items():
        path = raw_dir / filename
        _require(path.is_file(), f"Required input is missing: {filename}")
        frame = pd.read_csv(path, dtype=str, keep_default_na=False)
        _require(list(frame.columns) == columns, f"{filename}: columns/order do not match the contract")
        _require(not frame.empty, f"{filename}: dataset is empty")
        frames[filename] = frame
    return frames


def _dates(frame: pd.DataFrame, column: str, filename: str, *, optional: bool = False) -> pd.Series:
    values = frame[column].replace("", pd.NA)
    parsed = pd.Series(pd.NaT, index=values.index, dtype="datetime64[ns]")
    formats = (
        (values.str.match(r"^\d{4}-\d{2}-\d{2}$", na=False), "%Y-%m-%d"),
        (values.str.match(r"^\d{2}/\d{2}/\d{4}$", na=False), "%d/%m/%Y"),
        (values.str.match(r"^\d{2}-[A-Za-z]{3}-\d{4}$", na=False), "%d-%b-%Y"),
    )
    for mask, date_format in formats:
        parsed.loc[mask] = pd.to_datetime(values.loc[mask], format=date_format, errors="coerce")
    invalid = values.notna() & parsed.isna()
    _require(not invalid.any(), f"{filename}.{column}: {int(invalid.sum())} invalid date(s)")
    if not optional:
        _require(values.notna().all(), f"{filename}.{column}: missing required date(s)")
    return parsed


def _assert_terms(frame: pd.DataFrame, column: str, allowed: set[str], filename: str) -> None:
    invalid = sorted(set(frame[column]) - allowed)
    _require(not invalid, f"{filename}.{column}: invalid controlled term(s): {invalid}")


def _assert_unique(frame: pd.DataFrame, fields: list[str], filename: str) -> None:
    count = int(frame.duplicated(fields, keep=False).sum())
    _require(count == 0, f"{filename}: {count} rows duplicate key {fields}")


def _validate_manifest(raw_dir: Path, result: ValidationResult, manifest_path: Path) -> None:
    _require(manifest_path.is_file(), f"Golden manifest is missing: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    _require(manifest.get("schema_version") == 1, "Unsupported golden manifest schema")
    for filename in REQUIRED_COLUMNS:
        expected = manifest.get("files", {}).get(filename)
        _require(expected is not None, f"Golden manifest has no entry for {filename}")
        _require(expected["rows"] == result.row_counts[filename], f"{filename}: golden row count changed")
        _require(expected["sha256"] == result.sha256[filename], f"{filename}: golden SHA-256 changed")


def validate_raw_contracts(
    raw_dir: Path = DEFAULT_RAW_DIR,
    *,
    manifest_path: Path | None = DEFAULT_MANIFEST,
) -> ValidationResult:
    """Fail loudly when raw EDC structure, terminology or timeline drifts."""
    raw_dir = Path(raw_dir)
    frames = _read_inputs(raw_dir)
    dm = frames["raw_demog.csv"]

    _assert_unique(dm, ["SUBJ_ID"], "raw_demog.csv")
    _require((dm["SUBJ_ID"].str.strip() != "").all(), "raw_demog.csv.SUBJ_ID: missing key")
    _assert_terms(dm, "GENDER", {"M", "F", "Male", "Female"}, "raw_demog.csv")
    _assert_terms(dm, "RACE_TXT", {"White", "Black", "Asian", "Other"}, "raw_demog.csv")
    _assert_terms(dm, "ENROLLED", {"Y", "N"}, "raw_demog.csv")
    _assert_terms(dm, "RANDOMIZED_ARM", {"Placebo", "Active Drug 50mg", "Not Randomized"}, "raw_demog.csv")
    _assert_terms(dm, "DISPOSITION", {"COMPLETED", "EARLY TERMINATION", "SCREEN FAILURE"}, "raw_demog.csv")

    birth = _dates(dm, "BRTH_DT", "raw_demog.csv")
    consent = _dates(dm, "ICF_DAT", "raw_demog.csv")
    end = _dates(dm, "STUDY_END_DAT", "raw_demog.csv")
    _require((birth < consent).all(), "raw_demog.csv: birth must precede consent")
    _require((end >= consent).all(), "raw_demog.csv: study end precedes consent")
    bounds = pd.DataFrame({"start": consent.values, "end": end.values}, index=dm["SUBJ_ID"])

    subject_ids = set(dm["SUBJ_ID"])
    for filename, field in SUBJECT_FIELDS.items():
        unknown = sorted(set(frames[filename][field]) - subject_ids)
        _require(not unknown, f"{filename}: unknown subject key(s): {unknown[:5]}")

    ae = frames["raw_ae.csv"]
    _assert_terms(ae, "SEV", {"MILD", "MODERATE", "SEVERE"}, "raw_ae.csv")
    _assert_terms(ae, "RELATED", {"Y", "N"}, "raw_ae.csv")
    _assert_terms(ae, "SERIOUS", {"Y", "N"}, "raw_ae.csv")
    ae_start = _dates(ae, "START", "raw_ae.csv")
    ae_end = _dates(ae, "END", "raw_ae.csv", optional=True).fillna(ae_start)
    _require((ae_end >= ae_start).all(), "raw_ae.csv: END precedes START")

    visits = frames["raw_vitals.csv"]
    _assert_unique(visits, ["PT_ID", "VISIT_NUM"], "raw_vitals.csv")
    visit_dates = _dates(visits, "VS_DATE", "raw_vitals.csv")
    visit_numbers = pd.to_numeric(visits["VISIT_NUM"], errors="coerce")
    _require(visit_numbers.notna().all(), "raw_vitals.csv.VISIT_NUM: non-numeric value")

    ex = frames["raw_exposure.csv"]
    _assert_unique(ex, ["PATIENT"], "raw_exposure.csv")
    ex_start = _dates(ex, "START_DATE", "raw_exposure.csv")
    ex_end = _dates(ex, "END_DATE", "raw_exposure.csv", optional=True).fillna(ex_start)
    _require((ex_end >= ex_start).all(), "raw_exposure.csv: END_DATE precedes START_DATE")

    cm = frames["raw_conmeds.csv"]
    _assert_terms(cm, "ONGOING", {"Y", "N"}, "raw_conmeds.csv")
    cm_start = _dates(cm, "START_DT", "raw_conmeds.csv")
    cm_end = _dates(cm, "END_DT", "raw_conmeds.csv", optional=True)
    _require((cm_end.dropna() >= cm_start[cm_end.notna()]).all(), "raw_conmeds.csv: END_DT precedes START_DT")
    _require(((cm["ONGOING"] == "Y") == cm["END_DT"].eq("")).all(), "raw_conmeds.csv: ONGOING conflicts with END_DT")

    timeline_specs = [
        (ae, "ID", ae_start, ae_end, "raw_ae.csv"),
        (visits, "PT_ID", visit_dates, visit_dates, "raw_vitals.csv"),
        (ex, "PATIENT", ex_start, ex_end, "raw_exposure.csv"),
        (frames["raw_lab.csv"], "SUBJ", _dates(frames["raw_lab.csv"], "LAB_DAT", "raw_lab.csv"), None, "raw_lab.csv"),
        (frames["raw_ecg.csv"], "SUBJECT", _dates(frames["raw_ecg.csv"], "DATE", "raw_ecg.csv"), None, "raw_ecg.csv"),
    ]
    for frame, subject_field, starts, ends, filename in timeline_specs:
        lower = frame[subject_field].map(bounds["start"])
        upper = frame[subject_field].map(bounds["end"])
        _require((starts.reset_index(drop=True) >= lower.reset_index(drop=True)).all(), f"{filename}: event before consent")
        final = starts if ends is None else ends
        _require((final.reset_index(drop=True) <= upper.reset_index(drop=True)).all(), f"{filename}: event after study end")

    for filename in ("raw_lab.csv", "raw_ecg.csv"):
        frame = frames[filename]
        numeric = pd.to_numeric(frame["RESULT"], errors="coerce")
        _require(numeric.notna().all(), f"{filename}.RESULT: non-numeric or missing value")
        _require(frame["UNIT"].str.strip().ne("").all(), f"{filename}.UNIT: missing for numeric result")
        _assert_unique(frame, [SUBJECT_FIELDS[filename], "VISIT_NUM", "TEST_NAME"], filename)

    _dates(frames["raw_mh.csv"], "DIAGNOSIS_DATE", "raw_mh.csv")

    row_counts = {name: len(frame) for name, frame in frames.items()}
    sha256 = {
        name: hashlib.sha256((raw_dir / name).read_bytes()).hexdigest()
        for name in REQUIRED_COLUMNS
    }
    result = ValidationResult(row_counts=row_counts, sha256=sha256)
    if manifest_path is not None:
        _validate_manifest(raw_dir, result, Path(manifest_path))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path, default=DEFAULT_RAW_DIR)
    parser.add_argument("--no-golden", action="store_true", help="Validate contracts without exact golden hashes")
    args = parser.parse_args()
    result = validate_raw_contracts(args.raw_dir, manifest_path=None if args.no_golden else DEFAULT_MANIFEST)
    print("Raw EDC acceptance passed.")
    for filename, count in sorted(result.row_counts.items()):
        print(f" - {filename}: {count} rows")


if __name__ == "__main__":
    main()
