/*******************************************************************************
Program Name: qc_core.sas
Description:  Automated Quality Control (QC) Validation Framework.
              Runs cross-domain referential integrity checks and logical rules.
              Triggers ABORT CANCEL if critical errors are found.
              Generates a permanent audit dataset in the ADAM library.
*******************************************************************************/

/* Execute through RUN_ALL.SAS, which initializes PROJECT_PATH and libraries. */

/* -------------------------------------------------------------------
   1. DEFINE VALIDATION RULES
   ------------------------------------------------------------------- */

/* RULE 1: ADSL - USUBJID must be perfectly unique */
proc sql noprint;
    create table chk_adsl01 as
    select 'ADSL-001' as CHECK_ID, 'ADSL' as DOMAIN, 'USUBJID must be perfectly unique' as RULE,
           count(*) as N_FAIL
    from (select USUBJID from adam.adsl group by USUBJID having count(*) > 1);
quit;

/* RULE 2: ADAE - Adverse Event End Date must be >= Start Date */
proc sql noprint;
    create table chk_adae01 as
    select 'ADAE-001' as CHECK_ID, 'ADAE' as DOMAIN, 'AEENDT must be >= AESTDT' as RULE,
           count(*) as N_FAIL
    from adam.adae
    where AEENDT < AESTDT and not missing(AEENDT) and not missing(AESTDT);
quit;

/* RULE 3: ADVS - Maximum 1 Baseline (ABLFL='Y') per Parameter per Subject */
proc sql noprint;
    create table chk_advs01 as
    select 'ADVS-001' as CHECK_ID, 'ADVS' as DOMAIN, 'Max 1 Baseline (ABLFL=Y) per Param' as RULE,
           count(*) as N_FAIL
    from (select USUBJID, PARAMCD from adam.advs where ABLFL = 'Y' group by USUBJID, PARAMCD having count(*) > 1);
quit;

/* RULE 4: ADLB - Maximum 1 Baseline (ABLFL='Y') per Parameter per Subject */
proc sql noprint;
    create table chk_adlb01 as
    select 'ADLB-001' as CHECK_ID, 'ADLB' as DOMAIN, 'Max 1 Baseline (ABLFL=Y) per Param' as RULE,
           count(*) as N_FAIL
    from (select USUBJID, PARAMCD from adam.adlb where ABLFL = 'Y' group by USUBJID, PARAMCD having count(*) > 1);
quit;

/* RULE 5: SDTM DM - No duplicate records */
proc sql noprint;
    create table chk_dm01 as
    select 'SDTM-001' as CHECK_ID, 'DM' as DOMAIN, 'USUBJID must be perfectly unique' as RULE,
           count(*) as N_FAIL
    from (select USUBJID from sdtm.dm group by USUBJID having count(*) > 1);
quit;

/* RULE 6: SDTM AE - Referential Integrity (Subject must exist in DM) */
proc sql noprint;
    create table chk_ae01 as
    select 'SDTM-002' as CHECK_ID, 'AE' as DOMAIN, 'Every AE.USUBJID exists in DM' as RULE,
           count(*) as N_FAIL
    from sdtm.ae a left join sdtm.dm d on a.USUBJID = d.USUBJID
    where d.USUBJID is null;
quit;

/* RULE 7: SDTM EX - Referential Integrity */
proc sql noprint;
    create table chk_ex01 as
    select 'SDTM-003' as CHECK_ID, 'EX' as DOMAIN, 'Every EX.USUBJID exists in DM' as RULE,
           count(*) as N_FAIL
    from sdtm.ex a left join sdtm.dm d on a.USUBJID = d.USUBJID
    where d.USUBJID is null;
quit;

/* RULE 8: SDTM LB - Referential Integrity */
proc sql noprint;
    create table chk_lb01 as
    select 'SDTM-004' as CHECK_ID, 'LB' as DOMAIN, 'Every LB.USUBJID exists in DM' as RULE,
           count(*) as N_FAIL
    from sdtm.lb a left join sdtm.dm d on a.USUBJID = d.USUBJID
    where d.USUBJID is null;
