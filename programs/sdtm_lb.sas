/*******************************************************************************
Program Name: sdtm_lb.sas
Description:  Mapping of raw EDC data to the SDTM LB (Laboratory) domain.
              Demonstrates conditional dictionary mapping for test codes, 
              categories, and standardization of SI units.
*******************************************************************************/

/* Execute through RUN_ALL.SAS, which initializes PROJECT_PATH and libraries. */

/* 1. IMPORT RAW LAB DATA */
proc import datafile="&project_path./data/raw/raw_lab.csv"
    out=work.raw_lb
    dbms=csv
    replace;
    getnames=yes;
run;


/* 2. CORE TRANSFORMATION & DICTIONARY MAPPING */
data work.lb_mapped;
    set work.raw_lb;
    
    /* Pre-define lengths to prevent truncation */
    length STUDYID $8 DOMAIN $2 USUBJID $&usubjid_length.
           LBTESTCD $8 LBTEST $40 LBCAT $20 LBORRES $20 LBORRESU $20
           LBSTRESC $20 LBSTRESU $20;
    
    /* Core Identifiers */
    STUDYID = "CDISC-01";
    DOMAIN  = "LB";
    USUBJID = catx("-", STUDYID, SUBJ);
    VISIT   = strip(VISIT_NAM);
    VISITNUM = VISIT_NUM;
    
    /* --------------------------------------------------------
       TEST CODES, CATEGORIES, AND UNITS MAPPING
       -------------------------------------------------------- */
    /* Note: In a real CRO, this is usually merged from a master Excel 
       dictionary or Medidata Rave/Codelist format. Here we hardcode the logic. */
       
    select (upcase(strip(TEST_NAME)));
        when ('GLUCOSE') do;
            LBTESTCD = 'GLUC';
            LBTEST   = 'Glucose';
            LBCAT    = 'CHEMISTRY';
        end;
        when ('HEMOGLOBIN') do;
            LBTESTCD = 'HGB';
            LBTEST   = 'Hemoglobin';
            LBCAT    = 'HEMATOLOGY';
        end;
        when ('ALT') do;
            LBTESTCD = 'ALT';
            LBTEST   = 'Alanine Aminotransferase';
            LBCAT    = 'CHEMISTRY';
        end;
        when ('AST') do;
            LBTESTCD = 'AST';
            LBTEST   = 'Aspartate Aminotransferase';
            LBCAT    = 'CHEMISTRY';
        end;
        otherwise do;
            LBTESTCD = 'UNKNOWN';
            LBTEST   = TEST_NAME;
            LBCAT    = 'UNKNOWN';
        end;
    end;
    
    /* Results Formatting */
    LBORRES  = strip(put(RESULT, best.)); /* Original as text */
    LBSTRESN = RESULT;                    /* Standard as numeric */
    LBSTRESC = LBORRES;                   /* Standard as text */
    
    /* Standardize units (Cleaning up 'mg/dL' vs 'MG/DL' from the EDC) */
    LBORRESU = strip(UNIT);
    if upcase(LBORRESU) = 'MG/DL' then LBSTRESU = 'mg/dL';
    else if upcase(LBORRESU) = 'G/DL' then LBSTRESU = 'g/dL';
    else if upcase(LBORRESU) = 'U/L' then LBSTRESU = 'U/L';
    else LBSTRESU = LBORRESU;
    
    /* --------------------------------------------------------
       ISO 8601 DATE CONVERSION
       -------------------------------------------------------- */
    if vtype(LAB_DAT) = 'C' then _lab_num = input(strip(LAB_DAT), anydtdte.);
    else _lab_num = LAB_DAT;
    
    if not missing(_lab_num) then LBDTC = put(_lab_num, is8601da.);
    
    keep STUDYID DOMAIN USUBJID VISITNUM VISIT LBTESTCD LBTEST LBCAT LBORRES LBORRESU LBSTRESC LBSTRESN LBSTRESU LBDTC;
run;


/* 3. GENERATE SEQUENCE NUMBER (LBSEQ) */
proc sort data=work.lb_mapped;
    by USUBJID LBDTC LBTESTCD;
run;

data sdtm.lb;
	retain STUDYID DOMAIN USUBJID LBSEQ;
    set work.lb_mapped;
    by USUBJID;
    
    /* Retain and increment a counter for each Subject */
    if first.USUBJID then LBSEQ = 1;
    else LBSEQ + 1;
run;


/* 4. VISUAL AUDIT */
title "LB Domain Audit (Laboratory Test Results)";
proc print data=sdtm.lb(obs=12);
    var USUBJID VISITNUM VISIT LBTESTCD LBCAT LBSTRESN LBSTRESU LBDTC;
run;
title;
