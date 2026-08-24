/*******************************************************************************
Program Name: adam_advs.sas
Description:  Derivation of ADVS (Vital Signs Analysis Dataset).
              Merges ADSL with SDTM VS to derive Baseline Flags (ABLFL),
              Baseline Values (BASE), and Change from Baseline (CHG).
*******************************************************************************/

/* Execute through RUN_ALL.SAS, which initializes PROJECT_PATH and libraries. */

/* 1. MERGE ADSL AND VS */
proc sort data=adam.adsl out=work.adsl_sorted;
    by USUBJID;
run;

proc sort data=sdtm.vs out=work.vs_sorted;
    by USUBJID VSDTC VSTESTCD;
run;

data work.advs_draft;
	retain STUDYID USUBJID;
    merge work.adsl_sorted(in=a) work.vs_sorted(in=b);
    by USUBJID;
    if b; /* Keep only records that have vital signs */

    /* --------------------------------------------------------
       CORE ANALYSIS VARIABLES
       -------------------------------------------------------- */
    PARAMCD = VSTESTCD;
    PARAM   = VSTEST;
    AVAL    = VSSTRESN;
    AVISIT  = VISIT;
    AVISITN = VISITNUM;
    SRCDOM  = 'VS';
    SRCVAR  = 'VSSEQ';
    SRCSEQ  = VSSEQ;

    /* Convert ISO Date to Numeric Analysis Date */
    if length(VSDTC) >= 10 then ASTDT = input(substr(VSDTC, 1, 10), yymmdd10.);
    format ASTDT date9.;

    /* Analysis Relative Day (ASTDY) */
    if not missing(ASTDT) and not missing(TRTSDT) then do;
        if ASTDT >= TRTSDT then ASTDY = (ASTDT - TRTSDT) + 1;
        else ASTDY = ASTDT - TRTSDT;
    end;

    keep STUDYID USUBJID TRT01A TRTSDT TRTEDT PARAMCD PARAM AVAL
         AVISIT AVISITN ASTDT ASTDY SRCDOM SRCVAR SRCSEQ;
run;


/* 2. IDENTIFY BASELINE RECORD */
proc sort data=work.advs_draft out=work.advs_base_candidates;
    by USUBJID PARAMCD ASTDT AVISITN SRCSEQ;
    where ASTDT <= TRTSDT and not missing(AVAL);
run;

data work.base_flags;
    set work.advs_base_candidates;
    by USUBJID PARAMCD;
    
    if last.PARAMCD then do;
        BASE = AVAL;
        BASE_DT = ASTDT;
        BASE_SEQ = SRCSEQ;
        output;
    end;
    keep USUBJID PARAMCD BASE BASE_DT BASE_SEQ;
run;


/* 3. MERGE BASELINE BACK AND CALCULATE FLAGS/CHANGE */
proc sort data=work.advs_draft;
    by USUBJID PARAMCD;
run;

data adam.advs;
	retain STUDYID USUBJID;
    merge work.advs_draft(in=a) work.base_flags(in=b);
    by USUBJID PARAMCD;
    if a;

    /* Flag the exact source record; the QC gate rejects same-day ambiguity. */
    if SRCSEQ = BASE_SEQ then ABLFL = 'Y';
    else ABLFL = '';

    /* 2. Calculate Change from Baseline */
    if not missing(AVAL) and not missing(BASE) then do;
        CHG = AVAL - BASE;
    end;
    
    drop BASE_DT BASE_SEQ;
run;

/* Re-sort for final presentation */
proc sort data=adam.advs;
    by USUBJID PARAMCD ASTDT;
run;


/* 4. VISUAL AUDIT */
title "ADVS Audit - Vital Signs Baseline and Change Analysis";
proc print data=adam.advs(obs=15);
    var USUBJID PARAMCD AVISIT ASTDT TRTSDT AVAL BASE CHG ABLFL;
run;
title;
