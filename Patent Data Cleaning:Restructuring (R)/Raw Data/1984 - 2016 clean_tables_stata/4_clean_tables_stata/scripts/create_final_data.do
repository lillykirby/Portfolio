set more off
clear all
version 15
cap log close

* path to working directory
global working 	/proj/pheidiw/raw/orange_book_exclusivity_public/

* set up log file
log using ${working}4_clean_tables_stata/scripts/create_final_data.log, text replace

* paths to working directory subfolders
global PDF 	 ${working}1_orange_book_PDFs/full_books_1980-2016/ 			// FOIA'd Orange Books 
global rawtables ${working}2_hand_entered_by_firm_excel/tables_1985-2004/ 		// firm-entered tables
global rawabbs	 ${working}2_hand_entered_by_firm_excel/abbreviations_1985-2004/ 	// firm-entered abbreviations
global check1	 ${working}3_cross_check_sources/downloaded_from_FDA_PDFs_2000-2004/	// Downloaded from FDA	
global check2	 ${working}3_cross_check_sources/hand_entered_stata_1985-1999/		// Hand-entered from public files
global discrep 	 ${working}4_clean_tables_stata/exported_discrepancies_excel/   	// For discrepancies that need settled
global correct	 ${working}4_clean_tables_stata/corrected_discrepancies_excel/  	// For settled discrepancies
global temp 	 ${working}4_clean_tables_stata/temp/			    		// For intermediate Stata files
global dta 	 ${working}4_clean_tables_stata/				    	// For final Stata files
global txt 	 ${working}4_clean_tables_stata/txt/			    		// For converted PDF files

* create subdirectories that may not exist
! mkdir ${temp}
! mkdir ${txt}
! mkdir ${discrep}

* install commands
ssc install mdesc

*-------------------- CREATE PATENT AND EXCLUSIVITY TABLES --------------------*

********************************************************************************
********************************************************************************
*********** STEP 1: CREATE DATA FOR 2005-2016 **********************************
********************************************************************************
********************************************************************************
* For years 1985-1999, we use data from the directory /paper_orange_book/ as our comparison source
* For years 2000-2015, we use data that we convert from .pdf to .txt (and then parse into .dta form) as our comparison source

* set page limits for each orange book's pdftotext
* this is needed to use linux pdftotext command
clear all
input 	year	start	end
	2005	872	1004
	2006	855	990
	2007	883	1033
	2008	908	1064
	2009	939	1117
	2010	872	1067
	2011	1001	1203
	2012	1041	1247
	2013	1065	1291
	2014	955	1169
	2015	985	1213
	2016	1023	1247
end

	* generate edition variable
	gen edition = year - 1980

	* create local macros with parameters for each year
forvalues year = 2005/2016 {
	preserve
		keep if year==`year'
		local `year'start = start
		local `year'end = end
		local `year'edition = edition
		di "`year' ``year'start' ``year'end' ``year'edition'"
	restore
	}

* import and save .txt after converting from .pdf
forvalues year = 2005/2016 {
	di "Executing pdftotext for year `year'"
	! pdftotext -layout -nopgbrk -f ``year'start' -l ``year'end' "${PDF}`year'.pdf" ${txt}OB_`year'.txt
	}

* Parse data for orange books 2005-2015
* these are in a different format than 2000-2004. 2000-2004 editions will be parsed below
forvalues year = 2005/2016{
	* import .txt file from pdfttotext
	* import all as one column using "^" as a delimiter
	import delim using ${txt}OB_`year'.txt, clear delim("^")
	assert c(k)==1
	rename v1 var
	
	* get rid of tabs
	replace var = upper(trim(itrim(subinstr(var, char(9), " ", .))))
	* drop non-data lines
	drop if mi(var)
	foreach item in "APPROVED DRUG PRODUCT LIST" "PRESCRIPTION AND OTC DRUG PRODUCT" ///
		"FOOTNOTE" "APPL/PROD" "EXCLUSIVITY" "PATENT" "CODE(S)" "EXPIRATION" "REQUESTED" "314.53(D)(5)." ///
		"DS =" "DP =" "U AND NUMBER =" "HTTP:" "THEY MAY NOT BE" "NUMBER NUMBER" "314.53(C)" {
		drop if strpos(var, "`item'")
		}
	drop if var == "DATE"
	drop if var == "DATE CODES"
	drop if var == "CODES"
	drop if var == "DELIST"
	drop if regexm(var, "^ADA [0-9]+$")
	drop if regexm(var, "^ADA \- [0-9]+")
	drop if regexm(var, "ADA [0-9]+ OF [0-9]+")
	
	* for 2016 OB there is an error in PDF
	if `year'==2016 {
		replace var = "N 207920 001 5900424 MAY 04, 2016 DS U-1783" if var=="N 207920 01 5900424 MAY 04, 2016 DS U-1783"
		}
	* flag if line includes application and product number
	* this is one of the lines that comes before the patent/exclusivity information
	gen new_product = regexm(var, "^[NA]?[ ]?[0-9][0-9][0-9][0-9][0-9][0-9] [0-9][0-9][0-9]")

	* the trade name/active_ingredient comes in the previous oneor two or three lines
	* first flag the line that precedes a line with an application and product number
	* active ingredients and trade names are on this flagged line
	gen name = (new_product[_n+1]==1)
	
	* some of the active ingredients and trade names span two lines
	* we can spot these when a line is greater than 70 characters
	list if length(var) > 70 // eye-check shows these are all drug ingredients/trade names
	replace name = 1 if length(var) > 70
	
	* now concatenate ingredients/trade names split across multiple lines
	assert name==1 if _n==1
	gen name_start = (name[_n-1]==0 & name==1) | _n==1

	replace var = var + " " + var[_n+1] if name_start==1 & name[_n+1]==1
	drop if name==1 & name_start[_n-1]==1

	replace var = var + " " + var[_n+1] if name_start==1 & name[_n+1]==1
	drop if name==1 & name_start[_n-1]==1
	
	assert name_start==name
	drop name_start
	assert name==0 if new_product==1
	assert new_product==0 if name==1
	list var if name
		
	* for 2000-2009, trade name appears after last ";"
	if inrange(`year', 2005, 2009) {
		assert strpos(var, ";") if name==1
		gen name_reverse = reverse(var) if name==1
		gen trade_name = substr(name_reverse, 1, strpos(name_reverse, " ;")-1)
		gen active_ingredient = substr(name_reverse, strpos(name_reverse, " ;")+2, .)
		replace trade_name = reverse(trade_name)
		replace active_ingredient = reverse(active_ingredient)
		drop name_reverse
		foreach var in trade_name active_ingredient {
			assert `var' == trim(itrim(`var'))
			}
			
		assert var == active_ingredient + "; " + trade_name if name==1
		}
	
	if inrange(`year', 2010, 2016) {
		* generate active ingredient and trade name variables
		* assert presence of only one " - " in name lines
		assert (length(var) - length(subinstr(var, " - ", "", .))) == 3 if name==1
		gen active_ingredient = substr(var, 1, strpos(var, " - ")-1) if name==1
		assert !mi(active_ingredient) if name==1
	
		* now do trade name
		gen trade_name = substr(var, strpos(var, " - ")+3, .) if name==1
		assert !mi(trade_name) if name==1
	
		* do extra check
		assert var == active_ingredient + " - " + trade_name if name==1
		}
		
	* we can assert that they have " - ", which separates the ingredients and trade name
	*assert regexm(var, " \- ") if name==1
	*assert !regexm(var, " \- ") if name!=1
	* we can also make sure names have no other data fields in them, such as date, patent, or application number
	* dates
	assert !regexm(var, "[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]") if name==1
	* application numbers
	assert !regexm(var, "[NA]?[ ]?[0-9][0-9][0-9][0-9][0-9][0-9]") if name==1
	* patent numbers
	assert !regexm(var, "(((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?)") if name==1
	
	* now fill in trade name and active ingredient
	foreach var in trade_name active_ingredient {
		replace `var' = `var'[_n-1] if mi(`var')
		assert !mi(`var')
		}
	* drop the observations that had just names
	drop if name==1
	drop name
	
	* now grab application and product numbers
	gen application_number = regexs(1) if regexm(var, "^([NA]?[ ]?[0-9][0-9][0-9][0-9][0-9][0-9]) ([0-9][0-9][0-9])")
	gen product_number = regexs(2) if regexm(var, "^([NA]?[ ]?[0-9][0-9][0-9][0-9][0-9][0-9]) ([0-9][0-9][0-9])")
	
	* remove application and product numbers from var
	replace var = regexr(var, "^([NA]?[ ]?[0-9][0-9][0-9][0-9][0-9][0-9]) ([0-9][0-9][0-9])", "")
	assert !mi(application_number, product_number) if new_product
	
	* fill in application and product number
	foreach var in application_number product_number {
		replace `var' = `var'[_n-1] if mi(`var')
		assert !mi(`var')
		}
	replace application_number = subinstr(application_number, " ", "", .)
	replace var = trim(itrim(var))
	drop if mi(var)
	
	* check that every line starts with patent or exclusivity code
	* fix if it does not
	gen OK = 0
	foreach item in NC NCE NCE* NDF NE NP NP* NPP NR GAIN NS ODE PC PED RTO RTO* RTO** W PP {
		replace OK = 1 if strpos(var, "`item'")==1
		}
	replace OK = 1 if regexm(var, "(^[DIM]\-[0-9]+)") | regexm(var, "^[0-9RD][0-9E][0-9][0-9][0-9][0-9][0-9]")
	* lines that are not "OK" need to be fixed
	* confirm that lines immediately preceding a "not OK" line are OK
	replace var = var + " " + var[_n+1] if OK & !OK[_n+1]
	drop if !OK & OK[_n-1]
	
	replace var = var + " " + var[_n+1] if OK & !OK[_n+1]
	drop if !OK & OK[_n-1]
	
	assert OK
	drop OK
	
	* now extract exclusivity codes
	gen code = regexs(1) if regexm(var, "([DIM]\-[0-9]+)")
	* replace code as everything following the start of the exclusivity code
	gen code_position = strpos(var, code)
	replace code = substr(var, code_position, .) if !mi(code)
	
	* remove code and date from var
	replace var = substr(var, 1, code_position-1) if !mi(code)
	drop code_position
	
	* now get other exclusivity codes that don't have form [DIM]\-[0-9]+
	gen ex_position = 0
	* extract exclusivity
	foreach item in NC NCE NCE* NDF NE NP NP* NPP NR GAIN NS ODE PC PED RTO RTO* RTO** W PP {
		di "`item'"
		if "`item'" != "PED" {
			replace ex_position = strpos(var, "`item'")
			replace code = substr(var, ex_position, .) if ex_position > 0
			replace var = substr(var, 1, ex_position-1) if ex_position > 0
			}
		else {
			replace var = subinstr(var, "*PED", "$%^&", .)
			replace ex_position = strpos(var, "`item'")
			replace code = substr(var, ex_position, .) if ex_position > 0
			replace var = substr(var, 1, ex_position-1) if ex_position > 0
			replace var = subinstr(var, "$%^&", "*PED", .)
			}
		}
	
	assert regexm(code, "^[DIM]\-[0-9]+( [A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9])$") | mi(code) ///
		| regexm(code, "^[A-Z]+[\*]?[\*]?( [A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9])$")

	* gen exclusivity variables
	gen exclusivity_expiration = regexs(1) if regexm(code, "([A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9])")
	assert exclusivity_expiration == trim(itrim(exclusivity_expiration))
	
	* remove date from code
	replace code = substr(code, 1, strpos(code, exclusivity_expiration)-2)
	assert exclusivity_expiration == trim(itrim(exclusivity_expiration))
	rename code exclusivity_code
	
	* export preliminary exclusivity code data set
preserve
	keep if !mi(exclusivity_code)
	keep application_number product_number exclusivity_code exclusivity_expiration active_ingredient trade_name
	
	duplicates tag application_number product_number exclusivity_code exclusivity_expiration, gen(duplicate_count)
	duplicates drop
	
	isid application_number product_number exclusivity_code exclusivity_expiration
	
	gen edition = `year'
	
	compress
	save ${temp}`year'_parsed_exclusivity.dta, replace
restore
	
	* now move on with parsing the patents data
	drop ex_position exclusivity_expiration exclusivity_code
	
	* trim var and drop if all is no missing
	replace var = trim(itrim(var))	
	drop if mi(var)
	
	* all first lines of a new application-product group should have a patent
	assert regexm(var, "(((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?)") if new_product
		
	mdesc
	
	* we need to create a unique identifer for each patent
	* do this by multiplying an indicator for patent presence by _n
	gen patent = _n*regexm(var, "((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?")
	* now fill this in for all successive observations that don't have a patent
	replace patent = patent[_n-1] if patent==0
	assert patent > 0 & !mi(patent)
	
	* generate an id variable to keep things in the same order
	* we don't want things to change order at all
	gen id = _n
	bysort patent (id): gen N = _N
	sum N
	local max = r(max)
	
	* now concatenate together all information that follows a patent until we reach the next patent
	bysort patent (id): gen patent_info = var if _n==1
	forvalues i = 2/`max' {
		bysort patent (id): replace patent_info = patent_info + " " + var[`i'] if _n==1 & !mi(var[`i'])
		}
	assert N > 1 if mi(patent_info)
	drop if mi(patent_info)
	
	count
	
	replace patent_info = trim(itrim(patent_info))
	
	* the patent info should now follow a specific format:
	* it should be patent then date (both required), then optionally followed by "DS" "DP" use_code and "Y" (patent delist)
	assert regexm(patent_info, "^((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)? [A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]( DS )?( DS )?( U\-[0-9]+ )?( Y)?")
	
	* generate variables
	* patent_number
	gen patent_number = regexs(1) if regexm(patent_info, "^(((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?)")
	* strip patent number from patent_info
	replace patent_info = regexr(patent_info, "^(((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?)", "")
	replace patent_info = trim(itrim(patent_info))
	assert !mi(patent_number)
	
	* patent expiration
	gen patent_expiration = regexs(1) if regexm(patent_info, "(^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9])")
	replace patent_info = regexr(patent_info, "(^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9])", "")
	replace patent_info = trim(itrim(patent_info))
	assert !mi(patent_expiration)
	
	* delist
	gen delist = "Y" if regexm(patent_info, "Y$")
	replace patent_info = regexr(patent_info, "Y$", "")
	replace patent_info = trim(itrim(patent_info))
	assert mi(delist) if `year' < 2009
	
	* use code
	gen use_code = regexs(1) if regexm(patent_info, "(U[\-]?[0-9]+)$")
	assert use_code == trim(itrim(use_code))
	replace patent_info = regexr(patent_info, "(U[\-]?[0-9]+)$", "")
	replace patent_info = trim(itrim(patent_info))
	replace use_code = substr(use_code, 1, 1) + "-" + substr(use_code, 2, .) if regexm(use_code, "^U[0-9]+$")
	assert regexm(use_code, "^U\-[0-9]+$") | mi(use_code)
	
	* DS_DP
	assert inlist(patent_info, "DS", "DP", "DS DP", "")
	rename patent_info DS_DP
	replace DS_DP = subinstr(DS_DP, " ", "/", .)
	tab DS_DP, mi
	
	mdesc
	drop N id patent var new_product
	foreach var of varlist * {
		assert `var' == upper(trim(itrim(`var')))
		}
	
	* gen edition variable
	gen edition = `year'
	
	* check key variables
	duplicates drop
	isid application_number product_number patent_number use_code, mi
	
	* save final parsed data
	compress
	save ${temp}`year'_parsed_patents.dta, replace
	}
* end parsing 2005-2015 editions
	
* now append together data for each year 2000-2015
* do patents first
use ${temp}2005_parsed_patents.dta, clear
	forvalues year = 2006/2016 {
		append using ${temp}`year'_parsed_patents.dta
		}
	isid application_number product_number patent_number use_code edition, mi
	save ${temp}parsed_patents2005-2016.dta, replace

* then do the same for exclusivity
use ${temp}2005_parsed_exclusivity.dta, clear
	forvalues year = 2006/2016 {
		append using ${temp}`year'_parsed_exclusivity.dta
		}
	isid application_number product_number exclusivity_code exclusivity_expiration edition
	save ${temp}parsed_exclusivity2005-2016.dta, replace
	
********************************************************************************
********************************************************************************
****** STEP 2: PREPARE PUBLICLY AVAILABLE DATA SOURCES FOR CROSS-CHECK *********
********************************************************************************
********************************************************************************
* STEP 2A: Prepare cross-check source for 2000-2004
* set page limits for each orange book's pdftotext
* this is needed to use linux pdftotext command
clear all
input 	year	start	end
	2000	1	59
	2001	1	71
	2002	1	86
	2003	1	94
	2004	1	102
