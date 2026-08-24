/*******************************************************************************
Program Name: adam_adtte.sas
Description:  Derivation of ADTTE (Time-to-Event Analysis Dataset).
              Calculates Time to First Adverse Event (Survival Analysis).
*******************************************************************************/

/* Execute through RUN_ALL.SAS, which initializes PROJECT_PATH and libraries. */

/* 1. GET FIRST ADVERSE EVENT PER SUBJECT */
proc sort data=adam.adae out=work.adae_first;
    by USUBJID AESTDT; 
    where TRTEMFL = 'Y'; 
run;

data work.ae_target;
    set work.adae_first;
    by USUBJID;
    if first.USUBJID;
    keep USUBJID AESTDT;
    rename AESTDT = EVENTDT; 
run;


proc sort data=adam.adsl out=work.adsl_sorted;
    by USUBJID;
run;

data adam.adtte;
    retain STUDYID USUBJID PARAMCD PARAM;
    
    merge work.adsl_sorted(in=a) work.ae_target(in=b);
    by USUBJID;
    
    if a and SAFFL = 'Y'; 

    PARAMCD = "TTFAEV";
    PARAM   = "Time to First Adverse Event";

    /* --------------------------------------------------------
       3. DERIVE CENSORING (CNSR) AND TIME (AVAL)
       -------------------------------------------------------- */
    if missing(TRTSDT) then do;
        CNSR = .;
        AVAL = .;
    end;
    else if not missing(EVENTDT) then do;
        /* The subject experienced the first treatment-emergent event. */
        CNSR = 0; 
        AVAL = (EVENTDT - TRTSDT) + 1;
    end;
    else do;
        /* Censor at the participant-specific end of study participation.
           Treatment end is not a substitute for end of clinical follow-up. */
        CNSR = 1;
        if not missing(EOSDT) then AVAL = (EOSDT - TRTSDT) + 1;
        else AVAL = .;
    end;

    keep STUDYID USUBJID TRT01P TRT01A TRTSDT TRTEDT EOSDT
         PARAMCD PARAM CNSR AVAL EVENTDT;
run;


/* 4. VISUAL AUDIT */
title "ADTTE Audit - Time to First Adverse Event";
proc print data=adam.adtte(obs=15);
    var USUBJID TRT01A PARAM CNSR AVAL EVENTDT EOSDT;
run;
title;
