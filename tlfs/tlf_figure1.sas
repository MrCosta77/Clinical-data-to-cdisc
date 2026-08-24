/*******************************************************************************
Program Name: tlf_figure1.sas
Description:  Generates Figure 1: Kaplan-Meier Survival Curve.
              Analyzes the Time to First Adverse Event using ADTTE.
*******************************************************************************/

/* 1. INITIALIZE MASTER CONFIGURATION */
/* Execute through RUN_ALL.SAS, which initializes PROJECT_PATH and libraries. */

/* Enable high-resolution graphics in SAS (Adjusted size to clear RTF margin warnings) */
ods graphics on / width=7in height=5.5in imagename="KM_Curve";

/* Open ODS RTF destination for Word export with classic Journal style */
ods rtf file="&project_path./tlfs/tlf_figure1.rtf" style=Journal;

title1 "Figure 1: Kaplan-Meier Event-Free Survival by Treatment";
title2 "Population: Safety Population";

proc lifetest data=adam.adtte plots=survival(atrisk);
    /* 
       The syntax "AVAL * CNSR(1)" instructs the statistical engine: 
       Evaluate survival time, but mathematically ignore (censor) subjects with CNSR = 1 
    */
    time AVAL * CNSR(1);
    
    /* STRATA divides the plot lines by actual treatment arms */
    strata TRT01A; 
run;

title;

/* Close ODS destinations */
ods rtf close;
ods graphics off;