end

	* generate edition variable
	gen edition = year - 1980

	* create local macros with parameters for each year
forvalues year = 2000/2004 {
	preserve
		keep if year==`year'
		local `year'start = start
		local `year'end = end
		local `year'edition = edition
		di "`year' ``year'start' ``year'end' ``year'edition'"
	restore
	}

* import and save .txt after converting from .pdf
forvalues year = 2000/2004 {
	di "Executing pdftotext for year `year'"
	! pdftotext -layout -nopgbrk -f ``year'start' -l ``year'end' ${check1}ob``year'edition'.pdf ${txt}OB_`year'.txt
	}

* Parse data for orange books 2000-2004
* these are in a different format than 2005-2015 and hence need their own parser code
forvalues year = 2000/2004 {
	* import .txt file from pdfttotext
	* import all as one column using "^" as a delimiter
	import delim using ${txt}OB_`year'.txt, clear delim("^")
	assert c(k)==1
	rename v1 var
	
	* get rid of tabs
	replace var = upper(trim(itrim(subinstr(var, char(9), " ", .))))
	* drop non-data lines
	drop if mi(var)
	foreach item in "APPROVED DRUG PRODUCT LIST" "PRESCRIPTION AND OTC DRUG PRODUCT" ///
		"FOOTNOTE" "APPL/PROD" "EXCLUSIVITY" "PATENT" "CODE(S)" "EXPIRATION" "REQUESTED" "314.53(D)(5)." ///
		"DS =" "DP =" "U AND NUMBER =" "HTTP:" "THEY MAY NOT BE" "NUMBER NUMBER" "314.53(C)" {
		drop if strpos(var, "`item'")
		}
	drop if var == "DATE"
	drop if var == "DATE CODES"
	drop if regexm(var, "^ADA [0-9]+$")
	drop if regexm(var, "^ADA \- [0-9]+")
	drop if regexm(var, "ADA [0-9]+ OF [0-9]+")
	
	gen application_number = regexs(1) if regexm(var, "^([0-9][0-9][0-9][0-9][0-9][0-9]) ([0-9][0-9][0-9])")
	gen product_number = regexs(2) if regexm(var, "^([0-9][0-9][0-9][0-9][0-9][0-9]) ([0-9][0-9][0-9])")
	replace var = regexr(var, "^([0-9][0-9][0-9][0-9][0-9][0-9]) ([0-9][0-9][0-9])", "")
	replace var = trim(itrim(var))
	foreach var in application_number product_number {
		replace `var' = `var'[_n-1] if mi(`var')
		assert !mi(`var')
		}
	
	* find and remove patent information
	gen patent = regexs(1) if regexm(var, "(((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)? [A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]( DS)?( DP)?( U[\-]?[0-9]+)?)")
	assert !regexm(var, "((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?") if mi(patent)
	assert regexm(var, "((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?") if !mi(patent)
	replace var = regexr(var, "(((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)? [A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]( DS)?( DP)?( U[\-]?[0-9]+)?)", "")
	replace var = trim(itrim(var))
	
	replace patent = trim(itrim(patent))
	
	gen patent_expiration = regexs(1) if regexm(patent, "([A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9])")
	assert !mi(patent_expiration) if !mi(patent)
	replace patent = regexr(patent, "[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]", "")
	replace patent = trim(itrim(patent))
	gen patent_number = regexs(1) if regexm(patent, "(((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?)")
	assert !mi(patent_number) if !mi(patent)
	replace patent = regexr(patent, "((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?", "")
	replace patent = trim(itrim(patent))
	gen use_code = regexs(1) if regexm(patent, "(U[\-]?[0-9]+)")
	replace patent = regexr(patent, "(U[\-]?[0-9]+)", "")
	replace patent = trim(itrim(patent))
	rename patent DS_DP
	assert inlist(DS_DP, "", "DS", "DP", "DS DP")
	replace DS_DP = "DS/DP" if DS_DP == "DS DP"
	
	* now do exclusivity
	count if regexm(var, "([A-Z0-9\*\-]+ [A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9])")
	
	gen exclusivity = regexs(1) if regexm(var, "([A-Z0-9\*\-]+ [A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9])")
	replace exclusivity = trim(itrim(exclusivity))
	gen exclusivity_code = regexs(1) if regexm(var, "([A-Z0-9\*\-]+) ([A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9])")
	gen exclusivity_expiration = regexs(2) if regexm(var, "([A-Z0-9\*\-]+) ([A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9])")
	foreach var in exclusivity_code exclusivity_expiration {
		replace `var' = trim(itrim(`var'))
		}
	drop exclusivity
	
	replace var = regexr(var, "([A-Z0-9\*\-]+ [A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9])", "")
	replace var = trim(itrim(var))
	
	assert !mi(patent_number) | !mi(exclusivity_code) | regexm(var, "^U[\-]?[0-9]+$")

	replace use_code = var if regexm(var, "^U[\-]?[0-9]+$")
	replace var = "" if regexm(var, "^U[\-]?[0-9]+$")
	
	foreach var in patent_expiration patent_number DS_DP {
		replace `var' = `var'[_n-1] if mi(`var') & !mi(use_code)
		}
		
	assert strpos(var, ";") | mi(var)
	gen active_ingredient = substr(var, 1, strpos(var, ";")-1)
	assert active_ingredient == trim(itrim(active_ingredient))
	gen trade_name = substr(var, strpos(var, ";")+1, .)
	assert trade_name == trim(itrim(trade_name))
	assert (var == active_ingredient + ";" + trade_name) | mi(var)
	drop var
	
	foreach var in active_ingredient trade_name {
		replace `var' = `var'[_n-1] if mi(`var')
		assert !mi(`var')
		}
		
preserve
	keep if !mi(exclusivity_code)
	keep application_number product_number exclusivity_code exclusivity_expiration active_ingredient trade_name
	
	duplicates tag application_number product_number exclusivity_code exclusivity_expiration, gen(duplicate_count)
	duplicates drop
	
	isid application_number product_number exclusivity_code exclusivity_expiration
	
	gen edition = `year'
	
	compress
	save ${temp}`year'_parsing_exclusivity_prelim.dta, replace
restore

	drop exclusivity_code exclusivity_expiration
	keep if !mi(patent_number)
	
	replace use_code = substr(use_code, 1, 1) + "-" + substr(use_code, 2, .) if regexm(use_code, "^U[0-9]+$")
	assert regexm(use_code, "^U\-[0-9]+$") | mi(use_code)
	
	foreach var of varlist * {
		assert `var' == upper(trim(itrim(`var')))
		}
	
	duplicates drop
	* get rid of incorrect patent expiration for 2004
	if inlist(`year', 2002, 2003) {
		drop if application_number=="020330" & inlist(product_number, "001", "002") & patent_number=="4861760" & patent_expiration=="AUG 29, 2006"
		}
	
	isid application_number product_number patent_number use_code, mi
	
	gen edition = `year'
	
	compress
	save ${temp}`year'_parsed_final_patents.dta, replace
	}
* end parsing 2000-2004 editions

* now append together data for each year 2000-2004
* do patents first
use ${temp}2000_parsed_final_patents.dta, clear
	forvalues year = 2001/2004 {
		append using ${temp}`year'_parsed_final_patents.dta
		}
	isid application_number product_number patent_number use_code edition, mi
	save ${temp}parsed_final_patents2000-2004.dta, replace

* then do the same for exclusivity
use ${temp}2000_parsing_exclusivity_prelim.dta, clear
	forvalues year = 2001/2004 {
		append using ${temp}`year'_parsing_exclusivity_prelim.dta
		}
	isid application_number product_number exclusivity_code exclusivity_expiration edition
	save ${temp}parsed_final_exclusivity2000-2004.dta, replace

* STEP 2B: Prepare cross-check source for 1985-1999
* Now we will use /paper_orange_book/ data as our comparison source for 1985-1999
* import paper orange book data from /paper_orange_book/
forvalues year = 1985/1999 {
	* no book for 1986
	if `year'==1986 {
		continue
		}
	
	* load data
	use ${check2}paper_orange_book_`year', clear

	* trim data
	ds, has(type string)
	local vars = r(varlist)
	foreach var in `vars' {
		replace `var' = upper(trim(itrim(`var')))
		}
	
	* fill in data
	foreach var in applno product {
		replace `var' = `var'[_n-1] if mi(`var')
		}
	
	* drop those observations from Section 505 Exclusivity table
	* the observations we need to drop varies with year
	if `year'==1985 {
		count if applno=="168890" | applno=="761021"
		assert r(N)==3
		drop if applno=="168890" | applno=="761021"
		}
	if `year'==1987 {
		count if applno=="16889"
		assert r(N)==1
		drop if applno=="16889"
		}
	if `year'==1988 {
		count if inlist(applno, "83715", "16889", "841207")
		assert r(N)==3
		drop if inlist(applno, "83715", "16889", "841207")
		}
	if `year'==1989 {
		count if inlist(applno, "83715", "841207")
		assert r(N)==2
		drop if inlist(applno, "83715", "841207")
		}
	if `year'==1990 {
		count if inlist(applno, "841207", "860909")
		assert r(N)==3
		drop if inlist(applno, "841207", "860909")
		}
	if `year'==1991 {
		count if inlist(applno, "841207", "860909")
		assert r(N)==3
		drop if inlist(applno, "841207", "860909")	
		}
	if `year'==1992 {
		count if inlist(applno, "841207", "860909")
		assert r(N)==3
		drop if inlist(applno, "841207", "860909")	
		}
	if `year'==1993 {
		count if inlist(applno, "841207", "860909")
		assert r(N)==3
		drop if inlist(applno, "841207", "860909")	
		}	
	if `year'==1994 {
		count if inlist(applno, "841207", "860909", "19862", "900278")
		assert r(N)==5
		drop if inlist(applno, "841207", "860909", "19862", "900278")
		}
	if `year'==1995 {
		count if inlist(applno, "19841", "19862", "860909", "900278")
		assert r(N)==4
		drop  if inlist(applno, "19841", "19862", "860909", "900278")
		}
	if `year'==1996 {
		count if inlist(applno, "19841", "19862", "850905", "900278")
		assert r(N)==4
		drop  if inlist(applno, "19841", "19862", "850905", "900278")
		}
	if `year'==1997 {
		count if inlist(applno, "19841", "19862", "860909", "900278")
		assert r(N)==4
		drop  if inlist(applno, "19841", "19862", "860909", "900278")
		}
	if `year'==1998 {
		count if inlist(applno, "860909", "900278")
		assert r(N)==2
		drop if inlist(applno, "860909", "900278")
		}
	if `year'==1999 {
		* nothing to drop here
		}
		
	* assert not missing application and product numbers
	assert !mi(applno) & !mi(product)
	
	* save exclusivity data
	preserve
	if `year'==1985 {
		keep applno product excl excl_exp
		}
	else {
		keep applno product excl excl_exp name
		}
	keep if !mi(excl)
	gen edition = `year'
	save ${temp}paper_OB_excl_`year'.dta, replace
	restore
	
	* save patent data
	drop excl excl_exp
	keep if !mi(patent)
	gen edition = `year'
	save ${temp}paper_OB_patent_`year'.dta, replace
	}

* append together  and prepare paper_orange_book patent files for 1985-1999
use ${temp}paper_OB_patent_1985.dta, clear
	forvalues year = 1987/1999 {
		append using ${temp}paper_OB_patent_`year'.dta
		}
		
	* put data into same form as DDD patents data
	assert mi(name) if edition==1985
	assert !mi(name) if edition!=1985
	
	gen name_reverse = reverse(name)
	gen trade_name = substr(name_reverse, 1, strpos(name_reverse, ";")-1)
	gen active_ingredient = substr(name_reverse, strpos(name_reverse, ";")+1, .)
	foreach var in trade_name active_ingredient {
		replace `var' = reverse(`var')
		replace `var' = trim(itrim(`var'))
		}
	list name trade_name active_ingredient if edition > 1985 & (mi(trade_name) | mi(active_ingredient))
	foreach var in trade_name active_ingredient {
		replace `var' = "" if (mi(trade_name) | mi(active_ingredient))
		}
	list name trade_name active_ingredient if edition > 1985 & (mi(trade_name) | mi(active_ingredient))
	
	replace trade_name = reverse(substr(name_reverse, 1, strpos(name_reverse, " ")-1)) if (mi(trade_name) | mi(active_ingredient))
	replace active_ingredient = reverse(substr(name_reverse, strpos(name_reverse, " ")+1, .)) if (mi(trade_name) | mi(active_ingredient))
	foreach var in trade_name active_ingredient {
		replace `var' = trim(itrim(`var'))
		}
	list name trade_name active_ingredient if !strpos(name, ";") & !mi(name)
	
	* rename variables
	rename (applno product patent patent_exp) ///
		(application_number product_number patent_number patent_expiration)
	drop name name_reverse
	
	* drop if missing all variables that should never be missing
	drop if mi(application_number) & mi(product_number) & mi(patent_number) ///
		& mi(patent_expiration) & mi(trade_name) & mi(active_ingredient)
		
	* for variables not available in all editions, mark as "N/A" if not available
	* active_ingredient
	assert mi(active_ingredient) if edition < 1987
	replace active_ingredient = "N/A" if edition < 1987
	
	* trade_name
	assert mi(trade_name) if edition < 1987
	replace trade_name = "N/A" if edition < 1987
	
	* use_code
	assert mi(use_code) if edition < 1988
	replace use_code = "N/A" if edition < 1988
	list use_code if !regexm(use_code, "^U\-[0-9]+$") & !mi(use_code) & edition >= 1988
	replace use_code = substr(use_code, 1, 1) + "-" + substr(use_code, 2, .) if (!regexm(use_code, "^U\-[0-9]+$") & !mi(use_code) & edition >= 1988)
	
	* date
	gen year = year(patent_expiration)
	gen month = month(patent_expiration)
	gen day = day(patent_expiration)
	tostring year month day, replace
	local count = 1
	foreach month in JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC {
		replace month = "`month'" if month=="`count'"
		local ++count
		}
	drop patent_expiration
	
	replace day = "0" + day if length(day)==1
	gen patent_expiration = month + " " + day + ", " + year
	drop year month day
	list patent_expiration if !regexm(patent_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
	replace patent_expiration = "" if patent_expiration==". 0., ."
	assert regexm(patent_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$") | mi(patent_expiration)
	
	* product_number
	assert inlist(length(product_number), 1, 2, 3)
	replace product_number = "000" + product_number
	replace product_number = substr(product_number, -3, .)
	
	* application_number
	assert inlist(length(application_number), 4, 5, 6)
	replace application_number = "000000" + application_number
	replace application_number = substr(application_number, -5, .) if inrange(edition, 1985, 1997)
	replace application_number = substr(application_number, -6, .) if inrange(edition, 1998, 2009)
	
	duplicates drop
	duplicates drop application_number product_number patent_number use_code edition, force
	
	isid application_number product_number patent_number use_code edition, mi
	
	compress
	save ${temp}paper_orange_book_patents_1985-1999.dta, replace

	* now append our patent data for 2000-2004 for data for 1985-1999
	append using ${temp}parsed_final_patents2000-2004.dta
	isid application_number product_number patent_number use_code edition, mi
	
	mdesc
	sum edition
	tab edition
	
	* fill in "N/A" for use_code, delist, and DS_DP
	* use_code
	assert use_code=="N/A" if edition < 1988

	* DS_DP
	assert mi(DS_DP) if edition < 2004
	replace DS_DP = "N/A" if edition < 2004
	
	* save patent file for 1985
	* this is our base comparison file
	save ${temp}comparison_patents1985-2004.dta, replace

	* load comparison exclusivity data for 1985-1999 and put into same format as DDD data
use ${temp}paper_OB_excl_1985.dta, clear
	forvalues year = 1987/1999 {
		append using ${temp}paper_OB_excl_`year'.dta
		}

* put data into same form as DDD patents data
	assert mi(name) if edition==1985
	assert !mi(name) if edition!=1985
	
	gen name_reverse = reverse(name)
	gen trade_name = substr(name_reverse, 1, strpos(name_reverse, ";")-1)
	gen active_ingredient = substr(name_reverse, strpos(name_reverse, ";")+1, .)
	foreach var in trade_name active_ingredient {
		replace `var' = reverse(`var')
		replace `var' = trim(itrim(`var'))
		}
	list name trade_name active_ingredient if edition > 1985 & (mi(trade_name) | mi(active_ingredient))
	foreach var in trade_name active_ingredient {
		replace `var' = "" if (mi(trade_name) | mi(active_ingredient))
		}
	list name trade_name active_ingredient if edition > 1985 & (mi(trade_name) | mi(active_ingredient))
	
	replace trade_name = reverse(substr(name_reverse, 1, strpos(name_reverse, " ")-1)) if (mi(trade_name) | mi(active_ingredient))
	replace active_ingredient = reverse(substr(name_reverse, strpos(name_reverse, " ")+1, .)) if (mi(trade_name) | mi(active_ingredient))
	foreach var in trade_name active_ingredient {
		replace `var' = trim(itrim(`var'))
		}
	list name trade_name active_ingredient if !strpos(name, ";") & !mi(name)
	
	* rename variables
	rename (applno product excl excl_exp) ///
		(application_number product_number exclusivity_code exclusivity_expiration)
	drop name name_reverse
	
	* drop if missing all variables that should never be missing
	drop if mi(application_number) & mi(product_number) & mi(exclusivity_code) ///
		& mi(exclusivity_expiration) & mi(trade_name) & mi(active_ingredient)
		
	mdesc
	
	* for variables not available in all editions, mark as "N/A" if not available
	* active_ingredient
	assert mi(active_ingredient) if edition < 1987
	replace active_ingredient = "N/A" if edition < 1987
	
	* trade_name
	assert mi(trade_name) if edition < 1987
	replace trade_name = "N/A" if edition < 1987
	
	* date
	gen year = year(exclusivity_expiration)
	gen month = month(exclusivity_expiration)
	gen day = day(exclusivity_expiration)
	tostring year month day, replace
	local count = 1
	foreach month in JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC {
		replace month = "`month'" if month=="`count'"
		local ++count
		}
	drop exclusivity_expiration
	
	replace day = "0" + day if length(day)==1
	gen exclusivity_expiration = month + " " + day + ", " + year
	drop year month day
	list exclusivity_expiration if !regexm(exclusivity_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
	replace exclusivity_expiration = "" if !regexm(exclusivity_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
	assert regexm(exclusivity_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$") | mi(exclusivity_expiration)
	
	* product_number
	assert inlist(length(product_number), 1, 2, 3)
	replace product_number = "000" + product_number
	replace product_number = substr(product_number, -3, .)
	
	* application_number
	assert inlist(length(application_number), 4, 5, 6)
	replace application_number = "000000" + application_number
	replace application_number = substr(application_number, -5, .) if inrange(edition, 1985, 1997)
	replace application_number = substr(application_number, -6, .) if inrange(edition, 1998, 2009)
	
	duplicates tag application_number product_number exclusivity_code exclusivity_expiration edition, gen(duplicate_count)
	duplicates drop
	duplicates drop application_number product_number exclusivity_code exclusivity_expiration edition, force
	isid application_number product_number exclusivity_code exclusivity_expiration edition, mi
	
	compress
	save ${temp}paper_orange_book_exclusivity_1985-1999.dta, replace

	* now append our exclusivity data for 2000-2015 for data for 1985-1999
	append using ${temp}parsed_final_exclusivity2000-2004.dta
	isid application_number product_number exclusivity_code exclusivity_expiration edition, mi
	
	mdesc
	sum edition
	tab edition
	
	* save file
	* this is our base comparison file for exclusivity
	save ${temp}comparison_exclusivity1985-2004.dta, replace

********************************************************************************
********************************************************************************
****** STEP 3: INTERNALLY HARMONIZE DDD DATA ***********************************
********************************************************************************
********************************************************************************
* STEP 3A: Internally harmonize DDD-entered patents data
* We first import the DDD patent data and correct for idiosyncratic differences in each file, e.g., names of variables
* We then append them together and look for observations with varaibles that do not fit their correct "form"
* For these errant observations, we export an Excel file and make corrections in a NEW column
* We then merge the data back in after adding the corrections column and make the corrections
* E.g., dates should be in the "MMM DD, YYYY" format
* This allows us to catch some errors before cross-checking with our comparison data

* We then repeat the above steps for our exclusivity data

********************************************************************************
* PATENTS: Import files and reconcile differences across Excel workbooks
* first we need to import all data sets 1985-2004 and standardize variable names, etc.
* do this for all of the patent data sets first
forvalues i = 1985/2004 {
	* skip if 1986 (no orange book for that year)
	if `i' == 1986 {
		continue
		}
	* import raw dataset for that year
	* first make sure there is only one sheet in each workbook
	* we don't want to accidentally import the wrong sheet
	import excel using ${rawtables}ob-`i'_exclusivity_patents.xlsx, describe
	assert r(N_worksheet)==1
	* then actually import the data
	import excel using ${rawtables}ob-`i'_exclusivity_patents.xlsx, clear firstrow
	
	* then we have to make idiosyncratic changes for each year based on the raw datasets
	* do this year by year
	if `i' == 1985 {
		* nothing to change here
		}	
	* no orange book for 1986
	if `i' == 1987 {
		* nothing to change here
		}	
	if `i' == 1988 {
		* nothing to change here
		}
	if `i' == 1989 {
		* nothing to change here
		}
	if `i' == 1990 {
		* nothing to change here
		}
	if `i' == 1991 {
		* drop extra columns
		drop page_no
		}	
	if `i' == 1992 {
		* drop extra columns
		drop page_no
		}
	if `i' == 1993 {
		* nothing to change here
		}
	if `i' == 1994 {
		* nothing to change here
		}
	if `i' == 1995 {
		* nothing to change here
		}
	if `i' == 1996 {
		* nothing to change here
		}
	if `i' == 1997 {
		* nothing to change here
		}
	if `i' == 1998 {
		assert mi(H)
		drop H
		}	
	if `i' == 1999 {
		* nothing to change here
		}	
	if `i' == 2000 {
		assert mi(H)
		drop H
		}
	if `i' == 2001 {
		* nothing to change here
		}
	if `i' == 2002 {
		assert mi(H) & mi(I)
		drop H I
		}
	if `i' == 2003 {
		* nothing to change here
		}
	if `i' == 2004 {
		* drop extra columns
		assert mi(I)
		drop I
		}
		
	* create a variable for the edition (year)
	gen edition = `i'
	compress
	save ${temp}patents`i'raw.dta, replace
	}
	
	* now append all the yearly additions together
	use ${temp}patents1985raw.dta, clear
	forvalues i = 1987/2004 {
		append using ${temp}patents`i'raw.dta, nolabel
		}
		
	* remove labels
	foreach var of varlist * {
		label var `var' ""
		}
	
	* drop if missing all variables that should never be missing
	drop if mi(application_number) & mi(product_number) & mi(patent_number) ///
		& mi(patent_expiration) & mi(trade_name) & mi(active_ingredient)
	* drop exact duplicates
	duplicates tag, gen(dup)
	duplicates drop
	
	* for variables not available in all editions, mark as "N/A" if not available
	* active_ingredient
	assert mi(active_ingredient) if edition < 1987
	replace active_ingredient = "N/A" if edition < 1987
	
	* trade_name
	assert mi(trade_name) if edition < 1987
	replace trade_name = "N/A" if edition < 1987
	
	* use_code
	assert mi(use_code) if edition < 1988
	replace use_code = "N/A" if edition < 1988

	* DS_DP
	assert mi(DS_DP) if edition < 2004
	replace DS_DP = "N/A" if edition < 2004
		
