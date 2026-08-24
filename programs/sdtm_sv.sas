/*******************************************************************************
Program Name: sdtm_sv.sas
Description:  Creates one SDTM SV record for each actual subject visit.
*******************************************************************************/

/* Execute through RUN_ALL.SAS, which initializes PROJECT_PATH and libraries. */

proc import datafile="&project_path./data/raw/raw_vitals.csv"
    out=work.raw_sv dbms=csv replace;
    getnames=yes;
run;

data sdtm.sv;
    length STUDYID $8 DOMAIN $2 USUBJID $&usubjid_length. VISIT $40
           SVSTDTC SVENDTC $10;
    retain STUDYID DOMAIN USUBJID VISITNUM VISIT VISITDY SVSTDTC SVENDTC;
    set work.raw_sv;

    STUDYID = "CDISC-01";
    DOMAIN = "SV";
    USUBJID = catx("-", STUDYID, PT_ID);
    VISITNUM = VISIT_NUM;
    VISIT = strip(VISIT);
    select (VISITNUM);
        when (1) VISITDY = 1;
        when (2) VISITDY = 31;
        when (3) VISITDY = 61;
        otherwise VISITDY = .;
    end;

    /*
       VVALUE works for either a character date or a formatted numeric SAS date.
       Width 32 is explicit so DATE11 values such as 15-JAN-2023 are not
       truncated to 15-JAN-20 and misread as a date in 2020.
    */
    _svdt = input(strip(vvalue(VS_DATE)), anydtdte32.);
    if not missing(_svdt) then do;
        SVSTDTC = put(_svdt, is8601da.);
        SVENDTC = SVSTDTC;
    end;

    keep STUDYID DOMAIN USUBJID VISITNUM VISIT VISITDY SVSTDTC SVENDTC;
run;

/* Sort without deleting records: duplicate keys must remain visible to QC. */
proc sort data=sdtm.sv;
    by USUBJID VISITNUM;
run;

title "SV Domain Audit";
proc print data=sdtm.sv(obs=12);
run;
title;
