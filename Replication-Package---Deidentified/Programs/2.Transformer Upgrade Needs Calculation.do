********************************************************************************
********************************************************************************
*********** Simple Calculation of Infrastructure Upgrade Needs  ****************
********************************************************************************
********************************************************************************

// SET DIRECTORY

global statapath "Insert Directory"
global data "$statapath/Data"
global panel "$statapath/Data/Panel"
global results "$statapath/Results"
global fortisdata "$statapath/Data/Fortis Data"


********************************************************************************
** Construct Panel to calculate hourly violations at the transformer-level
********************************************************************************

** Upload hourly charge data 

use "$panel/panel_hourly_analysis.dta" , clear 

** Merge in Group Assignments 

merge m:1 vehicle_id using "$data/treatment group assignment.dta"

** _m == 1 are EVs that didnt make it into our trial, but have some charging data 
** Sizable numbers are coming from the fact that we have a number of unverified EVs that would have been eligible otherwise 

drop if _m == 1

drop _m 

sort vehicle_id date hour 

*******
** Merge in hourly template data - fill in non-charging hours with zeros  
*******

** Flag the first time period where a car shows up in the data 
** This includes both away and home charging 

bysort vehicle_id: egen double min_time = min(time) 

format min_time %tc 

** Merge in hourly template file to fill in zero values - where no charging occurs 

merge m:1 vehicle_id time using "$data/Hourly_Template_Analysis.dta"

** _m == 1 are charging sessions prior to 2023 (dropped below)

** Identify EVs that are in the interval data and/or template file (created for the full list of EVs), but did not make it into our randomization

bysort vehicle_id: egen transformer_max = max(transformer)

drop if transformer_max == . 

drop transformer_max

sort vehicle_id time 

** Drop time before April 1, 2023 - earliest start of pre-treatment period in our analysis 

drop if time < tc(01Apr2023 00:00:00)

** Some EVs didn't make it into the data until after April 1, 2023  
** Drop if time (from template file) < min_time of an EV 

bysort vehicle_id: egen double min_time2 = min(min_time)

format min_time2 %tc 

replace min_time = min_time2 

drop min_time2 

drop if time < min_time 

** Drop if time > 13dec2023 23:00:00 (Phase 3 surveys sent next day)

drop if time > tc(13dec2023 23:00:00) 

sort vehicle_id time 

** Understand merge status after data outside of the range is dropped 
** _ == 2 are hours where the EV isn't charging 

tab _m 

drop _m 

** Check that there is positive charge in at least one hour for each vehicle 

bysort vehicle_id: egen test = sum(kWh_added_hour)

sum test, detail 

drop test 

** Replace missing hours with zero charging 

replace kWh_added_hour = 0 if kWh_added_hour == . 

replace range_added_hour = 0 if range_added_hour ==. 

replace batterylvl_added_hour = 0 if batterylvl_added_hour == . 

** Fill in group assignments and vehicle characteristics (missing for non-charging hours)
** Merge in vehicle - list 

drop tesla_powerwall tesla_solar car_year est_battery_range_miles make model

merge m:1 vehicle_id using "$data/vehicle_data_analysis.dta"

drop if _m == 2

drop _m 

rename year car_year

** Drop assignments and re-merge to fill across hours 
** First, merge in the assignments to eligible EVs to flag which ones were initially eligibile and assigned
** Second, merge in the complete list of assignments (that includes multi-EV homes with initially ineligible vehicles)

drop treatment group transformer 

merge m:1 vehicle_id using "$data/treatment group assignment.dta"

drop _m 

** Verify that everyone has a treatment assignment 

count if treatment == ""

** Clean up data 

drop hour 

order vehicle_id date time hour_start 

sort  vehicle_id date hour_start 

*******
** Merge in transformer limits file - necessary to understand the "room" available on each transformer 
*******

** Merge by treatment group and time 

merge m:1 treatment time using "$data/group limits_Adjusted.dta"

** _m == 2 are hours that are either before our sample or after the data ends 

drop if _m == 2 

drop _m  datetime hour


sort vehicle_id time

*******
** Focusing on at-home charging only 
** replace charge KWhs away with zero 
*******

gen kWh_added_hour_home = 0 
replace kWh_added_hour_home = kWh_added_hour if location == 0 