********************************************************************************
* Flag fields that do not fit required form
	* trim all variables
	ds, has(type string)
	local vars = r(varlist)
	foreach var in `vars' {
		replace `var' = upper(trim(itrim(`var')))
		}

	* we may have some new duplicates after trimming
	* get rid of those
	duplicates tag, gen(tag)
	list if tag
	assert tag==0
	drop tag

	* application number
	* application numbers should be 5-6 digits, sometimes having an initial N or A
	count if !regexm(application_number, "^[NA]?[0-9]?[0-9][0-9][0-9][0-9][0-9]$")
	* more specifically, they should be 5 digits for 1985-1997
	* 6 digits for 1998-2009
	* N or A + 6 digits for 2010-2015
	count if (!regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1985, 1997)) ///
		| (!regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1998, 2004))
	gen errorflag = (!regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1985, 1997)) ///
		| (!regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1998, 2004))
	tab errorflag, mi
	export excel using ${discrep}form_errors_patents.xlsx if errorflag, sheet("application_number") sheetreplace firstrow(variables)
	drop errorflag
	
	* product number
	* all product numbers should be 3 digits
	count if !regexm(product_number, "^[0-9][0-9][0-9]$")
	gen errorflag = !regexm(product_number, "^[0-9][0-9][0-9]$")
	tab errorflag, mi
	count if errorflag
	assert r(N)==0
	* nothing to export here
	drop errorflag
	
	* active ingredient
	* active ingredient should never be missing
	count if mi(active_ingredient)
	assert r(N)==0
	* nothing to export here
	
	* trade name
	count if mi(trade_name)
	gen errorflag = mi(trade_name)
	export excel using ${discrep}form_errors_patents.xlsx if errorflag, sheet("trade_name") sheetreplace firstrow(variables)
	drop errorflag
	
	* patent_number
	* patents should always be 7 or 11 digits
	* they are D+6 digits, RE+5 digits, or just 7 digits
	* and then, optionally, *PED is appended to end
	count if !regexm(patent_number, "^((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?$")
	gen errorflag = !regexm(patent_number, "^((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?$")
	export excel using ${discrep}form_errors_patents.xlsx if errorflag, sheet("patent_number") sheetreplace firstrow(variables)
	drop errorflag
	
	* patent_expiration
	* expiration should all be of form "MMM DD, YYYY"
	count if !regexm(patent_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
	gen errorflag = !regexm(patent_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
	* additionally, they need to be a valid date
	gen datetemp = date(patent_expiration, "MDY")
	replace errorflag = 1 if mi(datetemp)
	drop datetemp
	tab errorflag, mi
	export excel using ${discrep}form_errors_patents.xlsx if errorflag, sheet("patent_expiration") sheetreplace firstrow(variables)
	drop errorflag
	
	* DS_DP
	* DS_DP needs to be either "N/A", <missing>, "DS", "DP", or "DS/DP"
	assert DS_DP == "N/A" if edition < 2004
	assert DS_DP != "N/A" if edition >= 2004
	count if !inlist(DS_DP, "", "DS", "DP", "DS/DP") & edition >= 2004
	gen errorflag = (!inlist(DS_DP, "", "DS", "DP", "DS/DP") & edition >= 2004)
	tab errorflag, mi
	export excel using ${discrep}form_errors_patents.xlsx if errorflag, sheet("DS_DP") sheetreplace firstrow(variables)
	drop errorflag
	
	* use code
	* use code needs to be "N/A", <missing>, or U-<number>
	* additionally, the number should not exceed the maximum number for that edition
	assert use_code == "N/A" if edition < 1988
	assert use_code != "N/A" if edition >= 1988
	count if !(regexm(use_code, "^U\-[0-9]+$") | mi(use_code)) & edition >= 1988
	* a lot of the errors are due to ommission of "-"
	* we will just fix those here
	replace use_code = substr(use_code, 1, 1) + "-" + substr(use_code, 2, .) if regexm(use_code, "^U[0-9]+$")
	count if !(regexm(use_code, "^U\-[0-9]+$") | mi(use_code)) & edition >= 1988
	gen errorflag = !(regexm(use_code, "^U\-[0-9]+$") | mi(use_code)) & edition >= 1988
	tab errorflag, mi
	
* create .dta for maximum use codes by edition
* this is imported from hand-coded Excel file
preserve
	import excel using ${correct}maximum_use_codes.xlsx, clear firstrow
	save ${temp}maximum_use_codes.dta, replace
restore
	
	* merge with crosswalk of maximum use codes by edition
	merge m:1 edition using ${temp}maximum_use_codes.dta
	assert _merge != 2
	assert edition < 1988 if _merge == 1
	drop _merge
	
	* generate use code numeric
	gen number = regexs(1) if regexm(use_code, "^U\-([0-9]+)$")
	destring number, replace
	count if number > max_use_code & !mi(number)
	replace errorflag = 1 if number > max_use_code & !mi(number)
	drop max_use_code number
	export excel using ${discrep}form_errors_patents.xlsx if errorflag, sheet("use_code") sheetreplace firstrow(variables)
	drop errorflag
	
	save ${temp}patents_working.dta, replace

********************************************************************************
* Merge back in hand-coded corrections
	* import and save .dta for each variable we need to correct
	foreach var in application_number trade_name patent_number patent_expiration DS_DP use_code {
		import excel using ${correct}form_errors_patents_corrections.xlsx, sheet("`var'") clear firstrow allstring
		destring edition errorflag, replace
		
		* fix use code for merging purposes
		replace use_code = substr(use_code, 1, 1) + "-" + substr(use_code, 2, .) if regexm(use_code, "^U[0-9]+$")
		save ${temp}patent_corrections_`var'.dta, replace
		}
		
	* use working patent data
use ${temp}patents_working.dta, clear
	* create new variables to store corrections
	foreach var in application_number product_number patent_number patent_expiration trade_name active_ingredient use_code DS_DP {
		gen `var'NEW = `var'
		}
	
	gen to_drop = 0
	* merge in corrections
	foreach var in application_number trade_name patent_number patent_expiration DS_DP use_code {
	di "`var'"
	merge 1:1 application_number product_number patent_number patent_expiration edition trade_name active_ingredient use_code DS_DP using ${temp}patent_corrections_`var'.dta, keepusing(new note)
	assert _merge != 2
	drop _merge
	
	replace `var'NEW = new if !mi(new)
	replace to_drop = 1 if note=="DROP"
	
	* now do other corrections according to notes
	if "`var'"=="application_number" {
		list note if !mi(note)
		local check = 1
		* no notes
		}
	if "`var'"=="trade_name" {
		list note if !mi(note)
		local check = 1
		* no notes
		}
	if "`var'"=="patent_number" {
		list note if !mi(note)
		local check = 1
		* no notes
		}
	if "`var'"=="patent_expiration" {
		list note if !mi(note)
		local check = 1
		* no notes
 		}
	
	if "`var'"=="DS_DP" {
		list note if !mi(note)
		local check = 1
		* no notes
		}
		
	if "`var'"=="use_code" {
		list note if !mi(note)
		local check = 1
		* fix DS/DP
		replace DS_DPNEW = new if note=="Clear use_code and replace DS_DP"
		replace `var'NEW = "" if note=="Clear use_code and replace DS_DP"
		}
	
	* check that we went into a conditional statement
	assert `check'==1
	* drop new and note
	drop new note
	* resent check to 0
	local `check' = 0	
	}
	
	* drop observations
	tab to_drop, mi
	drop if to_drop
	drop to_drop
	* now replace variables with corrected versions
	foreach var in application_number product_number patent_number patent_expiration trade_name active_ingredient use_code DS_DP {
		replace `var' = `var'NEW
		drop `var'NEW
		}
	
	save ${temp}patents_internally_corrected.dta, replace

********************************************************************************
* Do final check of variable formats and key variables

	* Key variables should be application_number product_number patent_number use_code edition
	* we have some duplicates on those variables that we need to resolve
	duplicates tag application_number product_number patent_number use_code edition, gen(tag)
	tab tag
	list if tag
	* drop incorect trade names
	count if trade_name=="BULEXIN" & tag
	assert r(N)==3
	drop if trade_name=="BULEXIN" & tag
	* drop incorrect expiration date
	count if patent_number=="6133289" & patent_expiration=="MAY 19, 2015" & edition==2004 & application_number=="020031" & product_number=="005" & tag
	assert r(N)==1
	drop if patent_number=="6133289" & patent_expiration=="MAY 19, 2015" & edition==2004 & application_number=="020031" & product_number=="005" & tag
	count if patent_number=="4861760" & patent_expiration=="AUG 29, 2006" & tag
	assert r(N)==4
	drop if patent_number=="4861760" & patent_expiration=="AUG 29, 2006" & tag
	
	* Key variables should be application_number product_number patent_number use_code edition
	* we have some duplicates on those variables that we need to resolve
	drop tag
	duplicates tag application_number product_number patent_number use_code edition, gen(tag)
	count if tag
	assert r(N)==0
	drop tag
	
	* key variables are now correct (use_code may be missing)
	isid application_number product_number patent_number use_code edition, mi

	* do final check of variable formats
	* check that N/A is where it should be
	assert active_ingredient == "N/A" if edition < 1987
	assert active_ingredient != "N/A" if edition >= 1987
	
	assert trade_name == "N/A" if edition < 1987
	assert trade_name != "N/A" if edition >= 1987
	
	assert use_code == "N/A" if edition < 1988
	assert use_code != "N/A" if edition >= 1988

	assert DS_DP == "N/A" if edition < 2004
	assert DS_DP != "N/A" if edition >= 2004
	
	* check forms of variables
	* application number
	assert regexm(application_number, "^[NA]?[0-9]?[0-9][0-9][0-9][0-9][0-9]$")
	assert (regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1985, 1997)) ///
		| (regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1998, 2009))
	assert (length(application_number)==5 & inrange(edition, 1985, 1997)) ///
		| (length(application_number)==6 & inrange(edition, 1998, 2009))
	* product number
	assert regexm(product_number, "^[0-9][0-9][0-9]$")
	assert length(product_number)==3
	* active_ingredient
	assert !mi(active_ingredient)
	assert !strpos(active_ingredient, "?") // make sure there are no marks for illegible PDFs
	* trade_name
	assert !mi(trade_name)
	assert !strpos(trade_name, "?")
	* patent_number
	assert regexm(patent_number, "^((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?$")
	assert inlist(length(patent_number), 7, 11)
	* patent_expiration
	assert regexm(patent_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
	gen datetemp = date(patent_expiration, "MDY")
	assert !mi(datetemp)
	drop datetemp
	assert length(patent_expiration)==12
	* DS_DP
	assert (inlist(DS_DP, "", "DS", "DP", "DS/DP") & edition >= 2004) | (DS_DP=="N/A" & edition < 2004)
	assert inlist(length(DS_DP), 0, 2, 3, 5)
	* use_code
	assert ((regexm(use_code, "^U\-[0-9]+$") | mi(use_code)) & edition >= 1988) | (use_code=="N/A" & edition < 1988)
	* edition
	assert !mi(edition)
	assert inrange(edition, 1985, 2004)
	assert edition != 1986
	
	duplicates tag, gen(tag)
	assert tag == 0
	drop tag
	
	* drop dup, we don't need it for patent data
	drop dup
	
	assert !mi(application_number, product_number, patent_number, patent_expiration, edition, trade_name, active_ingredient)
	
	compress
	save ${temp}final_patent_data_internally_corrected.dta, replace

********************************************************************************
* EXCLUSIVITY: Import files and reconcile differences across Excel workbooks
* first we need to import all data sets 1985-2015 and standardize variable names, etc.
* do this for all of the patent data sets first
forvalues i = 1985/2004 {
	* skip if 1986 (no orange book for that year)
	if `i' == 1986 {
		continue
		}
	
	* import raw dataset for that year
	* first make sure there is only one sheet in each workbook
	* we don't want to accidentally import the wrong sheet
	import excel using ${rawtables}ob-`i'_exclusivity_codes.xlsx, describe
	assert r(N_worksheet)==1	
	* then actually import the data
	import excel using ${rawtables}ob-`i'_exclusivity_codes.xlsx, clear firstrow
	
	if `i' == 1985 {
		* nothing to change here
		}
	if `i' == 1987 {
		* drop extra columns
		assert mi(G) & mi(H)
		drop G H
		}
	if `i' == 1988 {
		* drop extra column
		drop page_no
		}
	if `i' == 1989 {
		* nothing to change here
		}
	if `i' == 1990 {
		* nothing to change here
		}
	if `i' == 1991 {
		* nothing to change here
		}
	if `i' == 1992 {
		* drop extra column
		drop page_no
		}
	if `i' == 1993 {
		* drop extra column
		assert mi(G)
		drop G
		}
	if `i' == 1994 {
		* nothing to change here
		}
	if `i' == 1995 {
		* nothing to change here
		}
	if `i' == 1996 {
		* nothing to change here
		}
	if `i' == 1997 {
		* nothing to change here
		}
	if `i' == 1998 {
		* drop extra column
		assert mi(G)
		drop G
		}
	if `i' == 1999 {
		* nothing to change here
		}
	if `i' == 2000 {
		* nothing to change here
		}
	if `i' == 2001 {
		* nothing to change here
		}
	if `i' == 2002 {
		* nothing to change here
		}
	if `i' == 2003 {
		* nothing to change here
		}
	if `i' == 2004 {
		* drop extra column
		assert mi(G)
		drop G
		}
		
	* create a variable for the edition (year)
	gen edition = `i'
	compress
	save ${temp}exclusivity`i'raw.dta, replace
	}

	* now append all the yearly additions together
	use ${temp}exclusivity1985raw.dta, clear
	forvalues i = 1987/2004 {
		append using ${temp}exclusivity`i'raw.dta, nolabel
		}
		
	* remove labels
	foreach var of varlist * {
		label var `var' ""
		}	

	* drop if missing all variables that should never be missing
	drop if mi(application_number) & mi(product_number) & mi(exclusivity_code) ///
		& mi(exclusivity_expiration) & mi(trade_name) & mi(active_ingredient)
	* drop exact duplicates
	duplicates tag, gen(duplicate_count)
	duplicates drop
	
	* active_ingredient
	assert mi(active_ingredient) if edition < 1987
	replace active_ingredient = "N/A" if edition < 1987
	
	* trade_name
	assert mi(trade_name) if edition < 1987
	replace trade_name = "N/A" if edition < 1987

********************************************************************************
* Flag fields that do not fit required form
	* trim all variables
	ds, has(type string)
	local vars = r(varlist)
	foreach var in `vars' {
		replace `var' = upper(trim(itrim(`var')))
		}
	duplicates drop
	
	* application number
	* application numbers should be 5-6 digits, sometimes having an initial N or A
	count if !regexm(application_number, "^[NA]?[0-9]?[0-9][0-9][0-9][0-9][0-9]$")
	* more specifically, they should be 5 digits for 1985-1997
	* 6 digits for 1998-2009
	* N or A + 6 digits for 2010-2015
	count if (!regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1985, 1997)) ///
		| (!regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1998, 2009))
	gen errorflag = (!regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1985, 1997)) ///
		| (!regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1998, 2009))
	tab errorflag, mi
	export excel using ${discrep}form_errors_exclusivity.xlsx if errorflag, sheet("application_number") sheetreplace firstrow(variables)
	drop errorflag
	
	* product number
	* all product numbers should be 3 digits
	count if !regexm(product_number, "^[0-9][0-9][0-9]$")
	assert r(N)==0
	* nothing to export here
	
	* active ingredient
	* active ingredient should never be missing
	count if mi(active_ingredient)
	assert r(N)==0
	* nothing to export here
	
	* trade name
	count if mi(trade_name)
	gen errorflag = mi(trade_name)
	export excel using ${discrep}form_errors_exclusivity.xlsx if errorflag, sheet("trade_name") sheetreplace firstrow(variables)
	drop errorflag
	
	* exclusivity expiration
	* expiration should all be of form "MMM DD, YYYY"
	count if !regexm(exclusivity_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
	gen errorflag = !regexm(exclusivity_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
	* additionally, they need to be a valid date
	gen datetemp = date(exclusivity_expiration, "MDY")
	replace errorflag = 1 if mi(datetemp)
	drop datetemp
	tab errorflag, mi
	export excel using ${discrep}form_errors_exclusivity.xlsx if errorflag, sheet("exclusivity_expiration") sheetreplace firstrow(variables)
	drop errorflag
	
	* exclusivity code
	* exclusivity codes have to be one of many different strings
	count if !inlist(exclusivity_code, "NC", "NCE", "NCE*", "NDF", "NE", "NP", "NP*", "NPP", "NR") ///
		& !inlist(exclusivity_code, "NS", "ODE", "PC", "PED", "RTO", "RTO*", "RTO**", "W", "PP") ///
		& !regexm(exclusivity_code, "^[DIM]\-[0-9]+$")
	gen errorflag = (!inlist(exclusivity_code, "NC", "NCE", "NCE*", "NDF", "NE", "NP", "NP*", "NPP", "NR") ///
		& !inlist(exclusivity_code, "NS", "ODE", "PC", "PED", "RTO", "RTO*", "RTO**", "W", "PP") ///
		& !regexm(exclusivity_code, "^[DIM]\-[0-9]+$"))
	tab errorflag, mi
	
	* additionally, subcodes for D, I, M cannot exceed the max number for the given year
	* import and save table of acceptable maximum codes by each year
preserve
	import excel using ${correct}maximum_exclusivity_codes.xlsx, clear firstrow
	save ${temp}max_exclusivity_codes.dta, replace
restore
	
	* extract letter and number from D, I, and M codes
	gen code = regexs(1) if regexm(exclusivity_code, "^([DIM])\-([0-9]+)$")
	tab code, mi
	gen number = regexs(2) if regexm(exclusivity_code, "^([DIM])\-([0-9]+)$")
	destring number, replace
	
	* merge on edition and code
	merge m:1 edition code using ${temp}max_exclusivity_codes.dta
	assert code=="M" & edition <= 1999 if _m==2
	drop if _merge == 2
	drop _merge
	* flag those with a number that is too large
	count if number > max_number & !mi(number)
	replace errorflag = 1 if number > max_number & !mi(number)
	export excel using ${discrep}form_errors_exclusivity.xlsx if errorflag, sheet("exclusivity_code") sheetreplace firstrow(variables)
	drop errorflag code number max_number
	
	save ${temp}exclusivity_codes_working.dta, replace

********************************************************************************
* Merge back in hand-coded corrections
	* import and save .dta for each variable we need to correct
	foreach var in application_number trade_name exclusivity_expiration exclusivity_code {
		import excel using ${correct}form_errors_exclusivity_corrections.xlsx, sheet("`var'") clear firstrow allstring
		destring edition errorflag, replace
		
		save ${temp}exclusivity_code_corrections_`var'.dta, replace
		}
		
	* use working patent data
use ${temp}exclusivity_codes_working.dta, clear
	* create new variables to store corrections
	foreach var in application_number product_number exclusivity_code exclusivity_expiration trade_name active_ingredient {
		gen `var'NEW = `var'
		}
	
	gen to_drop = 0
	
	* merge in corrections
	foreach var in application_number trade_name exclusivity_expiration exclusivity_code {
	merge 1:1 application_number product_number exclusivity_code exclusivity_expiration edition trade_name active_ingredient using ${temp}exclusivity_code_corrections_`var'.dta, keepusing(new note)
	assert _merge != 2
	drop _merge
	
	replace `var'NEW = new if !mi(new)
	replace to_drop = 1 if note=="DROP"
	
	* now do other corrections according to notes
	if "`var'"=="application_number" {
		list note if !mi(note)
		* nothing to do
		local check = 1
		}
	if "`var'"=="trade_name" {
		list note if !mi(note)
		* nothing to do
		local check = 1
		}
	if "`var'"=="exclusivity_expiration" {
		list note if !mi(note)
		* nothing to do
		local check = 1
		}
	if "`var'"=="exclusivity_code" {
		list note if !mi(note)
		* nothing to do
		local check = 1
		}
	
	* check that we went into a conditional statement
	assert `check'==1
	* drop new and note
	drop new note
	* resent check to 0
	local `check' = 0
	}

	* drop observations
	tab to_drop, mi
	drop if to_drop
	drop to_drop
	
	* now replace variables with corrected versions
	foreach var in application_number product_number exclusivity_code exclusivity_expiration trade_name active_ingredient {
		replace `var' = `var'NEW
		drop `var'NEW
		}
	
	save ${temp}exclusivity_codes_internally_corrected.dta, replace
	
********************************************************************************
* Do final check of variable formats and key variables
	duplicates tag application_number product_number exclusivity_code exclusivity_expiration edition, gen(tag)
	tab tag
	assert tag==0
	drop tag
		
	isid application_number product_number exclusivity_code exclusivity_expiration edition
	mdesc
	assert r(miss_vars)==.
	
	* check forms of final data
	* application_number
	assert regexm(application_number, "^[NA]?[0-9]?[0-9][0-9][0-9][0-9][0-9]$")
	assert inrange(length(application_number), 5, 7)
	assert (regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1985, 1997)) ///
		| (regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1998, 2009))
	assert (length(application_number)==5 & inrange(edition, 1985, 1997)) ///
		| (length(application_number)==6 & inrange(edition, 1998, 2009))
		
	* product_number
	assert regexm(product_number, "^[0-9][0-9][0-9]$")
	assert length(product_number)==3
	
	* active_ingredient
	assert !mi(active_ingredient)
	
	* trade_name
	assert !mi(trade_name)
	
	* exclusivity expiration
	assert regexm(exclusivity_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
	assert length(exclusivity_expiration)==12
	
	* exclusivity_code
	assert inlist(exclusivity_code, "NC", "NCE", "NCE*", "NDF", "NE", "NP", "NP*", "NPP", "NR") ///
		| inlist(exclusivity_code, "NS", "ODE", "PC", "PED", "RTO", "RTO*", "RTO**", "W", "PP") ///
		| exclusivity_code == "GAIN" ///
		| regexm(exclusivity_code, "^[DIM]\-[0-9]+$")
		
	* duplicate_count
	tab duplicate_count, mi
	assert !mi(duplicate_count)
	
	* edition
	assert inrange(edition, 1985, 2004)
	assert edition != 1986
	
	compress
	save ${temp}final_exclusivity_data_internally_corrected.dta, replace
	
********************************************************************************
********************************************************************************
*********** STEP 4: CROSS CHECK PATENTS DATA ***********************************
********************************************************************************
********************************************************************************

* Now having internally corrected DDD data and comparison sources, we now merge the two sources
* on key variables and compare, resolving any differences
* We do this separately for the patents and exclusivity files

* This is the most complex and intricate portion of the code, involving a lot of exporting and importing
* of Excel files to make corrections
* Detailed information about these procedures can be found in the documenation in this /raw/ directory
		
* compare patent data
* load data from parsing and paper_orange_book
use ${temp}comparison_patents1985-2004.dta, clear
	
	* export data with "?" to fix manually
	* for 1996-1999, many of the application and products numbers were cut off in scans
	* leading to many "?"s being entered
	keep if regexm(application_number, "\?") | regexm(product_number, "\?")
	assert inlist(edition, 1996, 1997, 1998, 1999)
	sort edition active_ingredient trade_name application_number product_number patent_number use_code
	order application_number product_number active_ingredient trade_name patent_number patent_expiration use_code
	
	export excel using ${discrep}paper_orange_book_to_fix.xlsx, replace firstrow(variables)
	
	*** ... make corrections in excel file, then re-import
	import excel using ${correct}paper_orange_book_to_fix_corrections.xlsx, clear firstrow
	* save tempfile to merge back into comparison file
	tempfile corrections
	save `corrections'
	
	* merge in corrections
use ${temp}comparison_patents1985-2004.dta, clear
	merge 1:1 application_number product_number patent_number edition use_code using `corrections', keepusing(application_number_new product_number_new notes)
	assert _merge != 2
	assert mi(notes)
	assert !mi(application_number_new) | !mi(product_number_new) if _m==3
	drop notes _merge
	
	* trim corrections in case there are extra spaces
	foreach var in application_number_new product_number_new {
		replace `var' = trim(itrim(`var'))
		}
	
	* make corrections
	foreach var in application_number product_number {
		replace `var' = `var'_new if !mi(`var'_new)
		drop `var'_new
		}
	
	* we have some duplicates
	* for now, just force drop these
	* errors will be corrected as we do the cross-check
	duplicates tag application_number product_number patent_number edition use_code, gen(tag)
	assert tag==1 | tag==0
	count if tag==1
	assert r(N)==4
	duplicates drop application_number product_number patent_number edition use_code, force
	drop tag
	
	isid application_number product_number patent_number edition use_code, mi

	* save base data set that with corrected application and product numbers
	save ${temp}comparison_patents1985-2004_w_corrected_numbers.dta, replace

* load comparison data and merge with DDD data
* this will allow us to find application_number-product_number pairs that are only in
* one of the sources and needs to be corrected/added/deleted
use ${temp}comparison_patents1985-2004_w_corrected_numbers.dta, clear
	* rename non-key variables before the merge
	* "C" for Cross-check source
	foreach var in trade_name active_ingredient patent_expiration DS_DP {
		rename `var' `var'_C
		}
	
	* merge with DDD data
	merge 1:1 application_number product_number patent_number edition use_code using ${temp}final_patent_data_internally_corrected.dta
	tab _merge
	
	* find the number of application_number-product_number pairs (within edition) that are only in comparison/only in base DDD data
	forvalues i = 1/3 {
		bysort application_number product_number edition: egen total`i' = total(_m==`i')
		}

	* export a file of products only in comparison data
	* will manually go through these to see if they are mistakes, should be added to base DDD data, etc.
