/*******************************************************************************
Program Name: generate_define.sas
Description:  Dynamically extracts metadata from SDTM and ADaM libraries and 
              generates a structural CDISC Define-XML v2.0 document.
*******************************************************************************/

/* Execute through RUN_ALL.SAS, which initializes PROJECT_PATH and libraries. */

/* 1. Extract structural metadata from SDTM and ADaM libraries */
proc sql noprint;
    create table meta_data as
    select upcase(libname) as libname, 
           upcase(memname) as dataset, 
           upcase(name) as variable, 
           type, length, format, label, varnum
    from dictionary.columns
    where libname in ('SDTM', 'ADAM')
    order by libname, dataset, varnum;
quit;

/* Enrich the structural metadata with controlled terminology, origins and
   explicit derivation methods. These rules are versioned with the programs. */
data meta_data;
    set meta_data;
    length codelist_oid method_oid $40 origin_type $12 origin_description $256;

    select (variable);
        when ('SEX') codelist_oid = 'CL.SEX';
        when ('RACE') codelist_oid = 'CL.RACE';
        when ('AESER', 'ITTFL', 'SAFFL') codelist_oid = 'CL.YN';
        when ('TRTEMFL', 'AOCCFL', 'ABLFL') codelist_oid = 'CL.Y';
        when ('AESEV') codelist_oid = 'CL.AESEV';
        when ('AEREL') codelist_oid = 'CL.AEREL';
        when ('AEOUT') codelist_oid = 'CL.AEOUT';
        when ('LBNRIND') codelist_oid = 'CL.LBNRIND';
        when ('CNSR') codelist_oid = 'CL.CNSR';
        otherwise codelist_oid = '';
    end;

    select (cats(dataset, '.', variable));
        when ('DM.USUBJID') method_oid = 'MT.DM.USUBJID';
        when ('DM.SITEID') method_oid = 'MT.DM.SITEID';
        when ('DM.RACE') method_oid = 'MT.DM.RACE';
        when ('CM.CMDECOD') method_oid = 'MT.CM.CMDECOD';
        when ('ADSL.TRT01P') method_oid = 'MT.ADSL.TRT01P';
        when ('ADSL.TRT01A') method_oid = 'MT.ADSL.TRT01A';
        when ('ADSL.ITTFL') method_oid = 'MT.ADSL.ITTFL';
        when ('ADSL.SAFFL') method_oid = 'MT.ADSL.SAFFL';
        when ('ADSL.AGE') method_oid = 'MT.ADSL.AGE';
        when ('ADSL.EOSDT') method_oid = 'MT.ADSL.EOSDT';
        when ('ADAE.TRTEMFL') method_oid = 'MT.ADAE.TRTEMFL';
        when ('ADAE.AOCCFL') method_oid = 'MT.ADAE.AOCCFL';
        when ('ADVS.ABLFL', 'ADVS.BASE', 'ADVS.CHG') method_oid = 'MT.ADVS.BASELINE';
        when ('ADLB.ABLFL', 'ADLB.BASE', 'ADLB.CHG') method_oid = 'MT.ADLB.BASELINE';
        when ('ADLB.LBNRIND') method_oid = 'MT.ADLB.LBNRIND';
        when ('ADTTE.CNSR', 'ADTTE.AVAL') method_oid = 'MT.ADTTE.TTFAEV';
        otherwise method_oid = '';
    end;

    if variable in ('STUDYID', 'DOMAIN') then do;
        origin_type = 'Assigned';
        origin_description = 'Assigned according to the study convention.';
    end;
    else if libname = 'ADAM' then do;
        origin_type = 'Derived';
        origin_description = 'Derived from SDTM inputs and the versioned ADaM program.';
    end;
    else do;
        origin_type = 'Derived';
        origin_description = 'Derived from the source EDC extract by the versioned SDTM program.';
    end;
run;

/* 2. Initialize XML File and Write Header */
data _null_;
    file "&project_path./tlfs/define.xml" encoding="utf-8";
    put '<?xml version="1.0" encoding="UTF-8"?>';
    put '<ODM xmlns="http://www.cdisc.org/ns/odm/v1.3" xmlns:def="http://www.cdisc.org/ns/def/v2.0" FileType="Snapshot">';
    put '  <Study OID="STU.001">';
    put '    <GlobalVariables>';
    put '      <StudyName>Portfolio Clinical Trial</StudyName>';
    put '      <StudyDescription>End-to-End CDISC Pipeline Automation</StudyDescription>';
    put '      <ProtocolName>CDISC-001</ProtocolName>';
    put '    </GlobalVariables>';
    put '    <MetaDataVersion OID="MDV.001" Name="Study Metadata" def:DefineVersion="2.0.0">';
run;

