/*******************************************************************************
Program Name: sdtm_ae.sas
Description:  Mapping of raw EDC data to the SDTM AE (Adverse Events) domain.
              Demonstrates derivation of Sequence Numbers (AESEQ), dictionary 
              mapping placeholders, and handling of ongoing clinical events.
*******************************************************************************/

%include "/home/u64384931/Clinical-data-to-cdisc/programs/00_setup.sas";

/* 1. IMPORT RAW ADVERSE EVENTS */
proc import datafile="&project_path./data/raw/raw_ae.csv"
    out=work.raw_ae
    dbms=csv
    replace;
    getnames=yes;
    /* Scan the complete synthetic extract so longer terms are not truncated. */
    guessingrows=max;
run;


/* 2. CORE TRANSFORMATION & DERIVATION */
data work.ae_mapped;
    set work.raw_ae;
    
    /* Pre-define variable lengths to prevent SAS truncation */
    length STUDYID $8 DOMAIN $2 USUBJID $&usubjid_length.
           AETERM AEDECOD $60 AEREL $15 AESEV $10 AEOUT $30 AESER $1;
    
    /* Core Identifiers */
    STUDYID = "CDISC-01";
    DOMAIN  = "AE";
    USUBJID = catx("-", STUDYID, ID);
    
    /* --------------------------------------------------------
       EVENT TERMINOLOGY & ATTRIBUTES
       -------------------------------------------------------- */
    AETERM = strip(AE_TERM);
    AEDECOD = upcase(AETERM);
    
    /* Severity */
    AESEV = upcase(strip(SEV));
    
    /* Serious Event Flag */
    if upcase(strip(SERIOUS)) = 'Y' then AESER = 'Y';
    else AESER = 'N';
    
    /* Causality / Relationship to Study Drug */
    if upcase(strip(RELATED)) = 'Y' then AEREL = 'RELATED';
    else if upcase(strip(RELATED)) = 'N' then AEREL = 'NOT RELATED';
    else AEREL = 'UNKNOWN';
    
    /* --------------------------------------------------------
       ISO 8601 DATE CONVERSION & OUTCOME DERIVATION
       -------------------------------------------------------- */
    if vtype(START) = 'C' then _start_num = input(strip(START), anydtdte.);
    else _start_num = START;
    if not missing(_start_num) then AESTDTC = put(_start_num, is8601da.);
    
    if vtype(END) = 'C' then _end_num = input(strip(END), anydtdte.);
    else _end_num = END;
    
    if not missing(_end_num) then do;
        AEENDTC = put(_end_num, is8601da.);
        AEOUT   = 'RECOVERED/RESOLVED';
    end;
    else do;
        AEENDTC = "";
        AEOUT   = 'NOT RECOVERED/NOT RESOLVED';
    end;

    keep STUDYID DOMAIN USUBJID AETERM AEDECOD AESEV AESER AEREL AESTDTC AEENDTC AEOUT;
run;


/* 3. GENERATE SEQUENCE NUMBER (AESEQ) */
/* Sort by Subject and Start Date first to ensure chronological sequence */
proc sort data=work.ae_mapped;
    by USUBJID AESTDTC;
run;

/* Use BY-group processing to create the Sequence Number */
data sdtm.ae;
	retain STUDYID DOMAIN USUBJID AESEQ;
    set work.ae_mapped;
    by USUBJID;
    
    /* Retain and increment a counter for each Subject */
    if first.USUBJID then AESEQ = 1;
    else AESEQ + 1;
run;


/* 4. VISUAL AUDIT */
title "AE Domain Audit (Adverse Events with Ongoing Logic)";
proc print data=sdtm.ae(obs=12);
    var USUBJID AESEQ AETERM AESEV AESER AEREL AESTDTC AEENDTC AEOUT;
run;
title;