preserve
	egen tag = tag(application_number product_number edition total1 total2 total3)
	keep if tag
	isid application_number product_number edition
	
	* this keeps those groups only in comparison data
	keep if total1 & !(total2 | total3)
	keep edition application_number product_number patent_number use_code *_C
	sort edition application_number product_number
	export excel using ${discrep}products_in_only_one_source.xlsx, sheetreplace sheet("only in comparison") firstrow(variables)
restore

* export a file of products only in base DDD data
* will manually go through these to see if they are mistakes, etc.
preserve	
	egen tag = tag(application_number product_number edition total1 total2 total3)
	keep if tag
	isid application_number product_number edition
	
	* this keeps those groups only in DDD data
	keep if total2 & !(total1 | total3)
	keep edition application_number product_number patent_number use_code patent_expiration trade_name active_ingredient DS_DP
	sort edition application_number product_number
	export excel using ${discrep}products_in_only_one_source.xlsx, sheetreplace sheet("only in DDD") firstrow(variables)
restore
	
********************************************************************************
* ... manually go through these two sheets of output and make any corrections/deletions/additions
********************************************************************************

* import those products that were only in comparison data and make corrections to comparison data
import excel using ${correct}products_in_only_one_source_corrections.xlsx, sheet("only in comparison") firstrow clear
	assert !mi(new_application_number) | !mi(new_product_number) | !mi(notes)
	tostring new_product_number, replace
	replace new_product_number = "" if new_product_number=="."
	* trim in case there are extra spaces
	foreach var in new_product_number new_application_number notes {
		replace `var' = upper(trim(itrim(`var')))
		}
	* save temporary file of corrections
	tempfile new_comparison
	save `new_comparison'

	* use comparison data and merge in corrections
	use ${temp}comparison_patents1985-2004_w_corrected_numbers.dta, clear
	merge m:1 application_number product_number edition using `new_comparison', keepusing(new_product_number new_application_number notes)
	assert _merge != 2
	
	tab notes, mi
	
	* first drop some observations
	drop if regexm(notes, "^REMOVE")
	tab notes, mi
	assert inlist(notes, "", "CORRECT")
	
	* replace application number and product number with corrections
	foreach var in application_number product_number {
		replace `var' = new_`var' if !mi(new_`var')
		}
	mdesc
	drop new_application_number new_product_number notes _merge
	
	isid application_number product_number patent_number edition use_code, mi

	* save updated comparison file
	save ${temp}comparison_patents1985-2004_update1.dta, replace