/* 3. Write ItemGroupDefs (Datasets mapping) */
data _null_;
    set meta_data;
    by libname dataset;
    file "&project_path./tlfs/define.xml" mod encoding="utf-8";
    
    length ds_name $32 var_name $32 lib_name $10 repeating $3 line $1024;
    ds_name = strip(dataset);
    var_name = strip(variable);
    lib_name = strip(libname);
    
    if first.dataset then do;
        if ds_name in ('DM', 'ADSL') then repeating = 'No';
        else repeating = 'Yes';
        line = cats('      <ItemGroupDef OID="IG.', ds_name,
                    '" Name="', ds_name,
                    '" Repeating="', repeating, '" IsReferenceData="No">');
        put line;
        line = cats('        <Description><TranslatedText>', ds_name,
                    ' Dataset (', lib_name,
                    ')</TranslatedText></Description>');
        put line;
    end;

    if not missing(method_oid) then
        line = cats('        <ItemRef ItemOID="IT.', ds_name, '.', var_name,
                    '" Mandatory="No" MethodOID="', strip(method_oid), '"/>');
    else
        line = cats('        <ItemRef ItemOID="IT.', ds_name, '.', var_name,
                    '" Mandatory="No"/>');
    put line;
    
    if last.dataset then do;
        put '      </ItemGroupDef>';
    end;
run;

/* 4. Write ItemDefs (Variables mapping) */
proc sort data=meta_data nodupkey out=unique_vars;
    by libname dataset variable;
run;

data _null_;
    set unique_vars;
    file "&project_path./tlfs/define.xml" mod encoding="utf-8";
    
    length ds_name $32 var_name $32 var_lbl $256 dt_type $10 len_str $5
           fmt_name $49
           line $1024;
    ds_name = strip(dataset);
    var_name = strip(variable);
    var_lbl = strip(label);
    if missing(var_lbl) then var_lbl = var_name; /* Fallback caso não tenha label */
    
    fmt_name = upcase(strip(format));
    if type = 'char' then dt_type = 'text';
    else if prxmatch('/DATETIME|E8601DT|B8601DT/', fmt_name) then
        dt_type = 'datetime';
    else if prxmatch('/DATE|YYMMDD|MMDDYY|DDMMYY|E8601DA|B8601DA/', fmt_name) then
        dt_type = 'date';
    else if prxmatch('/TIME|E8601TM|B8601TM/', fmt_name) then
        dt_type = 'time';
    else if variable in ('AGE', 'CNSR', 'N_FAIL', 'TRTDURD')
         or prxmatch('/SEQ$/', strip(variable))
         or prxmatch('/DY$/', strip(variable)) then
        dt_type = 'integer';
    else dt_type = 'float';
    
    len_str = strip(put(length, best.));
    
    line = cats('      <ItemDef OID="IT.', ds_name, '.', var_name,
                '" Name="', var_name, '" DataType="', dt_type,
                '" Length="', len_str, '">');
    put line;
    line = cats('        <Description><TranslatedText>', var_lbl,
                '</TranslatedText></Description>');
    put line;

    if not missing(codelist_oid) then do;
        line = cats('        <CodeListRef CodeListOID="',
                    strip(codelist_oid), '"/>');
        put line;
    end;

    line = cats('        <def:Origin Type="', strip(origin_type), '">');
    put line;
    line = cats('          <Description><TranslatedText>',
                strip(origin_description), '</TranslatedText></Description>');
    put line;
    put '        </def:Origin>';
    put '      </ItemDef>';
run;

/* 5. Write controlled terminology used by the generated ItemDefs */
data _null_;
    file "&project_path./tlfs/define.xml" mod encoding="utf-8";
    put '      <CodeList OID="CL.SEX" Name="Sex" DataType="text">';
    put '        <CodeListItem CodedValue="M"><Decode><TranslatedText>Male</TranslatedText></Decode></CodeListItem>';
    put '        <CodeListItem CodedValue="F"><Decode><TranslatedText>Female</TranslatedText></Decode></CodeListItem>';
    put '        <CodeListItem CodedValue="U"><Decode><TranslatedText>Unknown</TranslatedText></Decode></CodeListItem>';
    put '      </CodeList>';
    put '      <CodeList OID="CL.RACE" Name="Race" DataType="text">';
    put '        <CodeListItem CodedValue="WHITE"/>';
    put '        <CodeListItem CodedValue="BLACK OR AFRICAN AMERICAN"/>';
    put '        <CodeListItem CodedValue="ASIAN"/>';
    put '        <CodeListItem CodedValue="OTHER"/>';
    put '        <CodeListItem CodedValue="UNKNOWN"/>';
    put '      </CodeList>';
    put '      <CodeList OID="CL.YN" Name="Yes No" DataType="text">';
    put '        <CodeListItem CodedValue="Y"><Decode><TranslatedText>Yes</TranslatedText></Decode></CodeListItem>';
    put '        <CodeListItem CodedValue="N"><Decode><TranslatedText>No</TranslatedText></Decode></CodeListItem>';
    put '      </CodeList>';
    put '      <CodeList OID="CL.Y" Name="Yes Flag" DataType="text">';
    put '        <CodeListItem CodedValue="Y"><Decode><TranslatedText>Yes</TranslatedText></Decode></CodeListItem>';
    put '      </CodeList>';
    put '      <CodeList OID="CL.AESEV" Name="Adverse Event Severity" DataType="text">';
    put '        <CodeListItem CodedValue="MILD"/><CodeListItem CodedValue="MODERATE"/><CodeListItem CodedValue="SEVERE"/>';
    put '      </CodeList>';
    put '      <CodeList OID="CL.AEREL" Name="Adverse Event Relationship" DataType="text">';
    put '        <CodeListItem CodedValue="RELATED"/><CodeListItem CodedValue="NOT RELATED"/><CodeListItem CodedValue="UNKNOWN"/>';
    put '      </CodeList>';
    put '      <CodeList OID="CL.AEOUT" Name="Adverse Event Outcome" DataType="text">';
    put '        <CodeListItem CodedValue="RECOVERED/RESOLVED"/><CodeListItem CodedValue="NOT RECOVERED/NOT RESOLVED"/>';
    put '      </CodeList>';
    put '      <CodeList OID="CL.LBNRIND" Name="Reference Range Indicator" DataType="text">';
    put '        <CodeListItem CodedValue="LOW"/><CodeListItem CodedValue="NORMAL"/><CodeListItem CodedValue="HIGH"/><CodeListItem CodedValue="UNKNOWN"/>';
    put '      </CodeList>';
    put '      <CodeList OID="CL.CNSR" Name="Censoring" DataType="integer">';
    put '        <CodeListItem CodedValue="0"><Decode><TranslatedText>Event</TranslatedText></Decode></CodeListItem>';
    put '        <CodeListItem CodedValue="1"><Decode><TranslatedText>Censored</TranslatedText></Decode></CodeListItem>';
    put '      </CodeList>';
