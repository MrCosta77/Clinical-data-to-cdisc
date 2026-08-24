import re
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _source(relative_path: str) -> str:
    return (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")


def test_dm_maps_race_and_retains_site_identifier():
    source = _source("programs/sdtm_dm.sas")
    assert "RACE $40" in source
    assert "BLACK OR AFRICAN AMERICAN" in source
    assert "SITEID = strip" in source
    assert "SUBJID SITEID SEX RACE" in source


def test_all_sdtm_domains_share_the_usubjid_length_contract():
    setup = _source("programs/00_setup.sas")
    assert "%let usubjid_length = 40;" in setup

    domains = ("dm", "ae", "ex", "vs", "lb", "cm", "mh", "eg", "sv", "ds")
    for domain in domains:
        source = _source(f"programs/sdtm_{domain}.sas")
        assert "USUBJID $&usubjid_length." in source, domain


def test_adae_derives_first_treatment_emergent_occurrence():
    source = _source("programs/adam_adae.sas")
    assert "length AOCCFL $1" in source
    assert "TRTEMFL = 'Y' and first._occ_order" in source
    assert "by USUBJID AEDECOD _occ_order AESTDT AESEQ" in source


def test_qc_covers_new_semantic_contracts():
    source = _source("qc/qc_core.sas")
    for check_id in (
        "SDTM-020", "SDTM-021", "ADAE-002", "ADAE-003",
        "ADVS-002", "ADLB-002",
    ):
        assert check_id in source
    assert "Baseline date has exactly one eligible source record" in source
    assert "ALL &n_checks CHECKS PASSED" in source
    check_ids = re.findall(r"select '([^']+)' as CHECK_ID", source)
    assert len(check_ids) == 31
    assert len(set(check_ids)) == 31


def test_define_generator_emits_semantic_metadata():
    source = _source("programs/generate_define.sas")
    assert '<CodeListRef CodeListOID="' in source
    assert '<def:Origin Type="' in source
    assert 'MethodOID="' in source
    assert '<CodeList OID="CL.RACE"' in source
    assert '<MethodDef OID="MT.ADAE.AOCCFL"' in source
    assert "same-day ambiguity is rejected by QC" in source
    assert "type, length, format, label, varnum" in source
    assert "dt_type = 'datetime'" in source
    assert "dt_type = 'date'" in source
    assert "dt_type = 'float'" in source


def test_adam_baselines_retain_source_traceability_and_exact_flag_key():
    for dataset, domain, sequence in (
        ("advs", "VS", "VSSEQ"),
        ("adlb", "LB", "LBSEQ"),
    ):
        source = _source(f"programs/adam_{dataset}.sas")
        assert f"SRCDOM  = '{domain}'" in source
        assert f"SRCVAR  = '{sequence}'" in source
        assert f"SRCSEQ  = {sequence}" in source
        assert "if SRCSEQ = BASE_SEQ then ABLFL = 'Y'" in source
        assert "drop BASE_DT BASE_SEQ" in source or "drop _calc_val BASE_DT BASE_SEQ" in source
