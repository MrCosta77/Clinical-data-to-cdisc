/*******************************************************************************
Program Name: adam_adsl.sas
Description:  Derivation of ADSL (Subject-Level Analysis Dataset).
              Merges SDTM DM and EX to create population flags (SAFFL, ITTFL), 
              numeric analysis dates, and calculates age and treatment duration.
*******************************************************************************/

%include "/home/u64384931/Clinical-data-to-cdisc/programs/00_setup.sas";

/* 1. GET FIRST EXPOSURE RECORD PER SUBJECT */
proc sort data=sdtm.ex out=work.ex_first;
    by USUBJID EXSTDTC;
run;

data work.ex_trt;
    set work.ex_first;
    by USUBJID;
    if first.USUBJID; /* Keep only the initial dosing record */
    keep USUBJID EXTRT EXSTDTC EXENDTC;
run;

/* 2. SORT DM BEFORE MERGING (Crucial SAS Rule) */
proc sort data=sdtm.dm out=work.dm_sorted;
    by USUBJID;
run;


/* 3. MERGE DEMOGRAPHICS AND EXPOSURE TO CREATE ADSL */
data work.adsl_draft;
    retain STUDYID USUBJID SUBJID SITEID;
    merge work.dm_sorted(in=a) work.ex_trt(in=b);
    by USUBJID;
    if a; /* Keep all randomized subjects from DM */

    /* Core Attributes */
    STUDYID = STUDYID;
    USUBJID = USUBJID;
    SUBJID  = SUBJID;

   /* --------------------------------------------------------
       TREATMENT VARIABLES & POPULATION FLAGS
       -------------------------------------------------------- */
    
    /* 1. Planned Treatment (TRT01P) comes from DM Randomization */
    if ARMCD ne 'SCRNFAIL' then TRT01P = ARM;
    else TRT01P = 'UNPLANNED';

    /* 2. Actual Treatment (TRT01A) comes from Exposure (EX) */
    if b and not missing(EXTRT) then TRT01A = EXTRT;
    else TRT01A = "NOT TREATED";

    /* 3. Intent-To-Treat (ITT) Flag: Only Randomized subjects */
    if ARMCD ne 'SCRNFAIL' then ITTFL = "Y";
    else ITTFL = "N";

    /* 4. Safety Population (SAFFL) Flag: Took at least one dose */
    if not missing(EXSTDTC) then SAFFL = "Y";
    else SAFFL = "N";


    /* --------------------------------------------------------
       NUMERIC DATE DERIVATIONS (For Statistical Math)
       -------------------------------------------------------- */
    /* Convert ISO 8601 character dates to SAS numeric dates */
    if length(BRTHDTC) >= 10 then BRTHDT = input(substr(BRTHDTC, 1, 10), yymmdd10.);
    if length(RFICDTC) >= 10 then RFICDT = input(substr(RFICDTC, 1, 10), yymmdd10.);
    if length(EXSTDTC) >= 10 then TRTSDT = input(substr(EXSTDTC, 1, 10), yymmdd10.);
    if length(EXENDTC) >= 10 then TRTEDT = input(substr(EXENDTC, 1, 10), yymmdd10.);

    format BRTHDT RFICDT TRTSDT TRTEDT date9.; /* Example: 05JAN2023 */

    /* --------------------------------------------------------
       CLINICAL MATH DERIVATIONS
       -------------------------------------------------------- */
    /* 1. Calculate Numeric Age at Time of Informed Consent */
    if not missing(BRTHDT) and not missing(RFICDT) then
        AGE = int((RFICDT - BRTHDT) / 365.25);

    /* 2. Calculate Treatment Duration (Days) */
    if not missing(TRTSDT) and not missing(TRTEDT) then
        TRTDURD = (TRTEDT - TRTSDT) + 1; /* Inclusive of start day */

    keep STUDYID USUBJID SUBJID SITEID TRT01P TRT01A ITTFL SAFFL
         BRTHDT RFICDT TRTSDT TRTEDT AGE TRTDURD SEX RACE;
run;


/* 4. FINALIZE AND SAVE TO ADAM LIBRARY */
proc sort data=work.adsl_draft out=adam.adsl;
    by USUBJID;
run;

/* 5. VISUAL AUDIT */
title "ADSL Audit - Subject Level Analysis Dataset";
proc print data=adam.adsl(obs=10);
    var USUBJID TRT01P TRT01A ITTFL SAFFL AGE;
run;
title;