* now import those products only in base DDD data
import excel using ${correct}products_in_only_one_source_corrections.xlsx, sheet("only in DDD") firstrow clear
	assert !mi(new_application_number) | !mi(new_product_number) | !mi(notes)
	tostring new_product_number, replace
	replace new_product_number = "" if new_product_number=="."
	assert mi(new_product_number)
	
	* trim in case of extra spaces
	foreach var in new_product_number new_application_number notes {
		replace `var' = upper(trim(itrim(`var')))
		}
	* save temporary file of corrections to make
	tempfile new_DDD
	save `new_DDD'
	
	* use base DDD data and merge in corrections
	use ${temp}final_patent_data_internally_corrected.dta, clear
	merge m:1 application_number product_number edition using `new_DDD', keepusing(new_product_number new_application_number notes)
	assert _merge != 2
	
	tab notes, mi
	* first drop some observations
	drop if regexm(notes, "^REMOVE")
	tab notes, mi
	assert inlist(notes, "", "CORRECT")

	* replace application number and product number with corrections
	foreach var in application_number product_number {
		replace `var' = new_`var' if !mi(new_`var')
		}
	mdesc
	drop new_application_number new_product_number notes _merge
	
	isid application_number product_number patent_number edition use_code, mi

	* save updated base DDD file
	save ${temp}final_patent_data_internally_corrected_update1.dta, replace

* now compare again to see if any application_number-product_number groups are missing from DDD data
use ${temp}comparison_patents1985-2004_update1.dta, clear
	foreach var in trade_name active_ingredient patent_expiration DS_DP {
		rename `var' `var'_C
		}
		
	* merge with DDD data
	merge 1:1 application_number product_number patent_number edition use_code using ${temp}final_patent_data_internally_corrected_update1.dta
	tab _merge
	
	* find the number of application_number-product_number pairs (within edition) that are only in comparison/only in base DDD data
	forvalues i = 1/3 {
		bysort application_number product_number edition: egen total`i' = total(_m==`i')
		}

preserve
	* keep products only in comparison data
	* these products need to be added to the DDD data
	egen tag = tag(application_number product_number edition total1 total2 total3)
	keep if tag
	isid application_number product_number edition
	
	* the line below keeps those product groups that are only in comparison data
	keep if total1 & !(total2 | total3)
	keep edition application_number product_number patent_number use_code *_C
	sort edition application_number product_number
	list
	* do a handcheck of this list
	* confirm that all of those remaining in only the comparison data are truly missing from base data
restore

********************************************************************************
* ... manually code the product groups that are missing from base data
********************************************************************************
* import set of products to append
import excel using ${correct}product_to_add_to_base_data.xlsx, clear firstrow 
	destring edition, replace
	* save temporary file of products to append
	tempfile products_to_append
	save `products_to_append'

	use ${temp}final_patent_data_internally_corrected_update1.dta, clear
	append using `products_to_append'

	sort edition application_number product_number patent_number use_code
	isid edition application_number product_number patent_number use_code, mi
	mdesc
	
	* save updated base data set
	save ${temp}base_dataset_v1.dta, replace

* now compare again to see if any product groups are missing from base data
* load comparison data
use ${temp}comparison_patents1985-2004_update1.dta, clear
	foreach var in trade_name active_ingredient patent_expiration DS_DP {
		rename `var' `var'_C
		}
		
	* merge with base data
	merge 1:1 application_number product_number patent_number edition use_code using ${temp}base_dataset_v1.dta
	tab _merge
	
	forvalues i = 1/3 {
		bysort application_number product_number edition: egen total`i' = total(_m==`i')
		}

preserve
	* keep products only in comparison data
	* these products need to be added to the DDD data
	egen tag = tag(application_number product_number edition total1 total2 total3)
	keep if tag
	isid application_number product_number edition
	
	* assert that there are no application_number-product number pairs only in comparison data
	keep if total1 & !(total2 | total3)
	count
	assert r(N)==0
restore


preserve	
	* keep product groups only in DDD data
	egen tag = tag(application_number product_number edition total1 total2 total3)
	keep if tag
	isid application_number product_number edition
	
	keep if total2 & !(total1 | total3)
	keep edition application_number product_number patent_number use_code patent_expiration trade_name active_ingredient DS_DP
	sort edition application_number product_number
	list
	* do a handcheck of this list
	* confirm that all of those remanining in only the DDD data are truly missing from comparison data
restore

* now we will export a full data set to review the product groups that are common
* to both data sets but that differ on other key variables (patent number, use code)
	gen review_flag = (total1 | total2)
	sort edition application_number product_number patent_number
	export excel using ${discrep}base_dataset_v1.xlsx, replace firstrow(variables)
	
	* .... do hand corrections

* import hand corrections and integrate with base and comparison datasets
import excel using ${correct}base_dataset_v1_corrections.xlsx, clear firstrow sheet("corrections")
	destring review_flag, replace

	* assert that changes have been made where they need to be made
	bysort edition application_number product_number: egen changes = total(!mi(action1) | !mi(action2) | !mi(notes))
	tab changes, mi
	assert changes > 0 if review_flag==1
	drop changes

	* make the merge variable numeric again
	* because it had turned to string after export then re-importing with Excel
	rename _merge _merge2
	gen _merge = .
	forvalues i = 1/3 {
		replace _merge = `i' if regexm(_merge2, "`i'")
		}
	assert !mi(_merge)
	drop _merge2

	* standardize new variables
	foreach var in action1 action2 notes {
		replace `var' = upper(trim(itrim(`var')))
		}
	tab action1, mi
	* make corrections
	replace action1 = "ADD TO BASE" if inlist(action1, "APPEND TO BASE", "APPNED TO BASE")
	replace action1 = "REMOVE" if action1=="REMOIVE"

	assert regexm(action1, "^(([0-9][0-9])|(RE)|(D[0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?$") | regexm(action1, "^U\-[0-9]+$") | ///
		inlist(action1, "DELETE USE CODE", "ADD TO BASE", "REMOVE") | mi(action1)

	tab action2, mi
	assert regexm(action2, "^(([0-9][0-9])|(RE)|(D[0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?$") | regexm(action2, "^U\-[0-9]+$") | ///
		inlist(action2, "DELETE USE CODE", "ADD TO BASE", "REMOVE") | mi(action2)

	* don't need to standardize notes
	tab notes, mi
	replace notes = "ONLY IN DDD: OK" if notes=="IN DDD ONLY: OK"

preserve
	* keep those changes that need to be made to base data
	* keep if _m==2 or _m==3
	* _m==2 indicates that entry was only in base and may need to be changed
	* _m==3 indicates that entry was in both and may need to be changed
	keep if inlist(_merge, 2, 3)
	isid application_number product_number patent_number edition use_code, mi
	keep application_number product_number patent_number edition use_code action1 action2 notes
	
	* merge with base data set
	merge 1:1 application_number product_number patent_number edition use_code using ${temp}base_dataset_v1.dta
	assert _merge==3
	* every observation should merge successfully since we kept only _m==2 and _m==3
	drop _merge
	
	tab action1
	assert regexm(action1, "^(([0-9][0-9])|(RE)|(D[0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?$") | regexm(action1, "^U\-[0-9]+$") | ///
		inlist(action1, "DELETE USE CODE", "ADD TO BASE", "REMOVE") | mi(action1)
	tab action2
	assert regexm(action2, "^(([0-9][0-9])|(RE)|(D[0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?$") | regexm(action2, "^U\-[0-9]+$") | ///
		inlist(action2, "DELETE USE CODE", "ADD TO BASE", "REMOVE") | mi(action2)
	
	tab notes
	
	* make corrections
	foreach var in action1 action2 {
		drop if `var'=="REMOVE"
		replace use_code = "" if `var'=="DELETE USE CODE"
		replace patent_number = `var' if regexm(`var', "^(([0-9][0-9])|(RE)|(D[0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?$")
		replace use_code = `var' if regexm(`var', "^U\-[0-9]+$")
		}
		
	assert regexm(notes, "ONLY") if !mi(notes)
	gen only_in_base_flag = !mi(notes)
	drop action1 action2 notes
	isid application_number product_number patent_number edition use_code, mi
	
	* save updated base data set
	save ${temp}base_dataset_v2.dta, replace
restore

preserve
	* keep those changes that need to be made to comparison data
	* keep if _m==1 or _m==3
	* _m==1 indicates that entry was only in comparison and may need to be changed
	* _m==3 indicates that entry was in both and may need to be changed
	keep if inlist(_merge, 1, 3)
	isid application_number product_number patent_number edition use_code, mi
	keep application_number product_number patent_number edition use_code action1 action2 notes
	
	* merge with comparison data set
	merge 1:1 application_number product_number patent_number edition use_code using ${temp}comparison_patents1985-2004_update1.dta
	assert _merge==3
	drop _merge
	
	tab action1
	assert regexm(action1, "^(([0-9][0-9])|(RE)|(D[0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?$") | regexm(action1, "^U\-[0-9]+$") | ///
		inlist(action1, "DELETE USE CODE", "ADD TO BASE", "REMOVE") | mi(action1)
	tab action2
	assert regexm(action2, "^(([0-9][0-9])|(RE)|(D[0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?$") | regexm(action2, "^U\-[0-9]+$") | ///
		inlist(action2, "DELETE USE CODE", "ADD TO BASE", "REMOVE") | mi(action2)
	
	tab notes, mi
	assert mi(notes)
	
	* make corrections
	foreach var in action1 action2 {
		drop if `var'=="REMOVE"
		replace use_code = "" if `var'=="DELETE USE CODE"
		replace patent_number = `var' if regexm(`var', "^(([0-9][0-9])|(RE)|(D[0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?$")
		replace use_code = `var' if regexm(`var', "^U\-[0-9]+$")
		}
	
	drop action1 action2 notes
	isid application_number product_number patent_number edition use_code, mi
	
	* save updated comparison data set
	save ${temp}comparison_patents1985-2004_update2.dta, replace
restore

* next we save a data set of observations from comparison set that need to be appended to base data
preserve
	keep if inlist(_merge, 1, 3)
	isid application_number product_number patent_number edition use_code, mi
	tab action1
	keep if action1=="ADD TO BASE"
	count
	keep application_number product_number patent_number edition use_code
	
	* indicate that these observations are only from comparison data
	* this will allow us to re-check all non-key variables
	gen only_in_base_flag = 0
	gen only_in_comparison_flag = 1
	* save tempfile to append
	tempfile to_append
	save `to_append'
restore

* save a data set of other observations that were in neither data set but that need to be appended to base data
import excel using ${correct}base_dataset_v1_corrections.xlsx, clear firstrow sheet("rows_to_add")
	tab note
	assert note=="ONLY IN DDD: OK"
	drop note
	* indicate that this is only in base data
	gen only_in_base_flag = 1
	
	destring edition, replace
	
	* save tempfile to append
	tempfile to_append2
	save `to_append2'

* load working base data set
use ${temp}base_dataset_v2.dta, clear
	* append additional observations
	append using `to_append'
	append using `to_append2'
	isid application_number product_number patent_number edition use_code, mi
	
	replace only_in_comparison_flag = 0 if mi(only_in_comparison_flag)
	
	* save updated base data
	save ${temp}base_dataset_v3.dta, replace
	