run;

/* 6. Write the principal derivation methods referenced by ItemRef */
data _null_;
    file "&project_path./tlfs/define.xml" mod encoding="utf-8";
    put '      <MethodDef OID="MT.DM.USUBJID" Name="Unique Subject Identifier" Type="Computation"><Description><TranslatedText>Concatenate STUDYID and SUBJID with a hyphen.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.DM.SITEID" Name="Site Identifier" Type="Computation"><Description><TranslatedText>Copy SITE from the raw demographic record after type-safe character conversion.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.DM.RACE" Name="Race Terminology Mapping" Type="Computation"><Description><TranslatedText>Map the EDC race label to the supported CDISC controlled term.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.CM.CMDECOD" Name="Medication Normalization" Type="Computation"><Description><TranslatedText>Normalize the approved Paracetamol source synonym to the standard ingredient name Acetaminophen; retain the uppercase source name for the remaining educational dictionary entries.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.ADSL.TRT01P" Name="Planned Treatment" Type="Computation"><Description><TranslatedText>Derive planned treatment from the randomized arm in DM.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.ADSL.TRT01A" Name="Actual Treatment" Type="Computation"><Description><TranslatedText>Derive actual treatment from the first exposure record in EX.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.ADSL.ITTFL" Name="Intent-to-Treat Flag" Type="Computation"><Description><TranslatedText>Set to Y for randomized subjects and N for screen failures.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.ADSL.SAFFL" Name="Safety Population Flag" Type="Computation"><Description><TranslatedText>Set to Y when at least one exposure start date is present.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.ADSL.AGE" Name="Age" Type="Computation"><Description><TranslatedText>Calculate completed years between birth and informed consent using SAS YRDIF with the AGE basis.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.ADSL.EOSDT" Name="End of Subject Follow-up" Type="Computation"><Description><TranslatedText>Convert DM.RFPENDTC to a numeric SAS date for participant-specific follow-up and censoring.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.ADAE.TRTEMFL" Name="Treatment-Emergent Flag" Type="Computation"><Description><TranslatedText>Set to Y when a safety subject event starts on or after first dose.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.ADAE.AOCCFL" Name="First Treatment-Emergent Occurrence" Type="Computation"><Description><TranslatedText>Set to Y on the chronologically first treatment-emergent occurrence per subject and decoded term.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.ADVS.BASELINE" Name="Vital Signs Baseline and Change" Type="Computation"><Description><TranslatedText>Select the exact source record with the latest nonmissing value on or before treatment start; same-day ambiguity is rejected by QC when collection time is unavailable.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.ADLB.BASELINE" Name="Laboratory Baseline and Change" Type="Computation"><Description><TranslatedText>Select the exact source record with the latest nonmissing value on or before treatment start; same-day ambiguity is rejected by QC when collection time is unavailable.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.ADLB.LBNRIND" Name="Laboratory Range Indicator" Type="Computation"><Description><TranslatedText>Classify the standardized analysis value using the parameter-specific reference range.</TranslatedText></Description></MethodDef>';
    put '      <MethodDef OID="MT.ADTTE.TTFAEV" Name="Time to First Adverse Event" Type="Computation"><Description><TranslatedText>Calculate inclusive days from treatment start to the first treatment-emergent event; subjects without an event are censored at their participant-specific ADSL.EOSDT derived from DM.RFPENDTC.</TranslatedText></Description></MethodDef>';
run;

/* 7. Close XML Tags */
data _null_;
    file "&project_path./tlfs/define.xml" mod encoding="utf-8";
    put '    </MetaDataVersion>';
    put '  </Study>';
    put '</ODM>';
run;
