********************************************************************************
********************************************************************************
************* Investigate Phase 3 Results **************************************
********************************************************************************
********************************************************************************

// SET DIRECTORY

global statapath "Insert Directory"
global data "$statapath/Data"
global panel "$statapath/Data/Panel"
global results "$statapath/Results"
global fortisdata "$statapath/Data/Fortis Data"

********************************************************************************
** Merge together Phase 3 matching with vehicle-level data file and Phase 3 randomization 
********************************************************************************

** Construct a data file that matches profile ids with home ids 
** Use Vehicle owner list from Phase 3 randomization 

import excel "$fortisdata/Fortis Data Transfer - 2023_11_29 - UofC.xlsx", clear first sheet("Vehicle Owner Data")

keep profile_id home_id 

duplicates drop 

tempfile profile_home_matching

save `profile_home_matching'

** Construct a data file that maps home_id to the Phase 3 offer 

use "$data/Phase3_Incentive_vehicle_ids.dta", clear 

keep home_id Incentive 

duplicates drop 

tempfile Phase3_home_profile_matching

save `Phase3_home_profile_matching'



***************
** Match profile_ids with home_ids and vehicle_id - $0 Offer 
** Then merge with Phase 3 randomization file 
***************

use "$fortisdata/Phase 3 Survey Data/$0_V1_Match.dta" , clear 

rename EmailAddressprofile_id profile_id

drop if profile_id == "DB_MISSING_1"

destring profile_id, replace 

merge 1:m profile_id using `profile_home_matching'

drop if _m == 2 

drop _m 

** 1 home has two profiles in Optiwatt's data - both accepted - drop duplicate 
** Entire HH accepted 

drop if profile_id == 183234

** 1 EV home_id changed in Optiwatt's November 2023 data from 119389 to 68352 in our Phase 3 randomization file 

replace home_id = 68352 if home_id == 119389

** Merge with the Phase 3 randomization file 

merge 1:1 home_id using `Phase3_home_profile_matching'

keep if _m == 3 

drop _m 

tempfile Phase3_0_Match

save `Phase3_0_Match'

 

***************
** Match profile_ids with home_ids and vehicle_id - $75 Offer 
** Then merge with Phase 3 randomization file 
***************

use "$fortisdata/Phase 3 Survey Data/$75_V1_Match.dta" , clear 

rename EmailAddressprofile_id profile_id

drop if profile_id == . 

merge 1:m profile_id using `profile_home_matching'

drop if _m == 2 

drop _m 

** 1 home has two profiles in Optiwatt's data - both accepted - drop duplicate 
** Entire HH accepted 

drop if profile_id == 179958

** Merge with the Phase 3 randomization file 

merge 1:1 home_id using `Phase3_home_profile_matching'

keep if _m == 3 

drop _m 

tempfile Phase3_75_Match

save `Phase3_75_Match'


***************
** Match profile_ids with home_ids and vehicle_id - $150 Offer 
** Then merge with Phase 3 randomization file 
***************

use "$fortisdata/Phase 3 Survey Data/$150_V1_Match.dta" , clear 

rename EmailAddressprofile_id profile_id

merge 1:m profile_id using `profile_home_matching'

drop if _m == 2 

drop _m 

** Merge with the Phase 3 randomization file 

merge 1:1 home_id using `Phase3_home_profile_matching'

keep if _m == 3 

drop _m 


tempfile Phase3_150_Match

save `Phase3_150_Match'


********************************************************************************
** Final Phase 3 vehicle data file - understand unenrollments 
********************************************************************************

// Generate Data flagging EVs that have unenrolled from the program 
import excel "$fortisdata/Fortis - Data Transfer 2024-05-21 UCalgary.xlsx", sheet("Vehicle Owner Data") firstrow clear

split unenrolled_at, p("-" " " ":")

destring unenrolled_at1, gen(unenroll_year)
destring unenrolled_at2, gen(unenroll_month)
destring unenrolled_at3, gen(unenroll_day)

keep vehicle_id profile_id home_id unenroll_year unenroll_month unenroll_day deleted_vehicle_reason unenrolled_reason

keep if unenroll_year != . 

gen unenroll_date = mdy(unenroll_month, unenroll_day, unenroll_year)

format unenroll_date %td 

keep vehicle_id profile_id home_id unenroll_date deleted_vehicle_reason unenrolled_reason

tab unenroll_date

sort unenroll_date

destring vehicle_id, replace  

destring profile_id , replace  

destring home_id, replace  

tab unenrolled_reason

tempfile Unenrollment_Phase3

save `Unenrollment_Phase3'

********************************************************************************
** Merge together matched files 
********************************************************************************

** Bringing together matched results 

use `Phase3_0_Match'

append using `Phase3_75_Match'

append using `Phase3_150_Match'

** Merge in with full list of vehicles offered incentives in Phase 3 

merge 1:m home_id using "$data/Phase3_Incentive_vehicle_ids.dta"

sort _merge home_id

gen completed_matched = 0 
replace completed_matched = 1 if _m == 3 

drop _m 

** Merge in Phase 2 group assignments 

merge 1:1 vehicle_id using "$data/Phase3_EligibleEVList.dta"

drop _m 

** Merge in Phase 3 unenrolled EVs

merge 1:1 vehicle_id using `Unenrollment_Phase3'

drop _m 

** Focus on Control EVs at the household-level that are matched 

keep if group == "C" & completed_matched == 1 

duplicates drop home_id, force 

** Count of Control homes that responded 

count 

** Count of Control homes that said yes to enrolling 

tab accepted_offer

** Count of Control homes that did not unenroll after 6 months 

count if accepted_offer == 1 & unenrolled_reason == ""

** Count of Control homes that unenrolled after 6 months 

count if accepted_offer == 1 & unenrolled_reason != ""