quit;

/* RULE 9: SDTM VS - Referential Integrity */
proc sql noprint;
    create table chk_vs01 as
    select 'SDTM-005' as CHECK_ID, 'VS' as DOMAIN, 'Every VS.USUBJID exists in DM' as RULE,
           count(*) as N_FAIL
    from sdtm.vs a left join sdtm.dm d on a.USUBJID = d.USUBJID
    where d.USUBJID is null;
quit;

/* RULE 10: ADSL - Safety Population (SAFFL='Y') requires Exposure in EX */
proc sql noprint;
    create table chk_adsl02 as
    select 'ADSL-002' as CHECK_ID, 'ADSL' as DOMAIN, 'SAFFL=Y requires exposure in EX' as RULE,
           count(*) as N_FAIL
    from adam.adsl a left join sdtm.ex e on a.USUBJID = e.USUBJID
    where a.SAFFL = 'Y' and e.USUBJID is null;
quit;

/* RULE 11: ADTTE - Survival time must be a positive inclusive day count */
proc sql noprint;
    create table chk_adtte01 as
    select 'ADTTE-001' as CHECK_ID, 'ADTTE' as DOMAIN, 'Survival time (AVAL) must be >= 1' as RULE,
           count(*) as N_FAIL
    from adam.adtte
    where missing(AVAL) or AVAL < 1;
quit;

/* ADTTE-002: Event and censoring records must use the documented formula. */
proc sql noprint;
    create table chk_adtte02 as
    select 'ADTTE-002' as CHECK_ID, 'ADTTE' as DOMAIN,
           'AVAL and CNSR agree with event or subject follow-up date' as RULE,
           count(*) as N_FAIL
    from adam.adtte
    where missing(TRTSDT)
       or missing(CNSR)
       or CNSR not in (0, 1)
       or (CNSR = 0 and (missing(EVENTDT) or AVAL ne (EVENTDT - TRTSDT) + 1))
       or (CNSR = 1 and (not missing(EVENTDT) or missing(EOSDT)
                         or AVAL ne (EOSDT - TRTSDT) + 1));
quit;

/* ADTTE-003: Analysis dates must remain inside individual follow-up. */
proc sql noprint;
    create table chk_adtte03 as
    select 'ADTTE-003' as CHECK_ID, 'ADTTE' as DOMAIN,
           'Event and follow-up dates must be chronologically valid' as RULE,
           count(*) as N_FAIL
    from adam.adtte
    where missing(EOSDT)
       or EOSDT < TRTSDT
       or (not missing(EVENTDT) and
           (EVENTDT < TRTSDT or EVENTDT > EOSDT));
quit;

/* ADSL-003: EOSDT must be the numeric representation of DM.RFPENDTC. */
proc sql noprint;
    create table chk_adsl03 as
    select 'ADSL-003' as CHECK_ID, 'ADSL' as DOMAIN,
           'EOSDT must agree with DM.RFPENDTC' as RULE,
           count(*) as N_FAIL
    from adam.adsl a
    left join sdtm.dm d on a.USUBJID = d.USUBJID
    where d.USUBJID is null
       or missing(a.EOSDT)
       or a.EOSDT ne input(substr(d.RFPENDTC, 1, 10), yymmdd10.);
quit;

/* ADSL-004: AGE must represent completed years at informed consent. */
proc sql noprint;
    create table chk_adsl04 as
    select 'ADSL-004' as CHECK_ID, 'ADSL' as DOMAIN,
           'AGE must equal completed years at informed consent' as RULE,
           count(*) as N_FAIL
    from adam.adsl
    where missing(BRTHDT)
       or missing(RFICDT)
       or missing(AGE)
       or AGE ne floor(yrdif(BRTHDT, RFICDT, 'AGE'));