*******
** Drop observations for EVs that unenrolled (in the data template file)
** Otherwise, we are assigning zero charge to these EVs when they unenrolled 
*******

drop if date >= unenroll_date & unenroll_date != . 

** Clean up data set 

order vehicle_id treatment group transformer date time hour_start kWh_added_hour kWh_added_hour_home

rename EV_Count EV_Count_on

** Drop C8 control group - non-controllable EVs 

drop if treatment == "C8"

*******
** Remove days with "DR Events"
*******

drop if date == td(11aug2023)
drop if date == td(12aug2023)
drop if date == td(28aug2023)
drop if date == td(22nov2023)

********************************************************************************
********************************************************************************
** Calculate Transformer Upgrade Needs - Using Observed Groups 
********************************************************************************
********************************************************************************

preserve 

*******
** Collapse to the transformer-day-hour level, summing up the amount charged at home 
*******

collapse (max) transformer evloadlimit  evloadlimit_adj  EV_Count_on   constraint loadtransgrp10 loadtransgrp_adj (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment date hour_start)


** Construct Violation Kwhs Variable - Include measure adjusted by attrition 

gen Transformer_Space = evloadlimit - kWh_added_hour_home

gen Transformer_Space_adj = evloadlimit_adj - kWh_added_hour_home

gen Violation_KWhs = 0 
replace Violation_KWhs = -1*Transformer_Space if Transformer_Space < 0 

gen Violation_KWhs_adj = 0 
replace Violation_KWhs_adj = -1*Transformer_Space_adj if Transformer_Space_adj < 0 


** Post-Treatment Flag - used below 

gen Post_Treat = 0 
replace Post_Treat = 1 if date >= td(05Jul2023) 


********************************************************************************
** Calculate the capacity level required for Control, TOU, and Managed to meet maximum demand 
** Calculate the relative difference between TOU and Control versus Managed and Control 
********************************************************************************

** For each transformer and hour, calculate the summation of at-home charging and underlying representative load 
** Use adjusted load to account for attrition 

gen Load_plus_HomeEVCharging_adj = (loadtransgrp_adj + kWh_added_hour_home)/EV_Count_on

** Find the maximum draw on the transformer in kWhs for each transformer, pre- and post-treatment 
collapse (firstnm) group (max) Load_plus_HomeEVCharging_adj, by(treatment Post_Treat)

** Find the average upgrade need for each group, pre- and post-treatment 

collapse (mean) Load_plus_HomeEVCharging_adj, by(group Post_Treat)

*************
** Calculate the percentage change in capacity required to meet the maximum draw on the transformer 
*************

sum Load_plus_HomeEVCharging_adj if group == "C" & Post_Treat == 1 

scalar control_max = r(mean)

sum Load_plus_HomeEVCharging_adj if group == "T" & Post_Treat == 1 

scalar TOU_max = r(mean)

sum Load_plus_HomeEVCharging_adj if group == "M" & Post_Treat == 1 

scalar Managed_max = r(mean)

** Percentage Change TOU relative to control 

scalar TOU_Control_Max = 100*(TOU_max - control_max)/control_max

display TOU_Control_Max

** Percentage Change Managed relative to control 

scalar Managed_Control_Max = 100*(Managed_max - control_max)/control_max

display Managed_Control_Max

** Percentage Change Managed relative to TOU 

scalar Managed_TOU_Max = 100*(Managed_max - TOU_max)/TOU_max

display Managed_TOU_Max

restore 

********************************************************************************
********************************************************************************
** Calculate Transformer Upgrade Needs - Randomly grouping Control and TOU with different number of EVs 
********************************************************************************
********************************************************************************

** Keep only TOU and Control EVs 

drop if group == "M"

** Save panel data (to be pulled upon below)

tempfile panel_data_T_C
save `panel_data_T_C'

*****************
** 2 EV groupings 
*****************

** Create an initially empty data set to store the results of the loop 

clear 
tempfile building
save `building', emptyok

