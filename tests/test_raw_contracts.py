from pathlib import Path

import pandas as pd
import pytest

from scripts.validate_raw_contracts import DEFAULT_RAW_DIR, validate_raw_contracts


def test_versioned_synthetic_cohort_matches_golden_manifest():
    result = validate_raw_contracts()
    assert result.row_counts["raw_demog.csv"] == 50
    assert set(result.row_counts) == {
        "raw_demog.csv", "raw_ae.csv", "raw_vitals.csv", "raw_exposure.csv",
        "raw_lab.csv", "raw_conmeds.csv", "raw_mh.csv", "raw_ecg.csv",
    }


def test_versioned_csv_bytes_use_platform_independent_lf_endings():
    for source in DEFAULT_RAW_DIR.glob("*.csv"):
        assert b"\r\n" not in source.read_bytes(), f"{source.name} uses CRLF endings"


def _copy_raw(tmp_path: Path) -> Path:
    target = tmp_path / "raw"
    target.mkdir()
    for source in DEFAULT_RAW_DIR.glob("*.csv"):
        (target / source.name).write_bytes(source.read_bytes())
    return target


def test_unknown_subject_is_rejected(tmp_path):
    raw = _copy_raw(tmp_path)
    ae = pd.read_csv(raw / "raw_ae.csv", dtype=str, keep_default_na=False)
    ae.loc[0, "ID"] = "UNKNOWN"
    ae.to_csv(raw / "raw_ae.csv", index=False)
    with pytest.raises(ValueError, match="unknown subject"):
        validate_raw_contracts(raw, manifest_path=None)


def test_invalid_controlled_term_is_rejected(tmp_path):
    raw = _copy_raw(tmp_path)
    ae = pd.read_csv(raw / "raw_ae.csv", dtype=str, keep_default_na=False)
    ae.loc[0, "SEV"] = "EXTREME"
    ae.to_csv(raw / "raw_ae.csv", index=False)
    with pytest.raises(ValueError, match="invalid controlled term"):
        validate_raw_contracts(raw, manifest_path=None)


def test_event_outside_subject_timeline_is_rejected(tmp_path):
    raw = _copy_raw(tmp_path)
    visits = pd.read_csv(raw / "raw_vitals.csv", dtype=str, keep_default_na=False)
    visits.loc[0, "VS_DATE"] = "01-Jan-2030"
    visits.to_csv(raw / "raw_vitals.csv", index=False)
    with pytest.raises(ValueError, match="event after study end"):
        validate_raw_contracts(raw, manifest_path=None)


def test_numeric_result_requires_unit(tmp_path):
    raw = _copy_raw(tmp_path)
    labs = pd.read_csv(raw / "raw_lab.csv", dtype=str, keep_default_na=False)
    labs.loc[0, "UNIT"] = ""
    labs.to_csv(raw / "raw_lab.csv", index=False)
    with pytest.raises(ValueError, match="UNIT: missing"):
        validate_raw_contracts(raw, manifest_path=None)
