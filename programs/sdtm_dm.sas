/*******************************************************************************
Program Name: sdtm_dm.sas
Description:  Mapping of raw EDC data to the SDTM DM (Demographics) domain.
              Includes data cleansing, controlled terminology alignment, 
              and ISO 8601 date conversion.
*******************************************************************************/

/* Execute through RUN_ALL.SAS, which initializes PROJECT_PATH and libraries. */

/* 2. IMPORT RAW EDC DATA */
proc import datafile="&project_path./data/raw/raw_demog.csv"
    out=work.raw_dm
    dbms=csv
    replace;
    getnames=yes;
run;


/* 3. TRANSFORMATION AND SDTM MAPPING */
data sdtm.dm;
    length STUDYID $8 DOMAIN $2 USUBJID $&usubjid_length. SUBJID $20 SITEID $10
           SEX $1 RACE $40 ARM $20 ARMCD $8;
    retain STUDYID DOMAIN USUBJID SUBJID SITEID RFSTDTC RFENDTC RFPENDTC RFICDTC;
    set work.raw_dm;
    
    /* Study Identifier Variables (Required) */
    STUDYID = "CDISC-01";
    DOMAIN  = "DM";
    
    /* USUBJID Creation (Unique Subject Identifier) */
    /* CDISC Rule: Concatenation of STUDYID and Subject ID */
    SUBJID  = SUBJ_ID;
    USUBJID = catx("-", STUDYID, SUBJID);

    /* Investigator site identifier retained from the EDC extract. */
    if vtype(SITE) = 'C' then SITEID = strip(SITE);
    else SITEID = strip(put(SITE, best.));
    
    /* --------------------------------------------------------
       CONTROLLED TERMINOLOGY CLEANING
       -------------------------------------------------------- */
    
    /* EDC has 'M', 'F', 'Male', 'Female'. CDISC strictly requires 'M' or 'F' */
    if upcase(char(GENDER, 1)) = 'M' then SEX = 'M';
    else if upcase(char(GENDER, 1)) = 'F' then SEX = 'F';
    else SEX = 'U'; /* Unknown */
    
    /* Map the EDC labels to CDISC Controlled Terminology. */
    select (upcase(strip(RACE_TXT)));
        when ('WHITE') RACE = 'WHITE';
        when ('BLACK') RACE = 'BLACK OR AFRICAN AMERICAN';
        when ('ASIAN') RACE = 'ASIAN';
        when ('OTHER') RACE = 'OTHER';
        otherwise RACE = 'UNKNOWN';
    end;
    
    /* --------------------------------------------------------
       TRIAL DESIGN VARIABLES (ARM, ARMCD)
       -------------------------------------------------------- */
    /* Mapping the Planned Arm from the EDC system */
    if strip(RANDOMIZED_ARM) = 'Not Randomized' then do;
        ARM = 'SCREEN FAILURE';
        ARMCD = 'SCRNFAIL';
    end;
    else if strip(RANDOMIZED_ARM) = 'Placebo' then do;
        ARM = 'Placebo';
        ARMCD = 'PBO';
    end;
    else if strip(RANDOMIZED_ARM) = 'Active Drug 50mg' then do;
        ARM = 'Active Drug 50mg';
        ARMCD = 'ACT50';
    end;
/* --------------------------------------------------------
       ISO 8601 DATE CONVERSION (YYYY-MM-DD)
       (Dynamic type-checking to prevent proc import errors)
       -------------------------------------------------------- */
    
    /* Handle Birth Date (BRTH_DT) */
    if vtype(BRTH_DT) = 'C' then _brth_num = input(strip(BRTH_DT), anydtdte.);
    else _brth_num = BRTH_DT;
    
    if not missing(_brth_num) then BRTHDTC = put(_brth_num, is8601da.);
    
    /* Handle Informed Consent Date (ICF_DAT) */
    if vtype(ICF_DAT) = 'C' then _rfic_num = input(strip(ICF_DAT), anydtdte.);
    else _rfic_num = ICF_DAT;
    
    if not missing(_rfic_num) then RFICDTC = put(_rfic_num, is8601da.);

    /* Sponsor-defined subject reference period: consent through end of participation. */
    RFSTDTC = RFICDTC;
    if vtype(STUDY_END_DAT) = 'C' then _rfend_num = input(strip(STUDY_END_DAT), anydtdte.);
    else _rfend_num = STUDY_END_DAT;
    if not missing(_rfend_num) then do;
        RFENDTC = put(_rfend_num, is8601da.);
        RFPENDTC = RFENDTC;
    end;
    
    /* Keep only variables that belong to the SDTM standard */
    keep STUDYID DOMAIN USUBJID SUBJID SITEID SEX RACE BRTHDTC RFSTDTC RFENDTC
         RFPENDTC RFICDTC ARM ARMCD;
run;


/* 4. VISUAL AUDIT (Quality Check) */
title "DM Domain Audit (First 10 Records)";
proc print data=sdtm.dm(obs=10);
    var STUDYID USUBJID SITEID SEX RACE BRTHDTC RFICDTC RFSTDTC RFENDTC RFPENDTC ARM ARMCD;
run;
title;