* now load comparison data set and check that merge with comaprison works for all observations
* except those that are only in base
use ${temp}comparison_patents1985-2004_update2.dta, clear
	isid application_number product_number patent_number edition use_code, mi
	
	
	* at this point I noticed that trade_name and active_ingredient are swapped in 1987 edition
	* correct this
	gen trade_name_old = trade_name
	gen active_ingredient_old = active_ingredient
	
	replace trade_name = active_ingredient_old if edition==1987
	replace active_ingredient = trade_name_old  if edition==1987
	drop trade_name_old active_ingredient_old

	
	* rename non-key variables before merge
	foreach var in trade_name active_ingredient patent_expiration DS_DP {
		rename `var' `var'_C
		}
	
	* merge with base data
	merge 1:1 application_number product_number patent_number edition use_code using ${temp}base_dataset_v3.dta
	* merge should never be 1, i.e. all observations should be in base data
	assert _merge != 1
	* merge should be 2 only if indicated that an observation is only in base data
	assert only_in_base_flag==1 if _merge==2
	drop _merge
	
	mdesc
	assert !mi(only_in_base_flag) & !mi(only_in_comparison_flag)
	
	* now we want to export a file of mis-matches on non-key variables
	* also keep all observations that are only in base or comparison to check values of non-key variables
	foreach var in patent_expiration trade_name active_ingredient DS_DP {
		preserve
		
		di "`var'"
		count if (`var' != `var'_C) | (only_in_base_flag==1) | (only_in_comparison_flag==1)
		local check = r(N)
		* keep if base var not equal to comparison var or the observation is flagged
		* as originating from one of the data sets
		keep if (`var' != `var'_C) | (only_in_base_flag==1) | (only_in_comparison_flag==1)
		
		keep application_number product_number patent_number edition use_code `var' `var'_C only_in_base_flag only_in_comparison_flag
		
		gen variable = "`var'"
		rename (`var' `var'_C) (base comparison)
		
		count
		assert `check' == r(N)
		* save temporary files to append together later
		tempfile `var'
		save ``var''
		
		restore	
		}
	
	* use the patent_expiration tempfile
	use `patent_expiration', clear
	* to this append temporary files for other non-key variable discrepancies
	foreach file in trade_name active_ingredient DS_DP {
		append using ``file''
		}
	
	assert mi(comparison) if only_in_base_flag==1
	assert mi(base) if only_in_comparison_flag==1
	
	order edition application_number product_number patent_number use_code base comparison only_in_base_flag variable
	sort edition application_number product_number patent_number use_code
	
	* export Excel of mismatches
	isid edition application_number product_number patent_number use_code variable, mi
	export excel using ${discrep}non_key_variable_mismatches.xlsx, firstrow(variables) sheetreplace

	* ... manually review and make corrections by hand
	
	* import corrections
	import excel using ${correct}non_key_variable_mismatches_corrections.xlsx, clear firstrow
	drop if notes=="DUPLICATE ROW?"
	isid edition application_number product_number patent_number use_code variable, mi

	* do some simiple checks of data
	assert !mi(action)
	assert mi(notes)
	drop notes

	assert inlist(action, "B", "C") if length(action)==1
	list if action!="B" & only_in_base_flag
	list if action!="C" & only_in_comparison_flag
	tab only*

	* drop if action=="B", i.e., base data is correct and doesn't need changed
	drop if action=="B"
	keep edition application_number product_number patent_number use_code variable comparison action
	tab action, mi

	* now we put the data in a form where we can replace the base data with corrected values
	* for those instances in which the comparison data is correct
	rename comparison correction
	replace correction = action if action != "C"
	drop action

	reshape wide correction, i(edition application_number product_number patent_number use_code) j(variable) string
	isid edition application_number product_number patent_number use_code, mi

	* save .dta of non-key variable corrections to be merged with base data
	save ${temp}patent_non_key_corrections.dta, replace

	* merge these corrections into base file to make final corrections
	use ${temp}base_dataset_v3.dta, clear

	* merge in corrections to non-key variables
	merge 1:1 application_number product_number patent_number edition use_code using ${temp}patent_non_key_corrections.dta
	assert _merge != 2
	drop _merge

	* trim correction values to make sure there are no extra spaces
	* and then replace variable in base data if comparison data is correct
	foreach var in patent_expiration trade_name active_ingredient DS_DP {
		replace correction`var' = trim(itrim(correction`var'))
		replace `var' = correction`var' if !mi(correction`var')
		}

	isid edition application_number product_number patent_number use_code, mi
	drop only_in_base_flag only_in_comparison_flag correctionDS_DP correctionactive_ingredient correctionpatent_expiration correctiontrade_name
	
	* append 2005-2016 data
	append using ${temp}parsed_patents2005-2016.dta
	isid edition application_number product_number patent_number use_code, mi

	* do a check that active_ingredient and trade_name do not vary within edition-application_number-product_number
	sort edition application_number product_number patent_number use_code
	foreach var in active_ingredient trade_name {
		by edition application_number product_number: assert `var'==`var'[_n-1] if !mi(`var'[_n-1])
		}
		
	* do final check of variable formats
	* check that N/A is where it should be
	assert active_ingredient == "N/A" if edition < 1987
	assert active_ingredient != "N/A" if edition >= 1987
	
	assert trade_name == "N/A" if edition < 1987
	assert trade_name != "N/A" if edition >= 1987
	
	assert use_code == "N/A" if edition < 1988
	assert use_code != "N/A" if edition >= 1988

	assert DS_DP == "N/A" if edition < 2004
	assert DS_DP != "N/A" if edition >= 2004
	
	replace delist = "N/A" if edition < 2009
	assert delist == "N/A" if edition < 2009
	assert delist != "N/A" if edition >= 2009
	
	* check forms of variables
	* application number
	assert regexm(application_number, "^[NA]?[0-9]?[0-9][0-9][0-9][0-9][0-9]$")
	assert (regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1985, 1997)) ///
		| (regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1998, 2009)) ///
		| (regexm(application_number, "^[NA][0-9][0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 2010, 2016))
	assert (length(application_number)==5 & inrange(edition, 1985, 1997)) ///
		| (length(application_number)==6 & inrange(edition, 1998, 2009)) ///
		| (length(application_number)==7 & inrange(edition, 2010, 2016))
	* product number
	assert regexm(product_number, "^[0-9][0-9][0-9]$")
	assert length(product_number)==3
	* active_ingredient
	assert !mi(active_ingredient)
	assert !strpos(active_ingredient, "?") // make sure there are no marks for illegible PDFs
	* trade_name
	assert !mi(trade_name)
	assert !strpos(trade_name, "?")
	* patent_number
	assert regexm(patent_number, "^((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9](\*PED)?$")
	assert inlist(length(patent_number), 7, 11)
	* patent_expiration
	assert regexm(patent_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
	gen datetemp = date(patent_expiration, "MDY")
	assert !mi(datetemp)
	drop datetemp
	assert length(patent_expiration)==12
	* DS_DP
	assert (inlist(DS_DP, "", "DS", "DP", "DS/DP") & edition >= 2004) | (DS_DP=="N/A" & edition < 2004)
	assert inlist(length(DS_DP), 0, 2, 3, 5)
	* delist
	assert (delist == "N/A" & edition < 2009) | (inlist(delist, "", "Y") & edition >= 2009)
	assert inlist(length(delist), 0, 1, 3)
	* use_code
	assert ((regexm(use_code, "^U\-[0-9]+$") | mi(use_code)) & edition >= 1988) | (use_code=="N/A" & edition < 1988)
	* edition
	assert !mi(edition)
	assert inrange(edition, 1985, 2016)
	assert edition != 1986
	
	duplicates tag, gen(tag)
	assert tag == 0
	drop tag
	
	assert !mi(application_number, product_number, patent_number, patent_expiration, edition, trade_name, active_ingredient)
	
	* put variables into final form and construct addional variables
	replace application_number = "0" + application_number if edition <= 1997
	assert regexm(application_number, "^[NA]?[0-9][0-9][0-9][0-9][0-9][0-9]$")
	
	* application_type
	gen application_type = regexs(1) if regexm(application_number, "^([NA]?)[0-9][0-9][0-9][0-9][0-9][0-9]$")
	tab application_type, mi
	assert (mi(application_type) & edition < 2010) | (!mi(application_type) & edition >= 2010)
	replace application_type = "ANDA" if application_type == "A"
	replace application_type = "NDA" if application_type == "N"
	replace application_type = "N/A" if mi(application_type)
	
	replace application_number = substr(application_number, -6, .)
	assert regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9][0-9]$")
	
	* ped_extenstion
	gen ped_extension = regexm(patent_number, "\*PED")
	tab ped_extension
	assert ped_extension == 0 if edition < 1999
	replace patent_number = regexr(patent_number, "\*PED$", "")
	assert length(patent_number) == 7
	assert regexm(patent_number, "^((D[0-9])|(RE)|([0-9][0-9]))[0-9][0-9][0-9][0-9][0-9]$")
	
	* patent_expiration
	rename patent_expiration patent_expiration_old
	gen patent_expiration = date(patent_expiration_old, "MDY")
	assert !mi(patent_expiration)
	format patent_expiration %td
	drop patent_expiration_old
	
	* DS and DP
	foreach var in DS DP {
		gen `var' = "1" if regexm(DS_DP, "`var'")
		replace `var' = "N/A" if DS_DP=="N/A"
		replace `var' = "0" if mi(`var')
		}
	drop DS_DP
	
	* delist_requested
	gen delist_requested = "1" if delist=="Y"
	replace delist_requested = "N/A" if delist=="N/A"
	replace delist_requested = "0" if mi(delist_requested)
	drop delist
	
	order edition application_type application_number product_number patent_number ///
		patent_expiration use_code active_ingredient trade_name DS DP ped_extension delist_requested
	sort edition application_type application_number product_number patent_number use_code
	isid edition application_number product_number patent_number use_code ped_extension, mi
	
	* label variables
	label var edition "orange book edition (year)"
	label var application_type "'NDA' or 'ANDA' or 'N/A'"
	label var application_number "FDA application number"
	label var product_number "FDA product number"
	label var patent_number "USPTO patent number"
	label var patent_expiration "patent expiration date"
	label var use_code "patent use code; missing if no use code; 'N/A' if edition<1988"
	label var active_ingredient "drug active ingredient(s)"
	label var trade_name "drug trade name"
	label var DS "drug substance claim indicator '1' for yes, '0' for no, or 'N/A'"
	label var DP "drug product claim indicator '1' for yes, '0' for no, or 'N/A'"	
	label var ped_extension "indicates patent has received 6-month extension for pediatric use"
	label var delist_requested "sponsor has requested patent be delisted"
	
	* make some final changes
	* there are some weird patent_expiration dates
	* these are wrong in orange books, not wrong from data entry
	* fix those here
	gen year = year(patent_expiration)
	tab year
	list if year > 2034
	replace patent_expiration = td(09jul2008) if patent_expiration==td(09jul2208)
	replace patent_expiration = td(11feb2014) if patent_expiration==td(03apr2115)
	replace patent_expiration = td(17aug2010) if patent_expiration==td(11feb2117)
	replace year = year(patent_expiration)
	sum year
	assert year <= 2035
	drop year
	
	* last check of all variable forms
	assert inrange(edition, 1985, 2016)
	assert inlist(application_type, "NDA", "ANDA", "N/A")
	assert regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9][0-9]$")
	assert regexm(product_number, "^[0-9][0-9][0-9]$")
	assert length(patent_number)==7
	assert !mi(patent_expiration)
	assert (use_code == "N/A" & edition < 1988) | (use_code != "N/A" & edition >= 1988)
	assert regexm(use_code, "^U\-[0-9]+$") | mi(use_code) if edition >= 1988
	assert !mi(active_ingredient)
	assert !mi(trade_name)
	assert (DS == "N/A" & edition < 2004) | (inlist(DS, "0", "1") & edition >= 2004)
	assert (DP == "N/A" & edition < 2004) | (inlist(DP, "0", "1") & edition >= 2004)
	assert inlist(ped_extension, 0, 1)
	assert (delist_requested == "N/A" & edition < 2009) | (inlist(delist_requested, "0", "1") & edition >= 2009)
	
	* ad-hoc changes to trade_name
	replace trade_name = "SEPTRA DS" if edition==1996 & application_number=="017376" ///
		& product_number=="002" & trade_name=="SEPTRA"
	replace trade_name = "CALCIJEX" if trade_name=="GALCIJEX" & edition==1989 ///
		& application_number=="018874" & product_number=="002"
	* ad-hoc changes to active_ingredient
	replace active_ingredient = "CARMUSTINE" if edition==1997 & application_number=="020637" ///
		& product_number=="001" & active_ingredient=="CARMUSTLNE"
	replace active_ingredient = "GEMCITABINE HYDROCHLORIDE" if edition==1998 ///
		& application_number=="020509" & inlist(product_number, "001", "002") & ///
		active_ingredient=="GEMCITABINE HYCROCHLORIDE"
	
	* save final datasets
	* save one of all observations
	save ${dta}FDA_drug_patents.dta, replace
	
	* end constructing patent files

********************************************************************************
********************************************************************************
*********** STEP 5: CROSS CHECK EXCLUSIVITY DATA *********************************
********************************************************************************
********************************************************************************	
* We now do the cross-check for exclusivity files in a manner very similar to how we did patents files

* compare exclusivity data
* load data from parsing and paper_orange_book
use ${temp}comparison_exclusivity1985-2004.dta, clear

	* export data with "?" to fix manually
	* for 1996-1999, many of the application and products numbers were cut off in scans
	* leading to many "?"s being entered
	keep if regexm(application_number, "\?") | regexm(product_number, "\?")
	assert inlist(edition, 1996, 1997, 1998, 1999)
	sort edition active_ingredient trade_name application_number product_number
	order application_number product_number active_ingredient trade_name
	
	export excel using ${discrep}paper_orange_book_to_fix_exclusivity.xlsx, replace firstrow(variables)
	
	*** ... make corrections in excel file, then re-import
	import excel using ${correct}paper_orange_book_to_fix_exclusivity_corrections.xlsx, clear firstrow
	* save tempfile to merge back into comparison file
	tempfile corrections
	save `corrections'

* use comparison data and merge in corrections tempfile
use ${temp}comparison_exclusivity1985-2004.dta, clear
	merge 1:1 application_number product_number exclusivity_code exclusivity_expiration edition using `corrections', keepusing(application_number_new product_number_new notes)
	assert _merge != 2
	assert mi(notes)
	assert !mi(application_number_new) | !mi(product_number_new) if _m==3
	drop notes _merge

	* trim corrections in case there are extra spaces
	foreach var in application_number_new product_number_new {
		replace `var' = trim(itrim(`var'))
		}
	
	* make corrections
	foreach var in application_number product_number {
		replace `var' = `var'_new if !mi(`var'_new)
		drop `var'_new
		}
		
	* we now have some duplicates on key variables
	duplicates tag application_number product_number exclusivity_code exclusivity_expiration edition, gen(tag)
	assert tag==1 | tag==0
	count if tag==1
	assert r(N)==2
	drop tag
	
	* just force drop these duplicats for now
	* issues will be resolved as we cross check
	duplicates drop application_number product_number exclusivity_code exclusivity_expiration edition, force
	
	isid application_number product_number exclusivity_code exclusivity_expiration edition, mi
		
	* save base data set that with corrected application and product numbers
	save ${temp}comparison_exclusivity1985-2004_w_corrected_numbers.dta, replace

* load comparison data and merge with DDD data
* this will allow us to find application_number-product_number pairs that are only in
* one of the sources and needs to be corrected/added/deleted
use ${temp}comparison_exclusivity1985-2004_w_corrected_numbers.dta, clear
	* rename non-key variables before the merge
	foreach var in trade_name active_ingredient duplicate_count {
		rename `var' `var'_C
		}

	* merge with DDD data
	merge 1:1 application_number product_number exclusivity_code exclusivity_expiration edition using ${temp}final_exclusivity_data_internally_corrected.dta
	tab _merge

	* find the number of application_number-product_number pairs (within edition) that are only in comparison/only in base DDD data
	forvalues i = 1/3 {
		bysort application_number product_number edition: egen total`i' = total(_m==`i')
		}

	* export a file of products only in comparison data
	* will manually go through these to see if they are mistakes, should be added to base DDD data, etc.
preserve
	egen tag = tag(application_number product_number edition total1 total2 total3)
	keep if tag
	isid application_number product_number edition
	
	* this keeps those groups only in comparison data
	keep if total1 & !(total2 | total3)
	keep application_number product_number exclusivity_code edition exclusivity_expiration *_C
	sort edition application_number product_number
	export excel using ${discrep}products_in_only_one_source_exclusivity.xlsx, sheetreplace sheet("only in comparison") firstrow(variables)
restore

* export a file of products only in base DDD data
* will manually go through these to see if they are mistakes, etc.
preserve	
	egen tag = tag(application_number product_number edition total1 total2 total3)
	keep if tag
	isid application_number product_number edition
	
	* this keeps those groups only in DDD data
	keep if total2 & !(total1 | total3)
	keep application_number product_number exclusivity_code edition exclusivity_expiration trade_name active_ingredient duplicate_count
	sort edition application_number product_number
	export excel using ${discrep}products_in_only_one_source_exclusivity.xlsx, sheetreplace sheet("only in DDD") firstrow(variables)
restore

********************************************************************************
* ... manually go through these two sheets of output and make any corrections/deletions/additions
********************************************************************************
		
* import those products that were only in comparison data and make corrections to comparison data
import excel using ${correct}products_in_only_one_source_exclusivity_corrections.xlsx, sheet("only in comparison") firstrow clear
	assert !mi(new_application_number) | !mi(new_product_number) | !mi(notes)
	replace new_product_number = "" if new_product_number=="."		
	* trim in case there are extra spaces
	foreach var in new_product_number new_application_number notes {
		replace `var' = upper(trim(itrim(`var')))
		}
	* save temporary file of corrections
	tempfile new_comparison
	save `new_comparison'
	
	* use comparison data and merge in corrections
	use ${temp}comparison_exclusivity1985-2004_w_corrected_numbers.dta, clear
	merge m:1 application_number product_number edition using `new_comparison', keepusing(new_product_number new_application_number notes)
	assert _merge != 2
	
	tab notes, mi

	* first drop some observations
	drop if regexm(notes, "^DELETE")
	tab notes, mi
	assert inlist(notes, "", "CORRECT")
	
	* replace application number and product number with corrections
	foreach var in application_number product_number {
		replace `var' = new_`var' if !mi(new_`var')
		}
	mdesc
	drop new_application_number new_product_number notes _merge
	
	* drop some new duplicates
	duplicates drop
	isid application_number product_number edition exclusivity_code exclusivity_expiration, mi
	
	* save updated comparison file
	save ${temp}comparison_exclusivity1985-2004_update1.dta, replace

* now import those products only in base DDD data
import excel using ${correct}products_in_only_one_source_exclusivity_corrections.xlsx, sheet("only in DDD") firstrow clear
	assert !mi(new_application_number) | !mi(new_product_number) | !mi(notes)
	
	* trim in case of extra spaces
	foreach var in new_product_number new_application_number notes {
		replace `var' = upper(trim(itrim(`var')))
		}
	* save temporary file of corrections to make
	tempfile new_DDD
	save `new_DDD'
	
	* use base DDD data and merge in corrections
	use ${temp}final_exclusivity_data_internally_corrected.dta, clear
	merge m:1 application_number product_number edition using `new_DDD', keepusing(new_product_number new_application_number notes)
	assert _merge != 2
	
	tab notes, mi
	* first drop some observations
	drop if regexm(notes, "^DELETE")
	tab notes, mi
	assert inlist(notes, "", "CORRECT")
	
	* replace application number and product number with corrections
	foreach var in application_number product_number {
		replace `var' = new_`var' if !mi(new_`var')
		}
	mdesc
	drop new_application_number new_product_number notes _merge
	
	isid application_number product_number edition exclusivity_code exclusivity_expiration, mi
	
	* save updated base DDD file
	save ${temp}final_exclusivity_data_internally_corrected_update1.dta, replace

* now compare again to see if any application_number-product_number groups are missing from DDD data
use ${temp}comparison_exclusivity1985-2004_update1.dta, clear
	foreach var in trade_name active_ingredient duplicate_count {
		rename `var' `var'_C
		}
		
	* merge with DDD data
	merge 1:1 application_number product_number exclusivity_code edition exclusivity_expiration using ${temp}final_exclusivity_data_internally_corrected_update1.dta
	tab _merge
	
	* find the number of application_number-product_number pairs (within edition) that are only in comparison/only in base DDD data
	forvalues i = 1/3 {
		bysort application_number product_number edition: egen total`i' = total(_m==`i')
		}

