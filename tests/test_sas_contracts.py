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


def test_cm_applies_the_approved_medication_normalization():
    source = _source("programs/sdtm_cm.sas")
    define = _source("programs/generate_define.sas")
    qc = _source("qc/qc_core.sas")
    assert "CMTRT CMDECOD $50" in source
    assert "when ('PARACETAMOL') CMDECOD = 'ACETAMINOPHEN'" in source
    assert "_CMENTPT_ANCHOR = RFENDTC" in source
    assert "CMENTPT = _CMENTPT_ANCHOR" in source
    assert "CMENRTPT CMENTPT" in source
    assert "MT.CM.CMDECOD" in define
    assert "MT.CM.CMENTPT" in define
    assert "CL.STENRF" in define
    assert "ACETAMINOPHEN" in qc
    assert "SDTM-025" in qc


def test_qc_covers_new_semantic_contracts():
    source = _source("qc/qc_core.sas")
    for check_id in (
        "SDTM-020", "SDTM-021", "ADAE-002", "ADAE-003",
        "ADVS-002", "ADLB-002", "ADSL-003", "ADSL-004", "ADTTE-001",
        "ADTTE-002", "ADTTE-003", "SDTM-022", "SDTM-023", "SDTM-024",
        "SDTM-025",
    ):
        assert check_id in source
    assert "Baseline date has exactly one eligible source record" in source
    assert "ALL &n_checks CHECKS PASSED" in source
    check_ids = re.findall(r"select '([^']+)' as CHECK_ID", source)
    assert len(check_ids) == 39
    assert len(set(check_ids)) == 39


def test_adtte_uses_participant_specific_follow_up():
    adsl = _source("programs/adam_adsl.sas")
    adtte = _source("programs/adam_adtte.sas")
    assert "RFPENDTC" in adsl
    assert "EOSDT = input" in adsl
    assert "(EOSDT - TRTSDT) + 1" in adtte
    assert "study_cutoff" not in adtte
    assert "if AVAL < 0 then AVAL = 0" not in adtte


def test_age_uses_completed_years():
    adsl = _source("programs/adam_adsl.sas")
    define = _source("programs/generate_define.sas")
    assert "floor(yrdif(BRTHDT, RFICDT, 'AGE'))" in adsl
    assert "YRDIF with the AGE basis" in define


def test_outputs_stay_in_tlfs_and_source_duplicates_are_not_deleted():
    for name in ("tlf_table1", "tlf_figure1"):
        source = _source(f"tlfs/{name}.sas")
        assert f'&project_path./tlfs/{name}.rtf' in source

    for domain in ("sv", "ds"):
        source = _source(f"programs/sdtm_{domain}.sas").lower()
        assert "nodupkey" not in source


def test_sas_programs_do_not_embed_a_personal_setup_path():
    sas_files = list((PROJECT_ROOT / "programs").glob("*.sas"))
    sas_files += list((PROJECT_ROOT / "qc").glob("*.sas"))
    sas_files += list((PROJECT_ROOT / "tlfs").glob("*.sas"))
    for sas_file in sas_files:
        source = sas_file.read_text(encoding="utf-8")
        assert "/home/u64384931/" not in source, sas_file

    run_all = _source("run_all.sas")
    assert '%include "&project_path./programs/00_setup.sas";' in run_all
    assert '%include "&project_path./qc/qc_core.sas";' in run_all

    expected_order = (
        "sdtm_dm", "sdtm_ae", "sdtm_ex", "sdtm_lb", "sdtm_vs",
        "sdtm_cm", "sdtm_mh", "sdtm_eg", "sdtm_sv", "sdtm_ds",
        "adam_adsl", "adam_adae", "adam_advs", "adam_adlb", "adam_adtte",
    )
    positions = [
        run_all.index(f'programs/{program}.sas')
        for program in expected_order
    ]
    assert positions == sorted(positions)
    for program in expected_order:
        assert run_all.count(f'programs/{program}.sas') == 1


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
