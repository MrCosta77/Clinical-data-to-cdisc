/*******************************************************************************
Program Name: sdtm_vs.sas
Description:  Mapping of raw EDC data to the SDTM VS (Vital Signs) domain.
              Demonstrates horizontal-to-vertical unpivoting and unit mapping.
*******************************************************************************/

%include "/home/u64384931/Clinical-data-to-cdisc/programs/00_setup.sas";

/* 1. IMPORT RAW VITALS */
proc import datafile="&project_path./data/raw/raw_vitals.csv"
    out=work.raw_vs
    dbms=csv
    replace;
    getnames=yes;
run;


/* 2. HORIZONTAL TO VERTICAL TRANSFORMATION (UNPIVOT) */
data work.vs_mapped;
    set work.raw_vs;
    
    length STUDYID $8 DOMAIN $2 USUBJID $&usubjid_length.
           VSTESTCD $8 VSTEST $40 VSORRESU VSSTRESU $20 VSORRES $200;

    STUDYID = "CDISC-01";
    DOMAIN  = "VS";
    USUBJID = catx("-", STUDYID, PT_ID); 
    VISITNUM = VISIT_NUM;

    if vtype(VS_DATE) = 'C' then _vs_num = input(strip(VS_DATE), anydtdte.);
    else _vs_num = VS_DATE;
    if not missing(_vs_num) then VSDTC = put(_vs_num, is8601da.);

    /* 1. Systolic Blood Pressure */
    if not missing(SYS_BP) then do;
        VSTESTCD = "SYSBP";
        VSTEST   = "Systolic Blood Pressure";
        VSORRES  = strip(put(SYS_BP, best.));
        VSSTRESN = SYS_BP;
        VSORRESU = "mmHg";
        VSSTRESU = "mmHg";
        output;
    end;

    /* 2. Diastolic Blood Pressure */
    if not missing(DIA_BP) then do;
        VSTESTCD = "DIABP";
        VSTEST   = "Diastolic Blood Pressure";
        VSORRES  = strip(put(DIA_BP, best.));
        VSSTRESN = DIA_BP;
        VSORRESU = "mmHg";
        VSSTRESU = "mmHg";
        output;
    end;

    /* 3. Heart Rate -> CDISC Official: PULSE */
    if not missing(HR_BPM) then do;
        VSTESTCD = "PULSE";
        VSTEST   = "Pulse Rate";
        VSORRES  = strip(put(HR_BPM, best.));
        VSSTRESN = HR_BPM;
        VSORRESU = "beats/min";
        VSSTRESU = "beats/min";
        output;
    end;

    /* 4. Weight */
    if not missing(WEIGHT_KG) then do;
        VSTESTCD = "WEIGHT";
        VSTEST   = "Weight";
        VSORRES  = strip(put(WEIGHT_KG, best.));
        VSSTRESN = WEIGHT_KG;
        VSORRESU = "kg";
        VSSTRESU = "kg";
        output;
    end;

    keep STUDYID DOMAIN USUBJID VISITNUM VISIT VSDTC VSTESTCD VSTEST VSORRES VSORRESU VSSTRESN VSSTRESU;
run;


/* 3. GENERATE SEQUENCE NUMBER (VSSEQ) */
proc sort data=work.vs_mapped;
    by USUBJID VSDTC VSTESTCD;
run;

data sdtm.vs;
	retain STUDYID DOMAIN USUBJID VSSEQ;
    set work.vs_mapped;
    by USUBJID;
    if first.USUBJID then VSSEQ = 1;
    else VSSEQ + 1;
run;


/* 4. VISUAL AUDIT */
title "VS Domain Audit (Unpivoted Format with VSSEQ)";
proc print data=sdtm.vs(obs=12);
    var USUBJID VSSEQ VISITNUM VISIT VSDTC VSTESTCD VSSTRESN VSSTRESU;
run;
title;