preserve
	* keep products only in comparison data
	* these products need to be added to the DDD data
	egen tag = tag(application_number product_number edition total1 total2 total3)
	keep if tag
	isid application_number product_number exclusivity_code edition exclusivity_expiration, mi
	
	* the line below keeps those product groups that are only in 
	keep if total1 & !(total2 | total3)
	keep  application_number product_number exclusivity_code edition exclusivity_expiration *_C
	sort edition application_number product_number
	list
	* do a handcheck of this list
	* confirm that all of those remaining in only the comparison data are truly missing from base data
restore	

* import corrected and omited products to add to base data
import excel using ${correct}products_to_add_exclusivity.xlsx, clear firstrow
	destring edition duplicate_count, replace
	tempfile products_to_append
	save `products_to_append'
	
use ${temp}final_exclusivity_data_internally_corrected_update1.dta, clear	
	* append new observations
	append using `products_to_append'

	sort application_number product_number edition exclusivity_code exclusivity_expiration
	isid application_number product_number edition exclusivity_code exclusivity_expiration
	mdesc
	
	* save updated base data set
	save ${temp}base_exclusivity_v2.dta, replace

* now compare again to see if any product groups are missing from base data
* load comparison data
use ${temp}comparison_exclusivity1985-2004_update1.dta, clear
	foreach var in trade_name active_ingredient duplicate_count {
		rename `var' `var'_C
		}
		
	* merge with base data
	merge 1:1 application_number product_number edition exclusivity_code exclusivity_expiration using ${temp}base_exclusivity_v2.dta
	tab _merge
	
	forvalues i = 1/3 {
		bysort application_number product_number edition: egen total`i' = total(_m==`i')
		}

preserve
	* keep products only in comparison data
	* these products need to be added to the DDD data
	egen tag = tag(application_number product_number edition total1 total2 total3)
	keep if tag
	isid application_number product_number edition
	
	* assert that there are no application_number-product number pairs only in comparison data
	keep if total1 & !(total2 | total3)
	count
	assert r(N)==0
restore
	
preserve	
	* keep product groups only in DDD data
	egen tag = tag(application_number product_number edition total1 total2 total3)
	keep if tag
	isid application_number product_number edition
	
	keep if total2 & !(total1 | total3)
	keep edition application_number product_number exclusivity_code exclusivity_expiration trade_name active_ingredient duplicate_count
	sort edition application_number product_number
	list
	* do a handcheck of this list
	* confirm that all of those remanining in only the DDD data are truly missing from comparison data
restore

* now we will export a full data set to review the product groups that are common
* to both data sets but that differ on other key variables (patent number, use code)
	gen review_flag = (total1 | total2)
	sort edition application_number product_number exclusivity_code exclusivity_expiration
	export excel using ${discrep}base_exclusivity_dataset_to_review.xlsx, replace firstrow(variables)
	
	* .... do hand corrections

* import corrections and integrate with base and comparison datasets
import excel using ${correct}base_exclusivity_dataset_to_review_corrections.xlsx, clear firstrow
	destring review_flag, replace
	
	* assert that changes have been made where they need to be made
	bysort edition application_number product_number: egen changes = total(!mi(action1) | !mi(action2) | !mi(notes))
	tab changes, mi
	assert changes > 0 if review_flag==1
	drop changes

	* make the merge variable numeric again
	* because it had turned to string after export then re-importing with Excel
	rename _merge _merge2
	gen _merge = .
	forvalues i = 1/3 {
		replace _merge = `i' if regexm(_merge2, "`i'")
		}
	assert !mi(_merge)
	drop _merge2

	* standardize new variables
	foreach var in action1 action2 notes {
		replace `var' = upper(trim(itrim(`var')))
		}
	tab action1, mi
	replace action1 = "DELETE ROW" if regexm(action1, "^REMOVE")
	tab action2, mi
	tab notes

preserve
	* keep those changes that need to be made to base data
	* keep if _m==2 or _m==3
	* _m==2 indicates that entry was only in base and may need to be changed
	* _m==3 indicates that entry was in both and may need to be changed
	keep if inlist(_merge, 2, 3)
	isid application_number product_number exclusivity_code exclusivity_expiration edition
	keep application_number product_number exclusivity_code exclusivity_expiration edition action1 action2 notes
	
	* merge with base data set
	merge 1:1 application_number product_number exclusivity_code exclusivity_expiration edition using ${temp}base_exclusivity_v2.dta
	* every observation should merge successfully since we kept only _m==2 and _m==3
	assert _merge==3
	drop _merge
	
	drop if regexm(action1, "^DELETE") | regexm(action2, "^DELETE")
	
	tab action1
	tab action2
	tab notes
	
	* ad-hoc change to application number
	replace application_number = "019766" if notes=="CHANGE APPLICATION NUMBER TO 019766"
	
	assert !regexm(action1, "APPEND") & !regexm(action2, "APPEND")
	* make corrections
	foreach var in action1 action2 {
		replace exclusivity_expiration = `var' if regexm(`var', "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
		replace exclusivity_code = `var' if !regexm(`var', "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$") & !mi(`var')
		}
	
	gen only_in_base_flag = !mi(notes) & !regexm(notes, "^CHANGE")
	drop action1 action2 notes
	isid application_number product_number exclusivity_code exclusivity_expiration edition

	* save updated base data set
	save ${temp}base_exclusivity_v3.dta, replace
restore

preserve
	* keep those changes that need to be made to base data
	* keep if _m==1 or _m==3
	* _m==1 indicates that entry was only in comparison and may need to be changed
	* _m==3 indicates that entry was in both and may need to be changed
	keep if inlist(_merge, 1, 3)
	isid application_number product_number exclusivity_code exclusivity_expiration edition, mi
	keep application_number product_number exclusivity_code exclusivity_expiration edition action1 action2 notes
	
	* merge with comparison data set
	merge 1:1 application_number product_number exclusivity_code exclusivity_expiration edition using ${temp}comparison_exclusivity1985-2004_update1.dta
	assert _merge==3
	drop _merge
	
	tab action1
	tab action2
	tab notes
	
	drop if regexm(action1, "^DELETE") | regexm(action2, "^DELETE")
	* ad-hoc change to application number
	replace application_number = "019766" if notes=="CHANGE APPLICATION NUMBER TO 019766"

	tab action1
	tab action2
	tab notes
	
	* make corrections
	foreach var in action1 action2 {
		replace exclusivity_expiration = `var' if regexm(`var', "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
		replace exclusivity_code = `var' if !regexm(`var', "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$") & !mi(`var') & !regexm(`var', "ADD TO BASE")
		}
	
	drop action1 action2 notes
	isid application_number product_number exclusivity_code exclusivity_expiration edition, mi
	
	* save updated comparison data set
	save ${temp}comparison_exclusivity1985-2004_update2.dta, replace
restore

* next we save a data set of observations from comparison set that need to be appended to base data
preserve
	keep if inlist(_merge, 1, 3)
	isid application_number product_number exclusivity_code exclusivity_expiration edition, mi
	tab action1
	keep if regexm(action1, "ADD TO BASE") | regexm(action2, "ADD TO BASE")
	count
	keep application_number product_number exclusivity_code exclusivity_expiration edition
	
	* indicate that these observations are only from comparison data
	* this will allow us to re-check all non-key variables
	gen only_in_base_flag = 0
	gen only_in_comparison_flag = 1
	* save tempfile to append
	tempfile to_append
	save `to_append'
restore	

* load working base data set
use ${temp}base_exclusivity_v3.dta, clear
	append using `to_append'
	isid application_number product_number exclusivity_code exclusivity_expiration edition, mi
	
	replace only_in_comparison_flag = 0 if mi(only_in_comparison_flag)
	
	* save updated base data
	save ${temp}base_exclusivity_v4.dta, replace

* now load comparison data set and check that merge with comaprison works for all observations
* except those that are only in base
use ${temp}comparison_exclusivity1985-2004_update2.dta, clear
	isid application_number product_number exclusivity_code exclusivity_expiration edition, mi
	
	* at this point I noticed that trade_name and active_ingredient are swapped in 1987 edition
	* correct this
	gen trade_name_old = trade_name
	gen active_ingredient_old = active_ingredient
	
	replace trade_name = active_ingredient_old if edition==1987
	replace active_ingredient = trade_name_old  if edition==1987
	drop trade_name_old active_ingredient_old
	
	* rename non-key variables before merge
	foreach var in trade_name active_ingredient duplicate_count {
		rename `var' `var'_C
		}
	
	* merge with base data
	merge 1:1 application_number product_number exclusivity_code exclusivity_expiration edition using ${temp}base_exclusivity_v4.dta
	* merge should never be 1, i.e. all observations should be in base data
	assert _merge != 1
	* merge should be 2 only if indicated that an observation is only in base data
	assert only_in_base_flag==1 if _merge==2
	drop _merge

	mdesc
	tab only*
	assert !mi(only_in_base_flag) & !mi(only_in_comparison_flag)

	* now we want to export a file of mis-matches on non-key variables
	* also keep all observations that are only in base or comparison to check values of non-key variables
	foreach var in trade_name active_ingredient duplicate_count {
		preserve
		
		di "`var'"
		count if (`var' != `var'_C) | (only_in_base_flag==1) | (only_in_comparison_flag==1)
		local check = r(N)
		* keep if base var not equal to comparison var or the observation is flagged
		* as originating from one of the data sets
		keep if (`var' != `var'_C) | (only_in_base_flag==1) | (only_in_comparison_flag==1)
		
		keep application_number product_number exclusivity_code exclusivity_expiration edition `var' `var'_C only_in_base_flag only_in_comparison_flag
		gen variable = "`var'"
		rename (`var' `var'_C) (base comparison)
		
		count
		assert `check' == r(N)
		* save temporary files to append together later
		if "`var'"=="duplicate_count" {
			tostring base comparison, replace
			replace base = "" if base=="."
			replace comparison= "" if comparison=="."
			}
		
		tempfile `var'
		save ``var''
		
		restore	
		}
	
	* use the patent_expiration tempfile
	use `trade_name', clear
	* to this append temporary files for other non-key variable discrepancies
	foreach file in active_ingredient duplicate_count {
		append using ``file''
		}
	
	assert mi(comparison) if only_in_base_flag==1
	assert mi(base) if only_in_comparison_flag==1	
	
	order edition application_number product_number exclusivity_code exclusivity_expiration variable
	sort edition application_number product_number exclusivity_code exclusivity_expiration variable

	* export Excel of mismatches
	isid edition application_number product_number exclusivity_code exclusivity_expiration variable, mi
	export excel using ${discrep}non_key_variable_mismatches_exclusivity.xlsx, firstrow(variables) sheetreplace
	
	* ... manually review and make corrections by hand

	* import corrections
	import excel using ${correct}non_key_variable_mismatches_exclusivity_corrections.xlsx, clear firstrow
	isid edition application_number product_number exclusivity_code exclusivity_expiration variable, mi

	* do some simiple checks of data
	assert !mi(action)
	tostring notes, replace
	replace notes = "" if notes=="."
	assert mi(notes)

	assert inlist(action, "B", "C") if length(action)==1
	list if action!="B" & only_in_base_flag
	list if action!="C" & only_in_comparison_flag
	tab only*

	* drop if action=="B", i.e., base data is correct and doesn't need changed
	drop if action=="B" & mi(notes)
	assert action != "B"
	keep edition application_number product_number exclusivity_code exclusivity_expiration variable comparison action notes
	tab action, mi

	* now we put the data in a form where we can replace the base data with corrected values
	* for those instances in which the comparison data is correct
	rename comparison correction
	replace correction = action if action != "C"
	drop action
	
	reshape wide correction, i(edition application_number product_number exclusivity_code exclusivity_expiration) j(variable) string
	isid edition application_number product_number exclusivity_code exclusivity_expiration, mi

	* save .dta of non-key variable corrections to be merged with base data
	save ${temp}exclusivity_non_key_corrections.dta, replace

	* merge these corrections into base file to make final corrections
	use ${temp}base_exclusivity_v4.dta, clear

	* merge in corrections to non-key variables
	merge 1:1 application_number product_number exclusivity_code exclusivity_expiration edition using ${temp}exclusivity_non_key_corrections.dta
	assert _merge != 2
	drop _merge

	* trim correction values to make sure there are no extra spaces
	* and then replace variable in base data if comparison data is correct
	tab correctionduplicate_count
	destring correctionduplicate_count, replace
	tab correctionduplicate_count
	foreach var in trade_name active_ingredient duplicate_count {
		
		if "`var'" != "duplicate_count" {
			replace correction`var' = trim(itrim(correction`var'))
			}
			
		replace `var' = correction`var' if !mi(correction`var')
		}

	assert mi(notes)
	mdesc
	keep application_number product_number exclusivity_code edition exclusivity_expiration trade_name active_ingredient duplicate_count

	* append 2005-2016 data
	append using ${temp}parsed_exclusivity2005-2016.dta
	isid edition application_number product_number exclusivity_code exclusivity_expiration

	* do a check that active_ingredient and trade_name do not vary within edition-application_number-product_number
	sort edition application_number product_number exclusivity_code exclusivity_expiration
	foreach var in active_ingredient trade_name {
		by edition application_number product_number: assert `var'==`var'[_n-1] if !mi(`var'[_n-1])
		}
	
	* do final check of variable formats
	* check that N/A is where it should be
	assert active_ingredient == "N/A" if edition < 1987
	assert active_ingredient != "N/A" if edition >= 1987
	
	assert trade_name == "N/A" if edition < 1987
	assert trade_name != "N/A" if edition >= 1987

	* check forms of variables
	* application number
	assert regexm(application_number, "^[NA]?[0-9]?[0-9][0-9][0-9][0-9][0-9]$")
	assert (regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1985, 1997)) ///
		| (regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 1998, 2009)) ///
		| (regexm(application_number, "^[NA][0-9][0-9][0-9][0-9][0-9][0-9]$") & inrange(edition, 2010, 2016))
	assert (length(application_number)==5 & inrange(edition, 1985, 1997)) ///
		| (length(application_number)==6 & inrange(edition, 1998, 2009)) ///
		| (length(application_number)==7 & inrange(edition, 2010, 2016))
	* product number
	assert regexm(product_number, "^[0-9][0-9][0-9]$")
	assert length(product_number)==3
	* active_ingredient
	assert !mi(active_ingredient)
	assert !strpos(active_ingredient, "?") // make sure there are no marks for illegible PDFs
	* trade_name
	assert !mi(trade_name)
	assert !strpos(trade_name, "?")
	* patent_expiration
	assert regexm(exclusivity_expiration, "^[A-Z][A-Z][A-Z] [0-9][0-9], [0-9][0-9][0-9][0-9]$")
	gen datetemp = date(exclusivity_expiration, "MDY")
	assert !mi(exclusivity_expiration)
	drop datetemp
	assert length(exclusivity_expiration)==12
	* exclusivity_code
	assert inlist(exclusivity_code, "NC", "NCE", "NCE*", "NDF", "NE", "NP", "NP*", "NPP") ///
		| inlist(exclusivity_code, "NR", "NS", "ODE", "PC", "PED", "RTO", "RTO*", "RTO**") ///\
		| inlist(exclusivity_code, "W", "PP", "GAIN") | regexm(exclusivity_code, "^[DIM]\-[0-9]+$")
	* edition
	assert !mi(edition)
	assert inrange(edition, 1985, 2016)
	assert edition != 1986
	* duplicate_count
	assert !mi(duplicate_count)
	sum duplicate_count
	rename duplicate_count observation_count
	replace observation_count = observation_count + 1
	sum observation_count
	assert inrange(observation_count, 1, 5)
	
	duplicates tag, gen(tag)
	assert tag == 0
	drop tag
	
	foreach var of varlist * {
		assert !mi(`var')
		}
	
	* put variables into final form and construct addional variables
	replace application_number = "0" + application_number if edition <= 1997
	assert regexm(application_number, "^[NA]?[0-9][0-9][0-9][0-9][0-9][0-9]$")
	
	* application_type
	gen application_type = regexs(1) if regexm(application_number, "^([NA]?)[0-9][0-9][0-9][0-9][0-9][0-9]$")
	tab application_type, mi
	assert (mi(application_type) & edition < 2010) | (!mi(application_type) & edition >= 2010)
	replace application_type = "ANDA" if application_type == "A"
	replace application_type = "NDA" if application_type == "N"
	replace application_type = "N/A" if mi(application_type)
	
	replace application_number = substr(application_number, -6, .)
	assert regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9][0-9]$")
	
	* exclusivity_expiration
	rename exclusivity_expiration exclusivity_expiration_old
	gen exclusivity_expiration = date(exclusivity_expiration_old, "MDY")
	assert !mi(exclusivity_expiration)
	format exclusivity_expiration %td
	drop exclusivity_expiration_old
	
	* label variables
	label var edition "orange book edition (year)"
	label var application_type "'NDA' or 'ANDA' or 'N/A'"
	label var application_number "FDA application number"
	label var product_number "FDA product number"
	label var exclusivity_code "FDA exclusivity code"
	label var exclusivity_expiration "exclusivity expiration date"
	label var observation_count "number of time observation occurs in FDA Orange Book"
	label var active_ingredient "drug active ingredient(s)"
	label var trade_name "drug trade name"

	* make some final changes
	* there are some weird patent_expiration dates
	* these are wrong in orange books, not wrong from data entry
	* fix those here
	gen year = year(exclusivity_expiration)
	tab year
	* years look okay
	drop year
		
	* last check of all variable forms
	assert inrange(edition, 1985, 2016)
	assert inlist(application_type, "NDA", "ANDA", "N/A")
	assert regexm(application_number, "^[0-9][0-9][0-9][0-9][0-9][0-9]$")
	assert regexm(product_number, "^[0-9][0-9][0-9]$")
	assert !mi(exclusivity_expiration) & !mi(exclusivity_code)
	assert !mi(active_ingredient)
	assert !mi(trade_name)

	order edition application_type application_number product_number exclusivity_code ///
		exclusivity_expiration active_ingredient trade_name observation_count
	sort edition application_type application_number product_number exclusivity_code exclusivity_expiration
	isid edition application_number product_number exclusivity_code exclusivity_expiration
	
	* ad-hoc change to trade_name
	replace trade_name = "CALCIJEX" if trade_name=="GALCIJEX" & edition==1989 ///
		& application_number=="018874" & product_number=="002"
	
	compress
	save ${dta}FDA_drug_exclusivity.dta, replace

* End constructing exclusivity files

********************************************************************************
********************************************************************************
******************* EXTRA CHECK OF trade_name AND active_ingredient ************
********************************************************************************
********************************************************************************
* Merge the patent files with exclusivity files on edition-application_number-product_number
* Make sure that active ingredient and trade name are identical in each
use ${dta}FDA_drug_exclusivity.dta, clear
	contract edition application_number product_number trade_name active_ingredient
	drop _freq
	isid edition application_number product_number
	tempfile exclusivity
	save `exclusivity'

use ${dta}FDA_drug_patents.dta, clear
	contract edition application_number product_number trade_name active_ingredient
	drop _freq
	isid edition application_number product_number
	rename (trade_name active_ingredient) (trade_name_patent active_ingredient_patent)

	merge 1:1 edition application_number product_number using `exclusivity'
	keep if _merge==3
	
	assert trade_name==trade_name_patent
	assert active_ingredient==active_ingredient_patent
*-------------- END CREATING PATENT AND EXCLUSIVITY TABLES --------------------*

*-------------- NOW CREATE ABBREVIATION LISTS ---------------------------------*

********************************************************************************
* STEP 1: FOR 2005-2016, WE IMPORT AND PARSE ORANGE BOOK PDFs TO CREATE
* ABBREVIATIONS LISTS
********************************************************************************
* set page ranges for each orange book's abbreviation list
clear all
input 	year	start	end
	2005	1006	1037
	2006	991	1022
	2007	1035	1069
	2008	1065	1102
	2009	1119	1160
	2010	1070	1114
	2011	1205	1252
	2012	1248	1298
	2013	1292	1346
	2014	1170	1231
	2015	1214	1280
	2016	1248	1319
end

	* generate edition variable
	gen edition = year - 1980

	forvalues year = 2005/2016 {
	preserve
		keep if year==`year'
		local `year'start = start
		local `year'end = end
		local `year'edition = edition
		di "`year' ``year'start' ``year'end' ``year'edition'"
	restore
	}

* now do pdftotext on each of these orange book abbreviation lists
forvalues year = 2005/2016 {

	di "Executing pdftotext for year `year'"
	! pdftotext -f ``year'start' -l ``year'end' -layout -nopgbrk "${PDF}`year'.pdf" ${txt}abbreviations`year'.txt
	}

* now import these and parse into .dta form
forvalues year = 2005/2016 {
	di "Importing .txt file for `year'"
	import delim using ${txt}abbreviations`year'.txt, clear delim("^")
	assert c(k) == 1
	
	rename v1 var
	
	* remove tabs
	replace var = subinstr(var, char(9), " ", .)
	replace var = upper(trim(itrim(var)))
	drop if mi(var)
	
	* drop non-data rows
	drop if regexm(var, "[0-9][0-9][A-Z][A-Z] EDITION")
	drop if regexm(var, "ADB [0-9]+")
	drop if strpos(var, "PATENT & EXCLUSIVITY") | strpos(var, "PATENT AND EXCLUSIVITY")
	drop if var=="EXCLUSIVITY DOSING SCHEDULE"
	drop if var =="EXCLUSIVITY INDICATION"
	drop if var=="EXCLUSIVITY MISCELLANEOUS"
	drop if var=="PATENT USE"
	
	* find code part of var
	gen potential_code = substr(var, 1, strpos(var, " ")-1)
	assert potential_code == trim(itrim(potential_code))
	gen code = potential_code if inlist(potential_code, "D", "I", "M", "NC", "NCE", "NCE*", "NDF", "NE", "NP") ///
		| inlist(potential_code, "NP*", "NPP", "NR", "ODE", "PC", "PED", "RTO", "RTO*", "RTO**") ///
		| inlist(potential_code, "U", "W", "NS", "GAIN")
	
	replace code = potential_code if regexm(potential_code, "^[UDIM]\-[0-9]+$")
	
	* make year-specific adjustments
	if `year'==2005 {
		* there is a second U-96 code that doesn't appear in other editions
		* it's meaning also doesn't appear in others
		* seems like a one-off error
		* drop it
		drop if var=="U-96 RECOMMENDED IV DOSAGE FOR PEDIATRIC SURGICAL PATIENTS (1 MONTH TO 12 YEARS OF AGE) IS" ///
			| var=="A SINGLE 0.1MG/KG DOSE FOR PATIENTS WEIGHING 40KG OR LESS, OR A SINGLE 4MG DOSE FOR" ///
			| var=="PATIENTS WEIGHING MORE THAN 40KG"
		}
	if inrange(`year', 2006, 2013) {
		* the entry "PED PEDIATRIC EXCLUSIVITY"  is not a code
		* replace the code part to null value
		replace code="" if var=="PED PATIENTS (1-17) NOT AS FIRST CHOICE"
		}
		
	* create id variable so we can sort
	* we need to make sure we can sort back to current order in order to correctly conccatenate descriptions
	gen id = _n
	* see if any codes are repeated (they shouldn't be)
	bysort code: gen N = _N
	assert N==1 if !mi(code) // good
	* sort back to original order
	sort id
	drop id N
	
	* check that numbers go in order
	gen number = regexs(1) if regexm(code, "^[UDIM]\-([0-9]+)$")
	destring number, replace
	replace number = number[_n-1] if mi(number)
	assert (number >= number[_n-1]) | (number == 1)
	drop number potential_code
	* assign code to all following missing codes
	replace code = code[_n-1] if mi(code)
	assert !mi(code)
	assert !mi(var)
	
	* create the meaning field
	rename var meaning
	* strip code from meaning field
	replace meaning = substr(meaning, strpos(meaning, " ")+1, .) if substr(meaning, 1, length(code))==code
	replace meaning = trim(itrim(meaning))
	
	* concatenate together meaning fields that span more than one line
	* gen id variable to make sure observations don't change order
	gen id = _n
	bysort code (id): gen N = _N
	sum N
	local max = r(max)
	
	forvalues i = 2/`max' {
		bysort code (id): replace meaning = meaning + " " + meaning[`i'] if (_n==1 & !mi(meaning[`i']))
		}
	bysort code (id): drop if _n != 1
	assert meaning == upper(trim(itrim(meaning)))
	* change "- " to "-"
	* sometimes a "-" appears at end of sentence and is forming a compound word
	* (not connecting a non-compound word)
	* we want to get rid of extra space
	replace meaning = subinstr(meaning, "- ", "-", .)
	
	isid code
	
	* check again that numbers go in order and are not missing
	gen subcode = regexm(code, "^[UDIM]\-[0-9]+$")
	gen letter = regexs(1) if regexm(code, "^([UDIM])\-[0-9]+$")
	gen number = regexs(1) if regexm(code, "^[UDIM]\-([0-9]+)$")
	destring number, replace
	sort subcode letter number

	bysort subcode letter (number): gen sequence_error = (number != number[_n-1] + 1) & !mi(number[_n-1])
	* inspect any seeming errors by references to Orange Book
	count if sequence_error==1
	assert r(N)==1 if inlist(`year', 2005, 2010, 2011, 2012, 2013, 2014, 2015)
	assert r(N)==0 if inlist(`year', 2006, 2007, 2008, 2009)
	list if sequence_error==1 | sequence_error[_n-1]==1 | sequence_error[_n+1]==1
	* For year 2005, referring to OB shows that U-619 is actually missing
	* For year 2010-2015 referring to OB shows that I-609 is actually missing from PDF
	
	drop sequence_error id N subcode letter number
	
	order code meaning
	rename meaning code_description
	compress
	
	************************************************************************
	* SPECIAL CASE: ADD "GAIN" EXCLUSIVITY FOR 2015 ORANGE BOOK
	* This does not appear in abbreviation lists but does appear in data tables
	************************************************************************
	if inlist(`year', 2015) {
		local newobs = _N+1
		set obs `newobs'
		replace code = "GAIN" if mi(code)
		replace code_description = "GENERATING ANTIBIOTIC INCENTIVES NOW (CONSTRUCTED, NOT IN RAW LIST)" if mi(code_description)
		}
	
	* save file
	save ${temp}abbreviations`year'.dta, replace
	}

********************************************************************************
* STEP 2: IMPORT ROWS TO ADD
********************************************************************************
import excel using ${correct}abbreviation_rows_to_add.xlsx, clear firstrow
	tempfile to_add
	save `to_add'

********************************************************************************
* STEP 3: FOR 1985-2004, WE IMPORT DATA HAND-ENTERED BY DIGITAL DATA DIVIDE
********************************************************************************
forvalues year = 1985/2004 {
	di "Importing abbreviations for `year'"
	
	* no data for 1986
	if `year'==1986 {
		continue
		}
		
	* import raw data s entered by DDD
	import excel using ${rawabbs}ob-exclusivity-abbreviations`year'.xlsx, clear firstrow
	
	* delete extra variable in 2001
	if inlist(`year', 2001, 2002, 2004) {
		drop C
		}
	
	ds
	assert r(varlist) == "abbreviation description"
	rename (abbreviation description) (code code_description)
	
	* trim variables
	foreach var in code code_description {
		replace `var' = upper(trim(itrim(`var')))
		}
	
	* drop missings and duplicates
	drop if mi(code) & mi(code_description)
	duplicates drop
	
	gen edition = `year'
	
	tempfile `year'
	save ``year''
	}
	
