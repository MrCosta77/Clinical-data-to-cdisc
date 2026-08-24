/*******************************************************************************
Program Name: sdtm_ex.sas
Description:  Mapping of raw EDC data to the SDTM EX (Exposure) domain.
              Captures study drug administration, doses, and duration.
*******************************************************************************/

/* Execute through RUN_ALL.SAS, which initializes PROJECT_PATH and libraries. */

/* 1. IMPORT RAW EXPOSURE DATA */
proc import datafile="&project_path./data/raw/raw_exposure.csv"
    out=work.raw_ex
    dbms=csv
    replace;
    getnames=yes;
run;


/* 2. CORE TRANSFORMATION */
data work.ex_mapped;
    set work.raw_ex;
    
    /* Pre-define variable lengths to prevent SAS truncation */
    length STUDYID $8 DOMAIN $2 USUBJID $&usubjid_length.
           EXTRT $50 EXDOSU $20 EXSTDTC $10 EXENDTC $10;
    
    /* Core Identifiers */
    STUDYID = "CDISC-01";
    DOMAIN  = "EX";
    USUBJID = catx("-", STUDYID, PATIENT);
    
    /* Treatment Details */
    EXTRT  = strip(TREATMENT);
    EXDOSE = DOSE;
    EXDOSU = strip(UNIT);
    
    /* --------------------------------------------------------
       ISO 8601 DATE CONVERSION
       -------------------------------------------------------- */
    /* Start Date */
    if vtype(START_DATE) = 'C' then _start_num = input(strip(START_DATE), anydtdte.);
    else _start_num = START_DATE;
    
    if not missing(_start_num) then EXSTDTC = put(_start_num, is8601da.);
    
    /* End Date (Handling missing end dates) */
    if vtype(END_DATE) = 'C' then _end_num = input(strip(END_DATE), anydtdte.);
    else _end_num = END_DATE;
    
    if not missing(_end_num) then EXENDTC = put(_end_num, is8601da.);
    else EXENDTC = ""; /* Ongoing Exposure */
    
    keep STUDYID DOMAIN USUBJID EXTRT EXDOSE EXDOSU EXSTDTC EXENDTC;
run;


/* 3. GENERATE SEQUENCE NUMBER (EXSEQ) */
proc sort data=work.ex_mapped;
    by USUBJID EXSTDTC;
run;

data sdtm.ex;
	retain STUDYID DOMAIN USUBJID EXSEQ;
    set work.ex_mapped;
    by USUBJID;
    
    /* Retain and increment a counter for each Subject */
    if first.USUBJID then EXSEQ = 1;
    else EXSEQ + 1;
run;


/* 4. VISUAL AUDIT */
title "EX Domain Audit (Study Drug Exposure)";
proc print data=sdtm.ex(obs=10);
    var USUBJID EXSEQ EXTRT EXDOSE EXDOSU EXSTDTC EXENDTC;
run;
title;
