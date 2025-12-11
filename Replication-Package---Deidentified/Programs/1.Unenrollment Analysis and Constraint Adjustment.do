********************************************************************************
********************************************************************************
************** Unenrollment Analysis and Constraint Adjustments ****************
********************************************************************************
********************************************************************************

// SET DIRECTORY

global statapath "Insert Directory"
global data "$statapath/Data"
global panel "$statapath/Data/Panel"
global randomization "$statapath/Randomization"
global results "$statapath/Results"
global fortisdata "$statapath/Data/Fortis Data"


********************************************************************************
********************************************************************************
** Investigate if there are missing EVs from the charge data and why 
********************************************************************************
********************************************************************************

****
** Were all EVs that passed all eligibility criteria included?
****

use "$panel/panel_hourly_analysis.dta" , clear 

** Merge in Group Assignments (check there is no _m==2)

merge m:1 vehicle_id using "$data/treatment group assignment.dta"


****
** Check that unenrolled EVs are in the data up to their final unenrollment date 
****

use "$panel/panel_hourly_analysis.dta" , clear 

** Merge in Group Assignments 
merge m:1 vehicle_id using "$data/treatment group assignment.dta"

rename _m Assigned_Missing 

** Merge in Vehicle Characteristics - including unenrollment date 

merge m:1 vehicle_id using "$data/vehicle_data_analysis.dta"

rename _m Missing_Flag 

sort vehicle_id time

** Calculate the difference between the charge date and unenrollment date
** Focus on EVs enrolled into a group 

keep if unenroll_date != .  

keep if group != ""

gen date_diff = unenroll_date - date 

** Note: No negative values - unenrolled EV data stops at unenroll_date 
sum date_diff, detail 


****
** Understand Unenrollment date and evaluate if date differs across groups by the min_time charged 
****

use "$panel/panel_hourly_analysis.dta" , clear 

** Flag the first time period where a car shows up in the data 
** This includes both away and home charging 

bysort vehicle_id: egen double min_time = min(time) 

format min_time %tc 

** Merge in Group Assignments 
merge m:1 vehicle_id using "$data/treatment group assignment.dta"

keep if _m == 3 

drop _m 

** Drop group C8 - non-controllable EVs 

drop if treatment == "C8"

** Merge in Vehicle Characteristics - including unenrollment date 

merge m:1 vehicle_id using "$data/vehicle_data_analysis.dta"

keep if _m == 3 

drop _m 

sort vehicle_id time

** Focus on EVs that unenrolled 

keep if unenroll_date != .  

keep if group != ""

collapse (firstnm) group (min) min_time unenroll_date, by(vehicle_id)

keep if unenroll_date <= td(13Dec2023)

tab group 

** Understand how long the EVs that unenrolled were on the App 

sort min_time

** Early

count if min_time < tc(01Jan2023 00:00:00)

** Late

count if min_time > tc(01Apr2023 00:00:00)

** Mid 

count if min_time >= tc(01Jan2023 00:00:00) & min_time < tc(01Apr2023 00:00:00)



********************************************************************************
********************************************************************************
** Create an Adjusted Transformer Group Limits data file 
** Method: Adjust Constraints down by unerolled EVs 
** Alternative Method below: Subtract off passive loads to define the new constraint 
********************************************************************************
********************************************************************************

** Start by loading group - limit data 

import delimited using "$randomization/group limits all vars_test.csv", clear 

replace datetime = datetime + " 00:00:00" if hour == 0 

gen double time = clock(datetime, "YMDhms" )

format time %tc 

sort treatment time 

** drop duplicates (time change)

duplicates drop treatment time, force 

gen date = dofc(time)

format date %td 

save "$data/group limits.dta", replace 


** Create a transformer-by-day specific count of EVs 
** Use our original treatment assignment 
** TOU and Managed - 10 EVs each 
** Control - 10 EVs for C1 - C6, C7 had 2 and C8 had 14

use "$data/treatment group assignment.dta", clear 

merge 1:1 vehicle_id using "$data/vehicle_data_analysis.dta"

drop if _m == 2 

drop _m 

keep vehicle_id home_id treatment group transformer unenroll_date unenrolled_reason

sort treatment 

** For Vehicle - merge with the EV daily template file 
** Only keep EVs that are still enrolled in the program 
** Count of enrolled EVs for each day and treatment group 

merge 1:m vehicle_id using "$data/Daily_Template_Analysis.dta"

drop if _m ==2 

drop _m 

sort treatment vehicle_id date 

** Drop EVs that unenroll from the program on and after the day they have unenrolled 

drop if unenroll_date != . & unenroll_date <= date 

sort treatment date 



** Now deal with the fact that we have a subset of EVs that entered after April 1, 2023 
** Important to get the count of EVs correct 
** Create a min_date variable 

preserve 

use "$panel/panel_hourly_analysis.dta" , clear 

bysort vehicle_id: egen double min_time = min(time)

format min_time %tc 

gen date_min_time = dofc(min_time)

format date_min_time %td 

collapse (max) date_min_time, by(vehicle_id)

tempfile min_date
save `min_date'

restore 
 
merge m:1 vehicle_id using `min_date'

drop if _m ==2 

drop _m 

sort vehicle_id date

drop if date < date_min_time



** Collapse to the treatment group - date level - counting the number of EVs that remain 

gen EV_Count = 1 

collapse (sum) EV_Count, by(treatment date)

merge 1:m treatment date using "$data/group limits.dta"

** _m == 2 are observations beyond June 30, 2024 or C7 where both EVs dropped out of the program (dropped because this occurred after Phase 3 survey)
drop if date == td(01jul2024)

replace EV_Count = 0 if _m == 2 

drop _m 

sort treatment time 

****
** Create an adjusted constraint 
****

** Underlying HH load per EV 
gen double loadtransgrp_perEV = loadtransgrp10/10 

** Create an adjusted underlying load by the number of EVs enrolled 
gen double loadtransgrp_adj = EV_Count*loadtransgrp_perEV

** Adjust Constraint (which is based on a 10 EV transformer) - multiple the number of EVs by the constraint per EV 

gen double constraint_adj = EV_Count*(constraint/10)

** Adjusted EV Load Limit 
gen double evloadlimit_adj = constraint_adj - loadtransgrp_adj

drop loadtransgrp_perEV

save "$data/group limits_Adjusted.dta", replace 