use `1985', clear
forvalues year = 1987/2004 {
	append using ``year''
	}

	* add rows
	append using `to_add'

	* deal with descriptions broken across multiple lines
	count if mi(code)
	assert r(N)==8
	list if mi(code) | mi(code[_n+1])
	
	gen n = _n
	bysort edition (n): replace code_description = code_description + " " + code_description[_n+1] ///
		if mi(code[_n+1])
	list if mi(code) | mi(code[_n+1])
	drop if mi(code)
	drop n
	
	* check that edition-code is key ID
	isid edition code
	
	* fix code formats
	replace code = subinstr(code, " ", "", .)
	* check that does all take on correct format
	gen error = !( inlist(code, "D", "I", "M", "NC", "NCE", "NDF", "NE", "NP") | ///
		inlist(code, "NP*", "NPP", "NR", "NS", "ODE", "PED", "PC", "RTO") | ///
		inlist(code, "U", "W", "PP") | ///
		regexm(code, "^[DUIM]\-[0-9]+$") )
	list code code_description edition if error
	tab code if error
	
	* regular expression fixes
	* first, change "1-" to "I-"
	replace code = "I" + substr(code, 2, .) if substr(code, 1, 2)=="1-"
	replace error = !( inlist(code, "D", "I", "M", "NC", "NCE", "NDF", "NE", "NP") | ///
		inlist(code, "NP*", "NPP", "NR", "NS", "ODE", "PED", "PC", "RTO") | ///
		inlist(code, "U", "W", "PP") | ///
		regexm(code, "^[DUIM]\-[0-9]+$") )
	list edition code code_description if error
	
	* ad-hoc changes
	replace code = "U-11" if code=="U-LL"
	replace code = "I-174" if code=="I-I74"
	replace code = "I-101" if code=="I-1O1" 
	replace code = "U-1" if code=="U-L"
	replace code = "U-13" if code=="U-L3"
	replace code = "U-136" if code=="II-136"
	replace code = "U-157" if code=="U--157"
	replace code = "U-I99" if code=="U-199"
	replace code = "U-314" if code=="U-3I4"
	replace code = "U-351" if code=="U-35I"
	replace code = "U-18" if code=="U-L8"
	replace code = "U-162" if code=="U-I62"
	replace code = "U-168" if code=="U-I68"
	replace code = "U-175" if code=="U-I75"
	replace code = "U-425" if code=="0-425"
	replace code = "U-199" if code=="U-I99"
	
	replace error = !( inlist(code, "D", "I", "M", "NC", "NCE", "NDF", "NE", "NP") | ///
		inlist(code, "NP*", "NPP", "NR", "NS", "ODE", "PED", "PC", "RTO") | ///
		inlist(code, "U", "W", "PP") | ///
		regexm(code, "^[DUIM]\-[0-9]+$") )
	assert !error
	isid edition code
	
	* check numbers entered for each type of code
	gen letter = regexs(1) if regexm(code, "^([DUIM])\-([0-9]+)$")
	gen number = regexs(2) if regexm(code, "^([DUIM])\-([0-9]+)$")
	destring number, replace
	
	* do some sanity checks
	sort edition letter number
	by edition letter: assert number==1 if (_n==1 & !mi(letter))
	by edition letter: assert (number == number[_n-1]+1) if !mi(letter) & !mi(number[_n-1])
	by edition letter: assert _N == number[_N] if !mi(letter)
	
	drop letter number error
	isid edition code
	
	* append 2005-2016 abbreviations
	forvalues year = 2005/2016 {
		append using ${temp}abbreviations`year'.dta
		replace edition = `year' if mi(edition)
		}
	isid edition code
		
	replace code_description = trim(itrim(code_description))
	
	label var edition "Orange Book edition"
	* save exclusivity codes and use codes separately
	* first save use codes
preserve
	keep if regexm(code, "^U\-[0-9]+$") | code=="U"
	rename code use_code
	rename code_description use_code_desc
	
	label var use_code "Patent Use Code"
	label var use_code_desc "Patent Use Code meaning"
	
	compress
	isid use_code edition
	compress
	save ${dta}FDA_patent_use_codes.dta, replace
restore	
	
	* now save exclusivity codes
preserve
	keep if !(regexm(code, "^U\-[0-9]+$") | code=="U")
	rename code exclusivity_code
	rename code_description exclusivity_code_desc

	label var exclusivity_code "FDA exclusivity code"
	label var exclusivity_code_desc "FDA exclusivity code meaning"

	compress
	isid exclusivity_code edition
	save ${dta}FDA_drug_exclusivity_codes.dta, replace
restore	
	
	* Now merge with Orange Book tables as check
	* First, patents data
	use ${dta}FDA_drug_patents.dta, clear
	drop if mi(use_code) | use_code=="N/A"
	count
	merge m:1 edition use_code using ${dta}FDA_patent_use_codes.dta
	assert _merge != 1
	* All use codes in Orange Book have a counterpart in codes list
	
	* Second, exclusivity data
	use ${dta}FDA_drug_exclusivity.dta, clear
	assert !mi(exclusivity_code)
	count
	merge m:1 edition exclusivity_code using ${dta}FDA_drug_exclusivity_codes.dta
	list if _merge==1
	* No counterpart for I-55 in 1990
	* This is just how it is in 1990 Orange Book
*-------------- END CREATING ABBREVIATION LISTS -------------------------------*

*------------------------------------------------------------------------------*
* You can enter code to remove, temp, txt, and excel discrepancie directories here
*------------------------------------------------------------------------------*
! rm -r ${working}4_clean_tables_stata/temp/
! rm -r ${working}4_clean_tables_stata/txt/
! rm -r ${working}4_clean_tables_stata/exported_discrepancies_excel/

* End