quit;

/* ADVS-002: Selected baseline date must identify one source record.
   More than one same-day candidate cannot be resolved without collection time. */
proc sql noprint;
    create table chk_advs02 as
    select 'ADVS-002' as CHECK_ID, 'ADVS' as DOMAIN,
           'Baseline date has exactly one eligible source record' as RULE,
           count(*) as N_FAIL
    from (
        select a.USUBJID, a.PARAMCD
        from adam.advs a
        inner join (
            select USUBJID, PARAMCD, max(ASTDT) as BASE_DT
            from adam.advs
            where ASTDT <= TRTSDT and not missing(AVAL)
            group by USUBJID, PARAMCD
        ) b
          on a.USUBJID = b.USUBJID
         and a.PARAMCD = b.PARAMCD
         and a.ASTDT = b.BASE_DT
        where not missing(a.AVAL)
        group by a.USUBJID, a.PARAMCD
        having count(*) > 1
    );
quit;

/* ADLB-002: Selected baseline date must identify one source record. */
proc sql noprint;
    create table chk_adlb02 as
    select 'ADLB-002' as CHECK_ID, 'ADLB' as DOMAIN,
           'Baseline date has exactly one eligible source record' as RULE,
           count(*) as N_FAIL
    from (
        select a.USUBJID, a.PARAMCD
        from adam.adlb a
        inner join (
            select USUBJID, PARAMCD, max(ASTDT) as BASE_DT
            from adam.adlb
            where ASTDT <= TRTSDT and not missing(AVAL)
            group by USUBJID, PARAMCD
        ) b
          on a.USUBJID = b.USUBJID
         and a.PARAMCD = b.PARAMCD
         and a.ASTDT = b.BASE_DT
        where not missing(a.AVAL)
        group by a.USUBJID, a.PARAMCD
        having count(*) > 1
    );
quit;

/* RULE 12: SDTM EG - Referential Integrity */
proc sql noprint;
    create table chk_eg01 as
    select 'SDTM-006' as CHECK_ID, 'EG' as DOMAIN, 'Every EG.USUBJID exists in DM' as RULE,
           count(*) as N_FAIL
    from sdtm.eg e left join sdtm.dm d on e.USUBJID = d.USUBJID
    where d.USUBJID is null;
quit;

/* RULE 13: SDTM EG - Required variables must exist */
proc sql noprint;
    create table chk_eg02 as
    select 'SDTM-007' as CHECK_ID, 'EG' as DOMAIN, 'Required EG variables must exist' as RULE,
           12 - count(distinct upcase(name)) as N_FAIL
    from dictionary.columns
    where libname = 'SDTM' and memname = 'EG'
      and upcase(name) in (
          'STUDYID', 'DOMAIN', 'USUBJID', 'EGSEQ', 'EGTESTCD', 'EGTEST',
          'EGORRES', 'EGORRESU', 'EGSTRESC', 'EGSTRESN', 'EGSTRESU', 'EGDTC'
      );
quit;

/* RULE 14: SDTM EG - Dates and numeric standard results must be usable */
proc sql noprint;
    create table chk_eg03 as
    select 'SDTM-008' as CHECK_ID, 'EG' as DOMAIN, 'EG date/value contract must be valid' as RULE,
           count(*) as N_FAIL
    from sdtm.eg
    where missing(EGDTC)
       or prxmatch('/^\d{4}-\d{2}-\d{2}$/', strip(EGDTC)) = 0
       or missing(EGSTRESN)
       or missing(EGSTRESC);
quit;

/* RULE 15: SDTM EG - Raw import variables must not leak into SDTM */
proc sql noprint;
    create table chk_eg04 as
    select 'SDTM-009' as CHECK_ID, 'EG' as DOMAIN, 'Raw EG variables must not leak to SDTM' as RULE,
           count(*) as N_FAIL
    from dictionary.columns
    where libname = 'SDTM' and memname = 'EG'
      and upcase(name) in ('SUBJECT', 'TEST_NAME', 'RESULT', 'UNIT', 'DATE');