forvalues i = 1(1)100{

** Load the panel data file 

use `panel_data_T_C', clear 

** Randomly create different groupings, and calculate the required transformer capacity to meet load 
** Create a temp file with new groupings 

preserve 

keep vehicle_id group 

duplicates drop 

sort group vehicle_id

set seed `i'

generate u1 = runiform()

sort group u1 

xtile transformer_new_C = u1 if group == "C" , nq(31)
xtile transformer_new_T = u1 if group == "T" , nq(35)

gen transformer_new = transformer_new_C if group == "C"
replace transformer_new = transformer_new_T if group == "T" 

drop transformer_new_C transformer_new_T

tempfile Transformer_Allocation_2
save `Transformer_Allocation_2'

restore 

** Merge in the random EV allocation into the TOU and Control panel 

merge m:1 vehicle_id using `Transformer_Allocation_2'

drop _m 

egen treatment_new = concat(group transformer_new)

*******
** Collapse to the transformer-day-hour level, summing up the amount charged at home 
** Using new 2-EV transformers 
*******

collapse (max) transformer_new loadtransgrp10  (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment_new date hour_start)

** Post-Treatment Flag - used below 

gen Post_Treat = 0 
replace Post_Treat = 1 if date >= td(05Jul2023) 

********************************************************************************
** Calculate the capacity level required for Control, TOU, and Managed to meet maximum demand 
** Calculate the relative difference between TOU and Control versus Managed and Control 
********************************************************************************

** For each transformer and hour, calculate the summation of at-home charging and underlying representative load (which is based on 10 homes)
** Adjust load by dividing by 10 and multiplying by 2 EVs 

gen Load_plus_HomeEVCharging = 2*(loadtransgrp10/10) + kWh_added_hour_home 

** Find the maximum draw on the transformer in kWhs for each transformer, pre- and post-treatment 
collapse (firstnm) group (max) Load_plus_HomeEVCharging, by(treatment_new Post_Treat)

** Find the average upgrade need for each group, pre- and post-treatment 

collapse (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

gen Number_EVs = 2 

gen iteration = `i'

** Store results 

append using `building'

save `building', replace


}

** Take the average of the 100 draws 

collapse (max) Number_EVs (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

save "$data/EV_MaxDemand_Simulation_Count2.dta", replace 


*****************
** 3 EV groupings 
*****************

** Create an initially empty data set to store the results of the loop 

clear 
tempfile building
save `building', emptyok

forvalues i = 1(1)100{

** Load the panel data file 

use `panel_data_T_C', clear 

** Randomly create different groupings, and calculate the required transformer capacity to meet load 
** Create a temp file with new groupings 

preserve 

keep vehicle_id group 

duplicates drop 

sort group vehicle_id

set seed `i'

generate u1 = runiform()

sort group u1 

** Need groups of 3 ==> must drop 2 C and 1 T (drop the final in the ranking)

gen ones = 1 

bysort group (u1): gen sum_ones = sum(ones)

drop if sum_ones > 60 & group == "C"
drop if sum_ones > 69 & group == "T"

drop ones sum_ones

xtile transformer_new_C = u1 if group == "C" , nq(20)
xtile transformer_new_T = u1 if group == "T" , nq(23)

gen transformer_new = transformer_new_C if group == "C"
replace transformer_new = transformer_new_T if group == "T" 

drop transformer_new_C transformer_new_T

tempfile Transformer_Allocation_3
save `Transformer_Allocation_3'

restore 

** Merge in the random EV allocation into the TOU and Control panel 

merge m:1 vehicle_id using `Transformer_Allocation_3'

drop if _m == 1 

drop _m 

egen treatment_new = concat(group transformer_new)

*******
** Collapse to the transformer-day-hour level, summing up the amount charged at home 
** Using new 3-EV transformers 
*******

collapse (max) transformer_new loadtransgrp10  (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment_new date hour_start)

** Post-Treatment Flag - used below 

gen Post_Treat = 0 
replace Post_Treat = 1 if date >= td(05Jul2023) 

********************************************************************************
** Calculate the capacity level required for Control, TOU, and Managed to meet maximum demand 
** Calculate the relative difference between TOU and Control versus Managed and Control 
********************************************************************************

** For each transformer and hour, calculate the summation of at-home charging and underlying representative load (which is based on 10 homes)
** Adjust load by dividing by 10 and multiplying by 3 EVs 

gen Load_plus_HomeEVCharging = 3*(loadtransgrp10/10) + kWh_added_hour_home 

** Find the maximum draw on the transformer in kWhs for each transformer, pre- and post-treatment 
collapse (firstnm) group (max) Load_plus_HomeEVCharging, by(treatment_new Post_Treat)

** Find the average upgrade need for each group, pre- and post-treatment 

collapse (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

gen Number_EVs = 3 

gen iteration = `i'

** Store results 

append using `building'

save `building', replace


}

** Take the average of the 100 draws 

collapse (max) Number_EVs (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

save "$data/EV_MaxDemand_Simulation_Count3.dta", replace 

*****************
** 4 EV groupings 
*****************

** Create an initially empty data set to store the results of the loop 

clear 
tempfile building
save `building', emptyok

forvalues i = 1(1)100{

** Load the panel data file 

use `panel_data_T_C', clear 

** Randomly create different groupings, and calculate the required transformer capacity to meet load 
** Create a temp file with new groupings 

preserve 

keep vehicle_id group 

duplicates drop 

sort group vehicle_id

set seed `i'

generate u1 = runiform()

sort group u1 

** Need groups of 4 ==> must drop 2 C and 2 T (drop the final in the ranking)

gen ones = 1 

bysort group (u1): gen sum_ones = sum(ones)

drop if sum_ones > 60 & group == "C"
drop if sum_ones > 68 & group == "T"

drop ones sum_ones

xtile transformer_new_C = u1 if group == "C" , nq(15)
xtile transformer_new_T = u1 if group == "T" , nq(17)

gen transformer_new = transformer_new_C if group == "C"
replace transformer_new = transformer_new_T if group == "T" 

drop transformer_new_C transformer_new_T

tempfile Transformer_Allocation_4
save `Transformer_Allocation_4'

restore 

** Merge in the random EV allocation into the TOU and Control panel 

merge m:1 vehicle_id using `Transformer_Allocation_4'

drop if _m == 1 

drop _m 

egen treatment_new = concat(group transformer_new)

*******
** Collapse to the transformer-day-hour level, summing up the amount charged at home 
** Using new 4-EV transformers 
*******

collapse (max) transformer_new loadtransgrp10  (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment_new date hour_start)

** Post-Treatment Flag - used below 

gen Post_Treat = 0 
replace Post_Treat = 1 if date >= td(05Jul2023) 

********************************************************************************
** Calculate the capacity level required for Control, TOU, and Managed to meet maximum demand 
** Calculate the relative difference between TOU and Control versus Managed and Control 
********************************************************************************

** For each transformer and hour, calculate the summation of at-home charging and underlying representative load (which is based on 10 homes)
** Adjust load by dividing by 10 and multiplying by 4 EVs 

gen Load_plus_HomeEVCharging = 4*(loadtransgrp10/10) + kWh_added_hour_home 

** Find the maximum draw on the transformer in kWhs for each transformer, pre- and post-treatment 
collapse (firstnm) group (max) Load_plus_HomeEVCharging, by(treatment_new Post_Treat)

** Find the average upgrade need for each group, pre- and post-treatment 

collapse (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

gen Number_EVs = 4 

gen iteration = `i'

** Store results 

append using `building'

save `building', replace


}

** Take the average of the 100 draws 

collapse (max) Number_EVs (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

save "$data/EV_MaxDemand_Simulation_Count4.dta", replace 


*****************
** 5 EV groupings 
*****************

** Create an initially empty data set to store the results of the loop 

clear 
tempfile building
save `building', emptyok

forvalues i = 1(1)100{

** Load the panel data file 

use `panel_data_T_C', clear 

** Randomly create different groupings, and calculate the required transformer capacity to meet load 
** Create a temp file with new groupings 

preserve 

keep vehicle_id group 

duplicates drop 

sort group vehicle_id

set seed `i'

generate u1 = runiform()

sort group u1 

** Need groups of 5 ==> must drop 2 C and 0 T (drop the final in the ranking)

gen ones = 1 

bysort group (u1): gen sum_ones = sum(ones)

drop if sum_ones > 60 & group == "C"
*drop if sum_ones > 68 & group == "T"

drop ones sum_ones

xtile transformer_new_C = u1 if group == "C" , nq(12)
xtile transformer_new_T = u1 if group == "T" , nq(14)

gen transformer_new = transformer_new_C if group == "C"
replace transformer_new = transformer_new_T if group == "T" 

drop transformer_new_C transformer_new_T

tempfile Transformer_Allocation_5
save `Transformer_Allocation_5'

restore 

** Merge in the random EV allocation into the TOU and Control panel 

merge m:1 vehicle_id using `Transformer_Allocation_5'

drop if _m == 1 

drop _m 

egen treatment_new = concat(group transformer_new)

*******
** Collapse to the transformer-day-hour level, summing up the amount charged at home 
** Using new 5-EV transformers 
*******

collapse (max) transformer_new loadtransgrp10  (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment_new date hour_start)

** Post-Treatment Flag - used below 

gen Post_Treat = 0 
replace Post_Treat = 1 if date >= td(05Jul2023) 

********************************************************************************
** Calculate the capacity level required for Control, TOU, and Managed to meet maximum demand 
** Calculate the relative difference between TOU and Control versus Managed and Control 
********************************************************************************

** For each transformer and hour, calculate the summation of at-home charging and underlying representative load (which is based on 10 homes)
** Adjust load by dividing by 10 and multiplying by 5 EVs 

gen Load_plus_HomeEVCharging = 5*(loadtransgrp10/10) + kWh_added_hour_home 

** Find the maximum draw on the transformer in kWhs for each transformer, pre- and post-treatment 
collapse (firstnm) group (max) Load_plus_HomeEVCharging, by(treatment_new Post_Treat)

** Find the average upgrade need for each group, pre- and post-treatment 

collapse (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

gen Number_EVs = 5 

gen iteration = `i'

** Store results 

append using `building'

save `building', replace


}

** Take the average of the 100 draws 

collapse (max) Number_EVs (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

save "$data/EV_MaxDemand_Simulation_Count5.dta", replace 


*****************
** 6 EV groupings 
*****************

** Create an initially empty data set to store the results of the loop 

clear 
tempfile building
save `building', emptyok

forvalues i = 1(1)100{

** Load the panel data file 

use `panel_data_T_C', clear 

** Randomly create different groupings, and calculate the required transformer capacity to meet load 
** Create a temp file with new groupings 

preserve 

keep vehicle_id group 

duplicates drop 

sort group vehicle_id

set seed `i'

generate u1 = runiform()

sort group u1 

** Need groups of 6 ==> must drop 2 C and 4 T (drop the final in the ranking)

gen ones = 1 

bysort group (u1): gen sum_ones = sum(ones)

drop if sum_ones > 60 & group == "C"
drop if sum_ones > 66 & group == "T"

drop ones sum_ones

xtile transformer_new_C = u1 if group == "C" , nq(10)
xtile transformer_new_T = u1 if group == "T" , nq(11)

gen transformer_new = transformer_new_C if group == "C"
replace transformer_new = transformer_new_T if group == "T" 

drop transformer_new_C transformer_new_T

tempfile Transformer_Allocation_6
save `Transformer_Allocation_6'

restore 

** Merge in the random EV allocation into the TOU and Control panel 

merge m:1 vehicle_id using `Transformer_Allocation_6'

drop if _m == 1 

drop _m 

egen treatment_new = concat(group transformer_new)

*******
** Collapse to the transformer-day-hour level, summing up the amount charged at home 
** Using new 6-EV transformers 
*******

collapse (max) transformer_new loadtransgrp10  (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment_new date hour_start)

** Post-Treatment Flag - used below 

gen Post_Treat = 0 
replace Post_Treat = 1 if date >= td(05Jul2023) 

********************************************************************************
** Calculate the capacity level required for Control, TOU, and Managed to meet maximum demand 
** Calculate the relative difference between TOU and Control versus Managed and Control 
********************************************************************************

** For each transformer and hour, calculate the summation of at-home charging and underlying representative load (which is based on 10 homes)
** Adjust load by dividing by 10 and multiplying by 6 EVs 

gen Load_plus_HomeEVCharging = 6*(loadtransgrp10/10) + kWh_added_hour_home 

** Find the maximum draw on the transformer in kWhs for each transformer, pre- and post-treatment 
collapse (firstnm) group (max) Load_plus_HomeEVCharging, by(treatment_new Post_Treat)

** Find the average upgrade need for each group, pre- and post-treatment 

collapse (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

gen Number_EVs = 6

gen iteration = `i'

** Store results 

append using `building'

save `building', replace


}

** Take the average of the 100 draws 

collapse (max) Number_EVs (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

save "$data/EV_MaxDemand_Simulation_Count6.dta", replace 


*****************
** 7 EV groupings 
*****************

** Create an initially empty data set to store the results of the loop 

clear 
tempfile building
save `building', emptyok

forvalues i = 1(1)100{

** Load the panel data file 

use `panel_data_T_C', clear 

** Randomly create different groupings, and calculate the required transformer capacity to meet load 
** Create a temp file with new groupings 

preserve 

keep vehicle_id group 

duplicates drop 

sort group vehicle_id

set seed `i'

generate u1 = runiform()

sort group u1 

** Need groups of 7 ==> must drop 6 C and 0 T (drop the final in the ranking)

gen ones = 1 

bysort group (u1): gen sum_ones = sum(ones)

drop if sum_ones > 56 & group == "C"
*drop if sum_ones > 66 & group == "T"

drop ones sum_ones

xtile transformer_new_C = u1 if group == "C" , nq(8)
xtile transformer_new_T = u1 if group == "T" , nq(10)

gen transformer_new = transformer_new_C if group == "C"
replace transformer_new = transformer_new_T if group == "T" 

drop transformer_new_C transformer_new_T

tempfile Transformer_Allocation_7
save `Transformer_Allocation_7'

restore 

** Merge in the random EV allocation into the TOU and Control panel 

merge m:1 vehicle_id using `Transformer_Allocation_7'

drop if _m == 1 

drop _m 

egen treatment_new = concat(group transformer_new)

*******
** Collapse to the transformer-day-hour level, summing up the amount charged at home 
** Using new 7-EV transformers 
*******

collapse (max) transformer_new loadtransgrp10  (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment_new date hour_start)

** Post-Treatment Flag - used below 

gen Post_Treat = 0 
replace Post_Treat = 1 if date >= td(05Jul2023) 

********************************************************************************
** Calculate the capacity level required for Control, TOU, and Managed to meet maximum demand 
** Calculate the relative difference between TOU and Control versus Managed and Control 
********************************************************************************

** For each transformer and hour, calculate the summation of at-home charging and underlying representative load (which is based on 10 homes)
** Adjust load by dividing by 10 and multiplying by 7 EVs 

gen Load_plus_HomeEVCharging = 7*(loadtransgrp10/10) + kWh_added_hour_home 

** Find the maximum draw on the transformer in kWhs for each transformer, pre- and post-treatment 
collapse (firstnm) group (max) Load_plus_HomeEVCharging, by(treatment_new Post_Treat)

** Find the average upgrade need for each group, pre- and post-treatment 

collapse (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

gen Number_EVs = 7

gen iteration = `i'

** Store results 

append using `building'

save `building', replace


}

** Take the average of the 100 draws 

collapse (max) Number_EVs (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

save "$data/EV_MaxDemand_Simulation_Count7.dta", replace 


*****************
** 8 EV groupings 
*****************

** Create an initially empty data set to store the results of the loop 

clear 
tempfile building
save `building', emptyok

forvalues i = 1(1)100{

** Load the panel data file 

use `panel_data_T_C', clear 

** Randomly create different groupings, and calculate the required transformer capacity to meet load 
** Create a temp file with new groupings 

preserve 

keep vehicle_id group 

duplicates drop 

sort group vehicle_id

set seed `i'

generate u1 = runiform()

sort group u1 

** Need groups of 8 ==> must drop 6 C and 6 T (drop the final in the ranking)

gen ones = 1 

bysort group (u1): gen sum_ones = sum(ones)

drop if sum_ones > 56 & group == "C"
drop if sum_ones > 64 & group == "T"

drop ones sum_ones

xtile transformer_new_C = u1 if group == "C" , nq(7)
xtile transformer_new_T = u1 if group == "T" , nq(8)

gen transformer_new = transformer_new_C if group == "C"
replace transformer_new = transformer_new_T if group == "T" 

drop transformer_new_C transformer_new_T

tempfile Transformer_Allocation_8
save `Transformer_Allocation_8'

restore 

** Merge in the random EV allocation into the TOU and Control panel 

merge m:1 vehicle_id using `Transformer_Allocation_8'

drop if _m == 1 

drop _m 

egen treatment_new = concat(group transformer_new)

*******
** Collapse to the transformer-day-hour level, summing up the amount charged at home 
** Using new 8-EV transformers 
*******

collapse (max) transformer_new loadtransgrp10  (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment_new date hour_start)

** Post-Treatment Flag - used below 

gen Post_Treat = 0 
replace Post_Treat = 1 if date >= td(05Jul2023) 

********************************************************************************
** Calculate the capacity level required for Control, TOU, and Managed to meet maximum demand 
** Calculate the relative difference between TOU and Control versus Managed and Control 
********************************************************************************

** For each transformer and hour, calculate the summation of at-home charging and underlying representative load (which is based on 10 homes)
** Adjust load by dividing by 10 and multiplying by 8 EVs 

gen Load_plus_HomeEVCharging = 8*(loadtransgrp10/10) + kWh_added_hour_home 

** Find the maximum draw on the transformer in kWhs for each transformer, pre- and post-treatment 
collapse (firstnm) group (max) Load_plus_HomeEVCharging, by(treatment_new Post_Treat)

** Find the average upgrade need for each group, pre- and post-treatment 

collapse (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

gen Number_EVs = 8

gen iteration = `i'

** Store results 

append using `building'

save `building', replace


}

** Take the average of the 100 draws 

collapse (max) Number_EVs (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

save "$data/EV_MaxDemand_Simulation_Count8.dta", replace 

*****************
** 9 EV groupings 
*****************

** Create an initially empty data set to store the results of the loop 

clear 
tempfile building
save `building', emptyok

forvalues i = 1(1)100{

** Load the panel data file 

use `panel_data_T_C', clear 

** Randomly create different groupings, and calculate the required transformer capacity to meet load 
** Create a temp file with new groupings 

preserve 

keep vehicle_id group 

duplicates drop 

sort group vehicle_id

set seed `i'

generate u1 = runiform()

sort group u1 

** Need groups of 9 ==> must drop 8 C and 7 T (drop the final in the ranking)

gen ones = 1 

bysort group (u1): gen sum_ones = sum(ones)

drop if sum_ones > 54 & group == "C"
drop if sum_ones > 63 & group == "T"

drop ones sum_ones

xtile transformer_new_C = u1 if group == "C" , nq(6)
xtile transformer_new_T = u1 if group == "T" , nq(7)

gen transformer_new = transformer_new_C if group == "C"
replace transformer_new = transformer_new_T if group == "T" 

drop transformer_new_C transformer_new_T

tempfile Transformer_Allocation_9
save `Transformer_Allocation_9'

restore 

** Merge in the random EV allocation into the TOU and Control panel 

merge m:1 vehicle_id using `Transformer_Allocation_9'

drop if _m == 1 

drop _m 

egen treatment_new = concat(group transformer_new)

*******
** Collapse to the transformer-day-hour level, summing up the amount charged at home 
** Using new 9-EV transformers 
*******

collapse (max) transformer_new loadtransgrp10  (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment_new date hour_start)

** Post-Treatment Flag - used below 

gen Post_Treat = 0 
replace Post_Treat = 1 if date >= td(05Jul2023) 

********************************************************************************
** Calculate the capacity level required for Control, TOU, and Managed to meet maximum demand 
** Calculate the relative difference between TOU and Control versus Managed and Control 
********************************************************************************

** For each transformer and hour, calculate the summation of at-home charging and underlying representative load (which is based on 10 homes)
** Adjust load by dividing by 10 and multiplying by 9 EVs 

gen Load_plus_HomeEVCharging = 9*(loadtransgrp10/10) + kWh_added_hour_home 

** Find the maximum draw on the transformer in kWhs for each transformer, pre- and post-treatment 
collapse (firstnm) group (max) Load_plus_HomeEVCharging, by(treatment_new Post_Treat)

** Find the average upgrade need for each group, pre- and post-treatment 

collapse (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

gen Number_EVs = 9

gen iteration = `i'

** Store results 

append using `building'

save `building', replace


}

** Take the average of the 100 draws 

collapse (max) Number_EVs (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

save "$data/EV_MaxDemand_Simulation_Count9.dta", replace 


*****************
** 10 EV groupings 
*****************

** Create an initially empty data set to store the results of the loop 

clear 
tempfile building
save `building', emptyok

forvalues i = 1(1)100{

** Load the panel data file 

use `panel_data_T_C', clear 

** Randomly create different groupings, and calculate the required transformer capacity to meet load 
** Create a temp file with new groupings 

preserve 

keep vehicle_id group 

duplicates drop 

sort group vehicle_id

set seed `i'

generate u1 = runiform()

sort group u1 

** Need groups of 10 ==> must drop 2 C and 0 T (drop the final in the ranking)

gen ones = 1 

bysort group (u1): gen sum_ones = sum(ones)

drop if sum_ones > 60 & group == "C"
*drop if sum_ones > 63 & group == "T"

drop ones sum_ones

xtile transformer_new_C = u1 if group == "C" , nq(6)
xtile transformer_new_T = u1 if group == "T" , nq(7)

gen transformer_new = transformer_new_C if group == "C"
replace transformer_new = transformer_new_T if group == "T" 

drop transformer_new_C transformer_new_T

tempfile Transformer_Allocation_10
save `Transformer_Allocation_10'

restore 

** Merge in the random EV allocation into the TOU and Control panel 

merge m:1 vehicle_id using `Transformer_Allocation_10'

drop if _m == 1 

drop _m 

egen treatment_new = concat(group transformer_new)

*******
** Collapse to the transformer-day-hour level, summing up the amount charged at home 
** Using new 10-EV transformers 
*******

collapse (max) transformer_new loadtransgrp10  (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment_new date hour_start)

** Post-Treatment Flag - used below 

gen Post_Treat = 0 
replace Post_Treat = 1 if date >= td(05Jul2023) 

********************************************************************************
** Calculate the capacity level required for Control, TOU, and Managed to meet maximum demand 
** Calculate the relative difference between TOU and Control versus Managed and Control 
********************************************************************************

** For each transformer and hour, calculate the summation of at-home charging and underlying representative load (which is based on 10 homes)
** Adjust load by dividing by 10 and multiplying by 10 EVs 

gen Load_plus_HomeEVCharging = 10*(loadtransgrp10/10) + kWh_added_hour_home 

** Find the maximum draw on the transformer in kWhs for each transformer, pre- and post-treatment 
collapse (firstnm) group (max) Load_plus_HomeEVCharging, by(treatment_new Post_Treat)

** Find the average upgrade need for each group, pre- and post-treatment 

collapse (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

gen Number_EVs = 10

gen iteration = `i'

** Store results 

append using `building'

save `building', replace


}

** Take the average of the 100 draws 

collapse (max) Number_EVs (mean) Load_plus_HomeEVCharging, by(group Post_Treat)

save "$data/EV_MaxDemand_Simulation_Count10.dta", replace 







********************************************************************************
** Merge files together - Plot infrastructure needs as N varies 
********************************************************************************

use "$data/EV_MaxDemand_Simulation_Count2.dta", clear 

append using "$data/EV_MaxDemand_Simulation_Count3.dta"
append using "$data/EV_MaxDemand_Simulation_Count4.dta"
append using "$data/EV_MaxDemand_Simulation_Count5.dta"
append using "$data/EV_MaxDemand_Simulation_Count6.dta"
append using "$data/EV_MaxDemand_Simulation_Count7.dta"
append using "$data/EV_MaxDemand_Simulation_Count8.dta"
append using "$data/EV_MaxDemand_Simulation_Count9.dta"
append using "$data/EV_MaxDemand_Simulation_Count10.dta" 


twoway (line Load_plus_HomeEVCharging Number_EVs if group == "T" & Post_Treat == 1, lcolor(black) ) ///
       (line Load_plus_HomeEVCharging Number_EVs if group == "C" & Post_Treat == 1, lcolor(black) lpattern(dash) ), ///
	   xtitle("Number of EVs") ytitle("Max Transformer Demand (kWh)") ///
	   legend( order(1 "TOU" 2 "Control") position(6) cols(2))  name(grc1leggraph ,replace)

gr draw grc1leggraph,  ysize(2.5) xsize(3.5)

graph export "$results/FigureC6.pdf", replace 		






