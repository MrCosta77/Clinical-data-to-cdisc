/*******************************************************************************
Program Name: sdtm_mh.sas
Description:  Transforms raw Medical History data into CDISC SDTM MH domain.
*******************************************************************************/
/* Execute through RUN_ALL.SAS, which initializes PROJECT_PATH and libraries. */

proc import datafile="&project_path./data/raw/raw_mh.csv" 
    out=work.raw_mh dbms=csv replace; 
    getnames=yes; 
run;

data sdtm.mh;
    length STUDYID $8 DOMAIN $2 USUBJID $&usubjid_length. MHTERM $60 MHSTDTC $10;
    
    set work.raw_mh;
    
    STUDYID = "CDISC-01";
    DOMAIN = "MH";
    USUBJID = catx('-', STUDYID, strip(SUBJECT)); 
    MHTERM = strip(CONDITION);

    /* PROC IMPORT may infer DIAGNOSIS_DATE as a numeric SAS date. */
    if vtype(DIAGNOSIS_DATE) = 'C' then
        _mhdt = input(strip(DIAGNOSIS_DATE), anydtdte.);
    else _mhdt = DIAGNOSIS_DATE;

    if not missing(_mhdt) then MHSTDTC = put(_mhdt, is8601da.);

    keep STUDYID DOMAIN USUBJID MHTERM MHSTDTC;
run;

proc sort data=sdtm.mh; 
    by USUBJID MHSTDTC; 
run;

data sdtm.mh;
    retain STUDYID DOMAIN USUBJID MHSEQ MHTERM MHSTDTC; 
    set sdtm.mh; 
    by USUBJID; 
    if first.USUBJID then MHSEQ=1; 
    else MHSEQ+1; 

    keep STUDYID DOMAIN USUBJID MHSEQ MHTERM MHSTDTC;
run;