quit;

/* RULE 16: SDTM MH - Referential Integrity */
proc sql noprint;
    create table chk_mh01 as
    select 'SDTM-010' as CHECK_ID, 'MH' as DOMAIN, 'Every MH.USUBJID exists in DM' as RULE,
           count(*) as N_FAIL
    from sdtm.mh m left join sdtm.dm d on m.USUBJID = d.USUBJID
    where d.USUBJID is null;
quit;

/* RULE 17: SDTM MH - Required variables must exist */
proc sql noprint;
    create table chk_mh02 as
    select 'SDTM-011' as CHECK_ID, 'MH' as DOMAIN, 'Required MH variables must exist' as RULE,
           6 - count(distinct upcase(name)) as N_FAIL
    from dictionary.columns
    where libname = 'SDTM' and memname = 'MH'
      and upcase(name) in (
          'STUDYID', 'DOMAIN', 'USUBJID', 'MHSEQ', 'MHTERM', 'MHSTDTC'
      );
quit;

/* RULE 18: SDTM MH - Dates and terms must be usable */
proc sql noprint;
    create table chk_mh03 as
    select 'SDTM-012' as CHECK_ID, 'MH' as DOMAIN, 'MH date/term contract must be valid' as RULE,
           count(*) as N_FAIL
    from sdtm.mh
    where missing(MHSTDTC)
       or prxmatch('/^\d{4}-\d{2}-\d{2}$/', strip(MHSTDTC)) = 0
       or missing(MHTERM);
quit;

/* RULE 19: SDTM MH - Raw import variables must not leak into SDTM */
proc sql noprint;
    create table chk_mh04 as
    select 'SDTM-013' as CHECK_ID, 'MH' as DOMAIN, 'Raw MH variables must not leak to SDTM' as RULE,
           count(*) as N_FAIL
    from dictionary.columns
    where libname = 'SDTM' and memname = 'MH'
      and upcase(name) in ('SUBJECT', 'CONDITION', 'DIAGNOSIS_DATE');
quit;

/* RULE 20: DM reference period must be complete, ISO 8601, and ordered */
proc sql noprint;
    create table chk_dm02 as
    select 'SDTM-014' as CHECK_ID, 'DM' as DOMAIN, 'DM reference dates complete and ordered' as RULE,
           count(*) as N_FAIL
    from sdtm.dm
    where missing(RFICDTC) or missing(RFSTDTC) or missing(RFENDTC) or missing(RFPENDTC)
       or prxmatch('/^\d{4}-\d{2}-\d{2}$/', strip(RFICDTC)) = 0
       or prxmatch('/^\d{4}-\d{2}-\d{2}$/', strip(RFSTDTC)) = 0
       or prxmatch('/^\d{4}-\d{2}-\d{2}$/', strip(RFENDTC)) = 0
       or prxmatch('/^\d{4}-\d{2}-\d{2}$/', strip(RFPENDTC)) = 0
       or RFSTDTC < RFICDTC or RFENDTC < RFSTDTC or RFPENDTC ne RFENDTC;
quit;

/* RULE 21: SV subjects must exist in DM */
proc sql noprint;
    create table chk_sv01 as
    select 'SDTM-015' as CHECK_ID, 'SV' as DOMAIN, 'Every SV.USUBJID exists in DM' as RULE,
           count(*) as N_FAIL
    from sdtm.sv s left join sdtm.dm d on s.USUBJID = d.USUBJID
    where d.USUBJID is null;
quit;

/* RULE 22: one SV row per subject and visit number */
proc sql noprint;
    create table chk_sv02 as
    select 'SDTM-016' as CHECK_ID, 'SV' as DOMAIN, 'USUBJID and VISITNUM must be unique' as RULE,
           count(*) as N_FAIL
    from (select USUBJID, VISITNUM from sdtm.sv
          group by USUBJID, VISITNUM having count(*) ne 1);
