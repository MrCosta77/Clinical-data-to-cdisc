/*******************************************************************************
Program Name: sdtm_cm.sas
Description:  Creates SDTM Concomitant Medications (CM) domain.
              Maps real-world background medication to CDISC standards.
*******************************************************************************/

/* 1. INITIALIZE MASTER CONFIGURATION */
%include "/home/u64384931/Clinical-data-to-cdisc/programs/00_setup.sas";

/* 2. IMPORT RAW DATA (Defensive Programming: Bypassing PROC IMPORT) */
data work.raw_cm;
    /* Lemos o CSV diretamente, dizendo ao SAS para não adivinhar nada */
    infile "&project_path./data/raw/raw_conmeds.csv" delimiter=',' dsd missover firstobs=2;
    
    /* Forçamos as datas a entrar como texto seguro ($10.) */
    length SUBJECT $10 MEDICATION $50 DOSE $20 START_DT $10 END_DT $10 ONGOING $1;
    input SUBJECT $ MEDICATION $ DOSE $ START_DT $ END_DT $ ONGOING $;
run;

/* 3. PROCESS AND MAP TO SDTM */
data work.cm_draft;
    length STUDYID $8 DOMAIN $2 USUBJID $&usubjid_length.;
    set work.raw_cm;
    
    /* Identifiers */
    STUDYID = "CDISC-01";
    DOMAIN  = "CM";
    USUBJID = strip(STUDYID) || "-" || strip(SUBJECT);
    
    /* Medication Mapping */
    CMTRT = strip(MEDICATION);
    CMDECOD = upcase(CMTRT); /* Mocking standard dictionary coding (e.g., WHODrug) */
    
    /* Dose and Unit parsing */
    CMDOSE = input(scan(DOSE, 1, ' '), best.);
    CMDOSU = strip(scan(DOSE, 2, ' '));
    
    /* Dates to ISO 8601 (Agora a conversão funciona a 100% porque a origem é texto limpo!) */
    if not missing(START_DT) then do;
        _start = input(START_DT, ddmmyy10.);
        CMSTDTC = put(_start, is8601da.);
    end;
    
    if not missing(END_DT) then do;
        _end = input(END_DT, ddmmyy10.);
        CMENDTC = put(_end, is8601da.);
    end;
    
    /* Handle Ongoing Medications */
    if ONGOING = 'Y' then CMENRTPT = 'ONGOING';
    else CMENRTPT = '';
    
    keep STUDYID DOMAIN USUBJID CMTRT CMDECOD CMDOSE CMDOSU CMSTDTC CMENDTC CMENRTPT;
run;

/* 4. SORT AND ASSIGN SEQUENCE NUMBER (CMSEQ) */
proc sort data=work.cm_draft;
    by USUBJID CMSTDTC CMTRT;
run;

data sdtm.cm;
    /* Retain ensures strict CDISC column order */
    retain STUDYID DOMAIN USUBJID CMSEQ CMTRT CMDECOD CMDOSE CMDOSU CMSTDTC CMENDTC CMENRTPT;
    set work.cm_draft;
    by USUBJID;
    
    if first.USUBJID then CMSEQ = 1;
    else CMSEQ + 1;
run;

/* 5. VISUAL AUDIT */
title "SDTM CM Domain - Concomitant Medications";
proc print data=sdtm.cm(obs=15);
run;
title;
