# 🧬 CDISC-Inspired Clinical Data Pipeline (Raw to SDTM/ADaM)

An educational end-to-end clinical data pipeline demonstrating the transformation of raw, unstructured Electronic Data Capture (EDC) exports into **CDISC SDTM (Study Data Tabulation Model)** and **ADaM (Analysis Data Model)** datasets. 

This project is designed to showcase clinical data engineering, defensive SAS programming, and statistical analysis dataset derivation, culminating in a structural Define-XML v2.0 metadata prototype.

## 🚀 Core Engineering Philosophy
* **Educational Terminology Mapping:** Utilizes mock dictionaries to simulate MedDRA and CDISC Controlled Terminology mapping.
* **Defensive SAS Programming:** Extensive use of dynamic type-checking (`vtype`), `anydtdte` informats, and robust ISO 8601 date conversions (`is8601da.`) to prevent data loss from unstructured EDC formats.
* **Advanced Derivations:** Complex logic for ongoing clinical events, baseline flagging (`ABLFL`), and temporal treatment-emergent derivations (`TRTEMFL`).

## 📂 Target Architecture
The pipeline follows a rule-based clinical data transformation approach, culminating in survival analysis modeling and regulatory-grade presentation layers:

RAW EDC ──▶ SDTM (DM, AE, EX, LB, VS, CM, MH, EG, SV, DS) ──▶ ADaM (ADSL, ADAE, ADVS, ADLB, ADTTE) ──▶ QC Framework ──▶ TLFs & Define-XML

## 🛠️ Development Milestones

### Phase 1: SDTM Transformation
- **DM:** Core subject identifiers, ISO 8601 date standardizations, and Randomization Arms.
- **VS & LB:** Horizontal-to-vertical unpivoting (wide to long), conditional dictionary mapping, and parameter standardization.
- **AE, EX & CM:** Sequential numbering, clinical exposure mapping, and concomitant medications standardization.
- **MH & EG:** Retrospective medical history mapping and electrocardiogram signal standardization.
- **SV & DS:** Actual subject visits and final study disposition, tied to the subject reference period in DM.
- **Architecture Validation:** Implementation of `retain` statements to ensure strict CDISC column ordering (Identifiers first).

### Phase 2: ADaM Derivation & Clinical Logic
- **ADSL (Subject-Level):** Numeric analysis dates, demographic math (AGE), Treatment Duration, and Population Flags (ITTFL, SAFFL).
  - *Note on Misallocation:* The synthetic generator deliberately introduces treatment deviations (~5%) to realistically demonstrate complex derivations between the Intent-to-Treat (ITT) and Safety populations.
- **ADVS (Vital Signs):** Advanced Baseline derivations (`ABLFL`) resolving retained PDV memory, and Change from Baseline calculations.
- **ADLB (Laboratory Analysis):** Biochemical logic implementation, including on-the-fly SI unit conversions (e.g., Glucose mg/dL to mmol/L) and derivation of clinical abnormality indicators (`LBNRIND`).
- **ADTTE (Time-to-Event):** Survival analysis dataset modeling, calculating Time to First Adverse Event and applying mathematical right-censoring (`CNSR`) using study cutoff dates.

### Phase 3: Quality Control & TLFs
- **QC Framework:** Automated `PROC SQL` validation scripts to detect duplicate baselines, chronological anomalies, and referential integrity issues across domains. The pipeline triggers an `ABORT CANCEL` if critical data errors are detected.
- **TLFs (Tables, Listings, Figures):** Generation of regulatory-grade RTF outputs using ODS.
  - **Table 1:** Demographics and Baseline Characteristics (Intent-to-Treat population) using `PROC TABULATE`.
  - **Figure 1:** Kaplan-Meier Survival Curve estimating adverse event probabilities over time using `PROC LIFETEST`.
- **Define-XML v2.0:** Dynamic extraction of structural metadata using SAS dictionary tables (dictionary.columns) to generate a structural Define-XML v2.0 prototype, demonstrating automated metadata cataloging directly from the datasets.

## ⚙️ How to Reproduce this Pipeline

To run this project locally or in SAS OnDemand for Academics (SODA):

1. **Clone the repository:**
   `git clone https://github.com/your-username/Clinical-data-to-cdisc.git`

2. **Generate the Raw Data:**
   Run both Python generators in order. Their fixed random seeds reproduce the
   same cohort and all study events share the subject timeline defined in DM.
   `python scripts/generate_raw_edc.py`
   `python scripts/generate_extra_edc.py`

   Before uploading the data to SAS, install the pinned Python dependencies and
   run the raw acceptance gate. It validates schemas, keys, dates, controlled
   terminology, units, subject timelines, and the versioned golden hashes:
   `python -m pip install -r requirements.txt`
   `python scripts/validate_raw_contracts.py`
   `python -m pytest -v`

3. **Configure the SAS Environment:**
   * Upload the repository to your SAS environment.
   * Open `programs/00_setup.sas`.
   * Modify the `%let project_path = ...` variable to match your root directory.
   * Run `00_setup.sas` to initialize the global libraries (`raw`, `sdtm`, `adam`).

4. **Execute the Pipeline (Strict Execution Order):**
   In clinical programming, the ETL flow relies on strict hierarchical dependencies. You must execute the SAS programs in this exact order:
   * **Phase 1 (Raw to SDTM):** Run `sdtm_dm.sas`, then the remaining `sdtm_*.sas` programs, including `sdtm_sv.sas` and `sdtm_ds.sas`.
   * **Phase 2 (Core ADaM):** Run `adam_adsl.sas`. *(Crucial: This generates the Safety/ITT populations and treatment dates needed by all subsequent domains).*
   * **Phase 3 (Analysis Domains):** Run `adam_adae.sas`, `adam_advs.sas`, and `adam_adlb.sas`.
   * **Phase 4 (Survival Analysis):** Run `adam_adtte.sas`. *(Note: This explicitly depends on the derived ADAE dataset).*
   * **Phase 5 (Reporting & Validation):** Run `tlf_table1.sas`, `tlf_figure1.sas`, `qc_core.sas` (25 checks), and finally `generate_define.sas` to output the XML metadata dictionary.