quit;

/* RULE 23: actual visits must be valid and within the DM reference period */
proc sql noprint;
    create table chk_sv03 as
    select 'SDTM-017' as CHECK_ID, 'SV' as DOMAIN, 'SV dates valid and inside reference period' as RULE,
           count(*) as N_FAIL
    from sdtm.sv s inner join sdtm.dm d on s.USUBJID = d.USUBJID
    where missing(s.VISITNUM) or missing(s.VISIT) or missing(s.SVSTDTC) or missing(s.SVENDTC)
       or prxmatch('/^\d{4}-\d{2}-\d{2}$/', strip(s.SVSTDTC)) = 0
       or prxmatch('/^\d{4}-\d{2}-\d{2}$/', strip(s.SVENDTC)) = 0
       or s.SVENDTC < s.SVSTDTC
       or s.SVSTDTC < d.RFSTDTC or s.SVENDTC > d.RFENDTC;
quit;

/* RULE 24: DS must contain exactly one final disposition for every DM subject */
proc sql noprint;
    create table chk_ds01 as
    select 'SDTM-018' as CHECK_ID, 'DS' as DOMAIN, 'Exactly one final DS record per DM subject' as RULE,
           count(*) as N_FAIL
    from (
        select d.USUBJID, count(s.USUBJID) as N_DS
        from sdtm.dm d left join sdtm.ds s on d.USUBJID = s.USUBJID
        group by d.USUBJID having calculated N_DS ne 1
        union all
        select s.USUBJID, count(*) as N_DS
        from sdtm.ds s left join sdtm.dm d on s.USUBJID = d.USUBJID
        where d.USUBJID is null group by s.USUBJID
    );
quit;

/* RULE 25: DS final date must agree with the end of subject participation */
proc sql noprint;
    create table chk_ds02 as
    select 'SDTM-019' as CHECK_ID, 'DS' as DOMAIN, 'DS date matches DM participation end' as RULE,
           count(*) as N_FAIL
    from sdtm.ds s inner join sdtm.dm d on s.USUBJID = d.USUBJID
    where missing(s.DSDECOD) or missing(s.DSSTDTC)
       or prxmatch('/^\d{4}-\d{2}-\d{2}$/', strip(s.DSSTDTC)) = 0
       or s.DSSTDTC ne d.RFPENDTC;
quit;

/* RULE 26: DM RACE must use the supported CDISC Controlled Terminology */
proc sql noprint;
    create table chk_dm03 as
    select 'SDTM-020' as CHECK_ID, 'DM' as DOMAIN, 'RACE uses supported CDISC terminology' as RULE,
           count(*) as N_FAIL
    from sdtm.dm
    where missing(RACE)
       or upcase(strip(RACE)) not in (
           'WHITE', 'BLACK OR AFRICAN AMERICAN', 'ASIAN', 'OTHER', 'UNKNOWN'
       );
quit;

/* RULE 27: DM SITEID must be present and agree with the subject identifier */
proc sql noprint;
    create table chk_dm04 as
    select 'SDTM-021' as CHECK_ID, 'DM' as DOMAIN, 'SITEID present and consistent with SUBJID' as RULE,
           count(*) as N_FAIL
    from sdtm.dm
    where missing(SITEID)
       or strip(SITEID) ne scan(strip(SUBJID), 1, '-');
quit;

/* RULE 28: AOCCFL may flag only a treatment-emergent record */
proc sql noprint;
    create table chk_adae02 as
    select 'ADAE-002' as CHECK_ID, 'ADAE' as DOMAIN, 'AOCCFL valid and restricted to TRTEMFL=Y' as RULE,
           count(*) as N_FAIL
    from adam.adae
    where (not missing(AOCCFL) and AOCCFL ne 'Y')
       or (AOCCFL = 'Y' and TRTEMFL ne 'Y');
