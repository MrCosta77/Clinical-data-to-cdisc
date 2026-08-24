/*******************************************************************************
Program Name: run_all.sas
Description:  Portable entry point for the complete Raw-to-SDTM-to-ADaM pipeline.

Instructions: Change PROJECT_PATH below to the absolute repository path in the
              current SAS environment, then execute this program.
*******************************************************************************/

%let project_path = /home/your-user/Clinical-data-to-cdisc;

%include "&project_path./programs/00_setup.sas";

/* Phase 1: Raw to SDTM. */
%include "&project_path./programs/sdtm_dm.sas";
%include "&project_path./programs/sdtm_ae.sas";
%include "&project_path./programs/sdtm_ex.sas";
%include "&project_path./programs/sdtm_lb.sas";
%include "&project_path./programs/sdtm_vs.sas";
%include "&project_path./programs/sdtm_cm.sas";
%include "&project_path./programs/sdtm_mh.sas";
%include "&project_path./programs/sdtm_eg.sas";
%include "&project_path./programs/sdtm_sv.sas";
%include "&project_path./programs/sdtm_ds.sas";

/* Phase 2: SDTM to ADaM. */
%include "&project_path./programs/adam_adsl.sas";
%include "&project_path./programs/adam_adae.sas";
%include "&project_path./programs/adam_advs.sas";
%include "&project_path./programs/adam_adlb.sas";
%include "&project_path./programs/adam_adtte.sas";

/* Phase 3: quality gate, outputs, and metadata. */
%include "&project_path./qc/qc_core.sas";
%include "&project_path./tlfs/tlf_table1.sas";
%include "&project_path./tlfs/tlf_figure1.sas";
%include "&project_path./programs/generate_define.sas";
