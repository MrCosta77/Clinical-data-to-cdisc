/*******************************************************************************
Program Name: sdtm_ds.sas
Description:  Creates the final study disposition for every subject.
*******************************************************************************/

%include "/home/u64384931/Clinical-data-to-cdisc/programs/00_setup.sas";

proc import datafile="&project_path./data/raw/raw_demog.csv"
    out=work.raw_ds dbms=csv replace;
    getnames=yes;
run;

data sdtm.ds;
    length STUDYID $8 DOMAIN $2 USUBJID $&usubjid_length. DSCAT DSSCAT $40
           DSTERM DSDECOD $80 EPOCH $20 DSSTDTC $10;
    retain STUDYID DOMAIN USUBJID DSSEQ DSCAT DSSCAT DSTERM DSDECOD EPOCH DSSTDTC;
    set work.raw_ds;

    STUDYID = "CDISC-01";
    DOMAIN = "DS";
    USUBJID = catx("-", STUDYID, SUBJ_ID);
    DSSEQ = 1;
    DSCAT = "DISPOSITION EVENT";
    DSSCAT = "STUDY PARTICIPATION";
    DSTERM = upcase(strip(DISPOSITION_REASON));
    DSDECOD = DSTERM;
    if upcase(strip(DISPOSITION)) = "SCREEN FAILURE" then EPOCH = "SCREENING";
    else EPOCH = "FOLLOW-UP";

    if vtype(STUDY_END_DAT) = 'C' then _dsdt = input(strip(STUDY_END_DAT), anydtdte.);
    else _dsdt = STUDY_END_DAT;
    if not missing(_dsdt) then DSSTDTC = put(_dsdt, is8601da.);

    keep STUDYID DOMAIN USUBJID DSSEQ DSCAT DSSCAT DSTERM DSDECOD EPOCH DSSTDTC;
run;

proc sort data=sdtm.ds nodupkey;
    by USUBJID DSSEQ;
run;

title "DS Domain Audit";
proc print data=sdtm.ds(obs=12);
run;
title;