quit;

/* RULE 29: Every subject/PT with a TEAE has exactly one first occurrence */
proc sql noprint;
    create table chk_adae03 as
    select 'ADAE-003' as CHECK_ID, 'ADAE' as DOMAIN, 'One AOCCFL=Y per subject and TEAE term' as RULE,
           count(*) as N_FAIL
    from (
        select USUBJID, AEDECOD
        from adam.adae
        group by USUBJID, AEDECOD
        having sum(case when TRTEMFL = 'Y' then 1 else 0 end) > 0
           and sum(case when AOCCFL = 'Y' then 1 else 0 end) ne 1
    );
quit;

/* RULE 30: CM must preserve subject integrity, required values and chronology. */
proc sql noprint;
    create table chk_cm01 as
    select 'SDTM-022' as CHECK_ID, 'CM' as DOMAIN,
           'CM subject, medication, dose and dates must be valid' as RULE,
           count(*) as N_FAIL
    from sdtm.cm c
    left join sdtm.dm d on c.USUBJID = d.USUBJID
    where d.USUBJID is null
       or missing(c.CMTRT) or missing(c.CMDECOD)
       or (upcase(strip(c.CMTRT)) = 'PARACETAMOL' and
           upcase(strip(c.CMDECOD)) ne 'ACETAMINOPHEN')
       or missing(c.CMDOSE) or missing(c.CMDOSU)
       or missing(c.CMSTDTC)
       or prxmatch('/^\d{4}-\d{2}-\d{2}$/', strip(c.CMSTDTC)) = 0
       or (not missing(c.CMENDTC) and
           prxmatch('/^\d{4}-\d{2}-\d{2}$/', strip(c.CMENDTC)) = 0)
       or (not missing(c.CMENDTC) and c.CMENDTC < c.CMSTDTC)
       or (c.CMENRTPT = 'ONGOING' and not missing(c.CMENDTC))
       or (c.CMENRTPT ne 'ONGOING' and missing(c.CMENDTC));
quit;

/* RULE 31: DSDECOD must use the supported disposition terminology. */
proc sql noprint;
    create table chk_ds03 as
    select 'SDTM-023' as CHECK_ID, 'DS' as DOMAIN,
           'DSDECOD uses supported disposition terminology' as RULE,
           count(*) as N_FAIL
    from sdtm.ds
    where upcase(strip(DSDECOD)) not in (
        'COMPLETED', 'LOST TO FOLLOW-UP', 'WITHDRAWAL BY SUBJECT',
        'ADVERSE EVENT', 'SCREEN FAILURE'
    );
quit;

/* RULE 32: Sequence variables must be unique inside each subject/domain. */
proc sql noprint;
    create table chk_seq01 as
    select 'SDTM-024' as CHECK_ID, 'SDTM' as DOMAIN,
           'Domain sequence keys must be unique per subject' as RULE,
           count(*) as N_FAIL
    from (
        select 'AE' as SOURCE, USUBJID, AESEQ as SEQ
        from sdtm.ae group by USUBJID, AESEQ having count(*) > 1
        union all
        select 'EX', USUBJID, EXSEQ from sdtm.ex
        group by USUBJID, EXSEQ having count(*) > 1
        union all
        select 'LB', USUBJID, LBSEQ from sdtm.lb
        group by USUBJID, LBSEQ having count(*) > 1
        union all
        select 'VS', USUBJID, VSSEQ from sdtm.vs
        group by USUBJID, VSSEQ having count(*) > 1
        union all
        select 'CM', USUBJID, CMSEQ from sdtm.cm
        group by USUBJID, CMSEQ having count(*) > 1
        union all
        select 'MH', USUBJID, MHSEQ from sdtm.mh
        group by USUBJID, MHSEQ having count(*) > 1
        union all
        select 'EG', USUBJID, EGSEQ from sdtm.eg
        group by USUBJID, EGSEQ having count(*) > 1
    );
quit;

