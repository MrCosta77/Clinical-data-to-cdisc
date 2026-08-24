/*******************************************************************************
Program Name: tlf_table1.sas
Description:  Generates Table 1: Demographics and Baseline Characteristics.
              Uses ODS RTF to export a professional Word document.
*******************************************************************************/

/* 1. INITIALIZE MASTER CONFIGURATION */
/* Execute through RUN_ALL.SAS, which initializes PROJECT_PATH and libraries. */

/* Open ODS RTF destination with Journal style without closing SAS Studio output */
ods rtf file="&project_path./tlfs/tlf_table1.rtf" style=Journal;

title1 "Table 1: Demographics and Baseline Characteristics";
title2 "Population: Intent-to-Treat (ITT)";

proc tabulate data=adam.adsl missing;
    /* Filter only randomized subjects */
    where ITTFL = 'Y'; 
    
    class TRT01P SEX RACE; 
    var AGE; 
    
    table 
        /* --- ROWS (Clean formatting and percentages) --- */
        ALL="Total Subjects" * N=""
        SEX="Sex" * (N="n" * f=5.0 ColPctN="%" * f=5.1)
        RACE="Race" * (N="n" * f=5.0 ColPctN="%" * f=5.1)
        AGE="Age (years)" * (N="n" * f=5.0 Mean="Mean" * f=5.1 Std="SD" * f=5.2 Min="Min" * f=5.0 Max="Max" * f=5.0),
        
        /* --- COLUMNS --- */
        (TRT01P="Planned Treatment" ALL="Total")
        
        / box="Demographic Parameter" row=float misstext="0";
run;

title;

/* Close only the RTF file */
ods rtf close;