/* RULE 39: Ongoing CM timing must have an explicit observed reference point. */
proc sql noprint;
    create table chk_cm02 as
    select 'SDTM-025' as CHECK_ID, 'CM' as DOMAIN,
           'Ongoing CM must be anchored to the DM reference end' as RULE,
           count(*) as N_FAIL
    from sdtm.cm c
    inner join sdtm.dm d on c.USUBJID = d.USUBJID
    where upcase(strip(c.CMENRTPT)) not in ('', 'ONGOING')
       or (upcase(strip(c.CMENRTPT)) = 'ONGOING' and (
              not missing(c.CMENDTC)
           or missing(c.CMENTPT)
           or prxmatch('/^\d{4}-\d{2}-\d{2}$/', strip(c.CMENTPT)) = 0
           or c.CMENTPT ne d.RFENDTC
          ))
       or (upcase(strip(c.CMENRTPT)) ne 'ONGOING' and
           not missing(c.CMENTPT));
quit;


/* -------------------------------------------------------------------
   2. CONSOLIDATE RESULTS (Generate Permanent Data)
   ------------------------------------------------------------------- */
data adam.qc_report;
    /* CORREÇÃO: Definir limites de texto ANTES do set previne os "Warnings" de truncation */
    length CHECK_ID $10 DOMAIN $10 RULE $70 STATUS $10;
    
    set chk_adsl01 chk_adae01 chk_advs01 chk_adlb01
        chk_advs02 chk_adlb02 chk_dm01
        chk_ae01 chk_ex01 chk_lb01 chk_vs01 chk_adsl02 chk_adsl03 chk_adsl04
        chk_adtte01 chk_adtte02 chk_adtte03
        chk_eg01 chk_eg02 chk_eg03 chk_eg04
        chk_mh01 chk_mh02 chk_mh03 chk_mh04 chk_dm02
        chk_sv01 chk_sv02 chk_sv03 chk_ds01 chk_ds02
        chk_dm03 chk_dm04 chk_adae02 chk_adae03
        chk_cm01 chk_ds03 chk_seq01 chk_cm02;
        
    if N_FAIL = 0 then STATUS = "PASS";
    else STATUS = "FAIL";
run;


/* -------------------------------------------------------------------
   3. PRINT REPORT
   ------------------------------------------------------------------- */
title "Automated Quality Control (QC) Validation Report";
proc print data=adam.qc_report noobs;
    var CHECK_ID DOMAIN RULE N_FAIL STATUS;
run;
title;


/* -------------------------------------------------------------------
   4. SYSTEM ABORT LOGIC (The Professional Pipeline Stopper)
   ------------------------------------------------------------------- */
proc sql noprint;
    select count(*), sum(STATUS = 'FAIL') into :n_checks, :n_failed
    from adam.qc_report
    ;
quit;

%macro abort_if_fail;
    %if &n_failed > 0 %then %do;
        %put ERROR: --------------------------------------------------;
        %put ERROR: QC PIPELINE FAILED. CRITICAL DATA ERRORS DETECTED.;
        %put ERROR: &n_failed VALIDATION RULES FAILED.;
        %put ERROR: EXECUTION ABORTED.;
        %put ERROR: --------------------------------------------------;
        %abort cancel;
    %end;
    %else %do;
        %put NOTE: ---------------------------------------------------;
        %put NOTE: QC VALIDATION COMPLETE. ALL &n_checks CHECKS PASSED SUCCESSFULLY.;
        %put NOTE: ---------------------------------------------------;
    %end;
%mend;

%abort_if_fail;

/* ---------------------------------------------------------
   EXPORT QC REPORT TO RTF FOR GITHUB PORTFOLIO
--------------------------------------------------------- */
ods rtf file="&project_path./tlfs/qc_report.rtf" style=Journal;

title "Automated Quality Control (QC) Report";
proc print data=adam.qc_report noobs;
run;
title;

ods rtf close;
