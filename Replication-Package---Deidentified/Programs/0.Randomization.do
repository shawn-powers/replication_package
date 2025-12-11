********************************************************************************
********************************************************************************
************************* Randomize EVs into Groups  ***************************
********************************************************************************
********************************************************************************

// SET DIRECTORY

global statapath "Insert Directory"
global data "$statapath/Data"
global panel "$statapath/Data/Panel"
global results "$statapath/Results"
global fortisdata "$statapath/Data/Fortis Data"


********************************************************************************
** Overall Randomization Approach 
********************************************************************************

** 1. Identify Non-Controllable EVs and EVs that are unverified 
** 2. Identify Always Away Chargers - drop 
** 3. Identify Multi-Vehicle Homes 
** 4. Identify EVs with no charging data at all
** 5. Identify EVs that do not have enough pre-treatment data 
** 6. Isolate Eligible single home vehicles and do clustering procedure 
** 7. Perform Randomization


********************************************************************************
** 1. Identify non-controllable EVs and unverified EVs
********************************************************************************

** Homes with EVS that cannot be controlled 
import excel "$data/Non-controllable vehicles-6-21-2023.xlsx", clear first 

gen non_controllable_flag = 1 

** Save as a temp file 

tempfile Noncontrollable_EVs
save `Noncontrollable_EVs'


** Homes with EVs with missing information 
import excel "$data/Unverified EVs List-6-26-2023.xlsx", clear first sheet("Raw Unverified List")

gen Unverified_EVs = 1 

rename VehicleID vehicle_id

rename HomeID home_id 

** Save as a temp file 

tempfile Unverified_EVs
save `Unverified_EVs'

********************************************************************************
** 2. Identify Always Away Chargers 
********************************************************************************

use "$data/charge_event_randomization.dta", clear 

sort vehicle_id s_start 

gen home_flag = 0 
replace home_flag = 1 if location == 0 // flags at-home charging sessions 

collapse (max) home_flag , by(vehicle_id )

** Note: 264 EVs in the charging data 
** 14 EVs never charged at home 
tab home_flag 

keep if home_flag == 0 

drop home_flag

gen away_charging = 1 

** Save as a temp file 

tempfile Awaychargingonly_EVs
save `Awaychargingonly_EVs'


********************************************************************************
** 3. Identify Multi-EV Homes 
********************************************************************************

use "$data/vehicle_data_randomization.dta", clear 

gen ones = 1 

bysort home_id: egen EV_count = sum(ones)

** There are 207 single EV households, twenty-six 2 EV homes, three 3 EV homes, one 4 EV homes, and one 6 EV home 
** This means 71 EVs are multi-EV homes
tab EV_count

** Create a list of multi-EV homes 

keep if EV_count > 1 

drop tesla_solar tesla_powerwall ones est_battery_range_miles

gen multi_EV = 1 

** Save as a temp file 

tempfile MultiEVHomes
save `MultiEVHomes'

********************************************************************************
** 4. Identify EVs that are not in the charging data  
********************************************************************************

use "$data/vehicle_data_randomization.dta", clear 

merge 1:m vehicle_id using "$data/charge_event_randomization.dta"

keep if _m == 1 

keep vehicle_id 

gen no_charge_data = 1

** Save as a temp file 

tempfile NoChargeData
save `NoChargeData'

********************************************************************************
** 5. Identify EVs that do not have enough pre-treatment data 
** Different from criteria 2 above because these EVs have some at home charging data 
** Cutoff date: Need to have charged at home at least once starting on April 1, 2023
********************************************************************************

use "$data/charge_event_randomization.dta", clear 

** Focus on at-home charging 

keep if location == 0 

** Create a date variable 

gen date = dofc(s_start)

format date %td 

** Identify each EV's first charge time 

bysort vehicle_id: egen min_s_start = min(date)

format min_s_start %td

** Identify the last at-home charge in the data 

bysort vehicle_id: egen max_s_start = max(date)

format max_s_start %td

** Flag EVs that haven't charged at home since before April 1 2023 

gen charge_2023 = 0 
replace charge_2023 = 1 if date >= td(01Apr2023)

** Collapse and save as a temp file 

collapse (max) charge_2023 (max) max_s_start (min) min_s_start, by(vehicle_id)

tab charge_2023

tempfile startdate
save `startdate'



********************************************************************************
** 6. Isolate Eligible single home vehicles and do clustering procedure 
********************************************************************************

*********
** Create a list of single vehicle home EVs that are controllable and have charged at home 
*********

use "$data/vehicle_data_randomization.dta", clear 

keep vehicle_id home_id 

** Flag non-controllable EVs

merge 1:1 vehicle_id using `Noncontrollable_EVs'

drop _m

** Flag always away charging EVs 

merge 1:1 vehicle_id using `Awaychargingonly_EVs'

drop _m 

** Flag Multi-EV Homes 

merge 1:1 vehicle_id using `MultiEVHomes'

drop _m 

** Merge in first at-home charge period 

merge 1:1 vehicle_id using `startdate'

drop _m 

** Merge in EVs with no charge data at all 

merge 1:1 vehicle_id using `NoChargeData' 

drop _m 

** Merge in EVs with Unverified Data 

merge 1:1 vehicle_id using `Unverified_EVs' 

drop _m 

keep vehicle_id non_controllable_flag away_charging EV_count multi_EV home_id min_s_start max_s_start charge_2023 no_charge_data Unverified_EVs

replace  non_controllable_flag = 0 if non_controllable_flag  == . 
replace away_charging = 0 if away_charging == . 
replace multi_EV = 0 if multi_EV == . 
replace EV_count = 1 if EV_count == . 
replace no_charge_data = 0 if no_charge_data == .
replace  Unverified_EVs = 0 if Unverified_EVs == . 

***********
** Understand Data Quality and Sample 
***********

** 278 EVs in the Vehicles List

count 

** 19 non-controllable EVs 
** 2 non-controllable EVs have no charging data 
** 3 haven't been charged at home since April 1, 2023, but have some at home charging data 
** 1 has always charged away 
** 1 is unverified - missing data
** 1 is part of a multi-EV home
** 13 eligible non-controllable EVs 

count if non_controllable_flag == 1
count if non_controllable_flag == 1 & no_charge_data == 1
count if non_controllable_flag == 1 & charge_2023 == 0 
count if non_controllable_flag == 1 & away_charging == 1  
count if non_controllable_flag == 1 & Unverified_EVs == 1  

tab multi_EV if non_controllable_flag == 1
count if non_controllable_flag == 1 &  away_charging == 0 & charge_2023 == 1 & no_charge_data == 0 & Unverified_EVs == 0

** 14 EVs are not in the charging data 

count if no_charge_data == 1 

** 14 EVs have charging data, but have never charged at home 

count if away_charging == 1 & no_charge_data == 0 

** 71 EVs that are part of multi-vehicle homes 
** 9 of them have charging data, but no at-home charging  
** 4 Have no charging data 
** 5 have unverified data 
** 1 has some at-home charging data, but it hasn't occurred recently 

count if multi_EV == 1 

count if multi_EV == 1 & away_charging == 1 & no_charge_data == 0  

count if multi_EV == 1 & no_charge_data == 1  

count if multi_EV == 1 & Unverified_EVs == 1  

count if multi_EV == 1 & charge_2023 == 0 & no_charge_data == 0   & away_charging == 0 

** Unverified Data 
** 30 EVs have unverified data in their accounts 
** 22 EVs would have passed our selection criteria otherwise 
** (i.e., they have at-home charge data after April 1, 2023)

count if Unverified_EVs == 1 
count if Unverified_EVs == 1 & no_charge_data == 0 & away_charging == 0 & charge_2023 == 1 

** Full Sample: All EVs that have some at-home charging since April 1, 2023
** Drop: 
** (i) EVs that have no charging data,
** (ii) EVs that have never charged at home, 
** (iii) EVs that haven't charged at home recently 
** (vi) EVs that disenrolled, were Tesla loaner EVs, and one PHEV 

drop if no_charge_data == 1 
drop if away_charging == 1 
drop if charge_2023 == 0 
drop if Unverified_EVs == 1 

drop if vehicle_id == 6584516 | vehicle_id == 6586486 | vehicle_id == 6589741 | ///
		vehicle_id == 6591412 | vehicle_id == 6588791 | vehicle_id == 6591481 | ///
		vehicle_id ==  6591994 | vehicle_id ==  6580075
		
** Final Sample 
** 216 EVs 
** 13 non-controllable EVs 
** 46 EVS are part of multi-EV households 
** 20 two EV homes
** 2 three EV homes 

count 
 
count if non_controllable_flag == 1 

** Recalculate the multi-EVs 

gen ones = 1 

bysort home_id: egen EV_count_final = sum(ones) 

drop ones 

tab EV_count_final if non_controllable_flag == 1 

tab EV_count_final

** Understand difference between EV_count and EV_count_final 
** 8 total homes 
** 1: 6 EV home down to 2
** 1: 4 EV home down to 3 
** 1: 3 EV home down to 1 
** 5: 2 EV homes down to 1 

gen EV_count_diff =  EV_count - EV_count_final

tab EV_count_diff

browse if EV_count_diff !=0 

unique (home_id) if EV_count_diff !=0 

** Understand the distribution of last charge 

sort max_s_start

browse 

hist max_s_start

sort  vehicle_id
 
save "$data/EV_List_Randomization.dta", replace 

count if non_controllable_flag == 0 

** 158 are homes with only one eligible EV 

count if non_controllable_flag == 0 & EV_count_final == 1 
  

********************************************************************************
********************************************************************************
** RANDOMIZATION Process 
********************************************************************************
********************************************************************************

** Eligible EVs (n = 216): 158 single-EV homes controllable, 14 in non-controllable + one Multi-EV , 44 Multi-vehicle EVs & Controllable 

** 1. 14 EVs are automatically allocated to the control - 13 non-controllable + 1 EV that is part of the non-controllable household 
** 2. Assign remaining 44 multi-vehicle home IDs to random spots, place all cars in the household in those spots 
** 3. Assign 158 vehicles to the remaining spots 

** Group Allocation: 70 M, 70 T, 76 C 
** Control group containts 76 - 13 non-controllable - 1 added multi-EV = 62 purely randomized EVs into Control 
 
** Transformer Groups of 10 EVs = 7 M, 7 T, 8 C
** Last 2 control groups are not size 10: 14 non-controllable home bundle in C8, 2 residual in C7. 
  
********************************************************************************
** Create Treatment and Transformer Template Data set
********************************************************************************

clear

set obs 224

gen treatment = "M1" if inrange(_n, 1, 10) 
replace treatment = "M2" if inrange(_n, 11, 20) 
replace treatment = "M3" if inrange(_n, 21, 30) 
replace treatment = "M4" if inrange(_n, 31, 40) 
replace treatment = "M5" if inrange(_n, 41, 50) 
replace treatment = "M6" if inrange(_n, 51, 60) 
replace treatment = "M7" if inrange(_n, 61, 70) 

replace treatment = "T1" if inrange(_n, 71, 80) 
replace treatment = "T2" if inrange(_n, 81, 90) 
replace treatment = "T3" if inrange(_n, 91, 100) 
replace treatment = "T4" if inrange(_n, 101, 110) 
replace treatment = "T5" if inrange(_n, 111, 120) 
replace treatment = "T6" if inrange(_n, 121, 130) 
replace treatment = "T7" if inrange(_n, 131, 140) 

replace treatment = "C1" if inrange(_n, 141, 150) 
replace treatment = "C2" if inrange(_n, 151, 160) 
replace treatment = "C3" if inrange(_n, 161, 170) 
replace treatment = "C4" if inrange(_n, 171, 180) 
replace treatment = "C5" if inrange(_n, 181, 190) 
replace treatment = "C6" if inrange(_n, 191, 200) 
replace treatment = "C7" if inrange(_n, 201, 210) 
replace treatment = "C8" if inrange(_n, 211, 224) 

gen group = substr(treatment, 1, 1)

gen transformer = substr(treatment, 2, 1)

destring transformer, replace 

** Create slots to randomize into 

gen ones = 1 

gen slot = sum(ones) 

** C7 only has 2 EVs 

drop if slot >= 203 & slot <= 210  

drop slot 

** Create final slots 
gen slot = sum(ones) 

** Do a check on the number of EVs in each treatment 

bysort treatment: egen test = sum(ones) 

sort slot 

drop test ones 

********************************************************************************
** Non-Controllable EVs (plus the 1 EV that is part of the non-controllable home)
** Allocate to the final Control group Slot 207 - 220 
********************************************************************************

preserve 

** Use Eligible EV Flagged data set 

use "$data/EV_List_Randomization.dta", clear 

keep if non_controllable_flag == 1  | home_id == 68491

count

sort vehicle_id 

** Fill in slot starting at 203 

gen ones = 1 

gen sum_ones = sum(ones)

gen slot = sum_ones + 202  

drop ones sum_ones 

** Save as a temp file and merge in with Treatment and Transformer Template Data set

tempfile noncontrollabledata
save `noncontrollabledata'

restore 

*********
** Reopen the Treatment and Transformer Template Data set and merge in the Non-Controllable EV Home slots 
*********

merge 1:1 slot using `noncontrollabledata'

drop _m 

** Make sure the multi_home EV is allocated to the same transformer 

tab treatment if home_id == 68491

** Create a transformer_slot that will be used to help with the merge below 

sort slot 

gen ones = 1 

bysort group transformer (slot): gen transformer_slot = sum(ones)

drop ones home_id 

sort slot 

********************************************************************************
** Now move on to the Multi-EV Homes 
** Allocate all EVs within a home to a group, then allocate to different transformers 
********************************************************************************

preserve 

** Use Eligible EV Flagged data set 

use "$data/EV_List_Randomization.dta", clear 

** Keep multi EV homes, dropping the one that is part of a non-controllable household (n = 44)

keep if EV_count_final > 1 

drop if home_id == 68491

count 

keep vehicle_id home_id EV_count_final

** Save as a temp file to merge back in after group and transformer assignments 
** Key: Used to match all EVs within a home to the same transformer-grouping 

tempfile MultiEV_randomdata
save `MultiEV_randomdata'

** Randomly assign multi_home to a group and transformer (M1... M7; T1..., T7; C1..., C7) 
** Drop duplicate home_ids 

** Group randomization 

duplicates drop home_id, force 

sort vehicle_id 

set seed 123456

generate random_number = runiformint(1,3)

gen group = "M" if random_number == 1 
replace group = "T" if random_number == 2 
replace group = "C" if random_number == 3 
 
tab group 

** Transformer randomization 

set seed 69524

gen T_random_number = runiformint(1,7) if group == "T"

set seed 69524

gen M_random_number = runiformint(1,7) if group == "M"

set seed 695247

gen C_random_number = runiformint(1,7) if group == "C"

egen transformer = rowmax(C_random_number T_random_number M_random_number)
 
** Make sure C7 does not have more than 2 Vehicles 

gen C7_flag = 0 
replace C7_flag = 1 if group == "C" & transformer == 7 

egen sum_C7_EVs = sum(EV_count_final) if C7_flag == 1 
 
tab sum_C7_EVs

drop sum_C7_EVs C7_flag
 
** keep home_id group and transformer, then merge back in with the vehicle-level data 

keep home_id group transformer

merge 1:m home_id  using `MultiEV_randomdata'

drop _m   

** Test that all multi-EV homes are in the same transformer -group
 
sort group transformer home_id vehicle_id

gen group_test = . 
replace group_test = 1 if group == "C"
replace group_test = 2 if group == "T"
replace group_test = 3 if group == "M"

bysort home_id: egen group_min = min(group_test)
bysort home_id: egen group_max = max(group_test)

gen group_diff = group_max-group_min

sum group_diff 

drop group_diff group_max group_min group_test

bysort home_id: egen transformer_min = min(transformer)
bysort home_id: egen transformer_max = max(transformer)

gen transformer_diff = transformer_max - transformer_min 

sum transformer_diff 
 
drop transformer_min transformer_max transformer_diff

sort group transformer home_id vehicle_id

** Create a transformer-group specific number - to merge with the template slot file 

gen ones = 1

bysort group transformer (vehicle_id): gen transformer_slot = sum(ones)

drop ones 

** Rename vehicle_id 

rename vehicle_id vehicle_id2

sort vehicle_id2

** Save as a temp file to merge in with the group and transformer assignments 

tempfile MultiEV_Assignments
save `MultiEV_Assignments'

restore 

*********
** Reopen the Treatment and Transformer Template Data set and merge in the Multi-EV home allocation 
*********

merge 1:1 group transformer transformer_slot using `MultiEV_Assignments'

replace vehicle_id = vehicle_id2 if _m == 3 

sort group transformer transformer_slot

drop home_id multi_EV non_controllable_flag EV_count away_charging charge_2023 min_s_start vehicle_id2 _m  no_charge_data EV_count_final EV_count_diff max_s_start Unverified_EVs

** Create a new slot variable to identify the remaining slots 

sort slot 

gen ones = 1 if vehicle_id == . 

gen slot_new = sum(ones) if vehicle_id == . 

drop ones slot 

rename slot_new slot

********************************************************************************
** Now move on to the 158 controllable single eligible EVs households 
** Allocate them randomly to the remaining slots 
********************************************************************************
 
preserve 

** Use Eligible EV Flagged data set 

use "$data/EV_List_Randomization.dta", clear 

** Drop multi_EV and non_controllable_flag

drop if EV_count_final > 1 
drop if non_controllable_flag == 1 

** Make sure home_id == 68491 is not in the sample 

count if home_id == 68491 

count
 
sort vehicle_id

** Randomly Allocate to a slot 1 - 158 
** Then merge in with the remaining slots 

set seed 639

generate shuffle_order  = runiform()

sort shuffle_order

gen ones = 1 

gen slot = sum(ones)

drop shuffle_order ones  non_controllable_flag multi_EV away_charging charge_2023 min_s_start home_id EV_count no_charge_data EV_count_final EV_count_diff max_s_start Unverified_EVs

rename vehicle_id vehicle_id2

** Save as temp file 

tempfile SingleEV_Data
save `SingleEV_Data'

restore

merge m:1 slot using `SingleEV_Data'
 
replace vehicle_id = vehicle_id2 if vehicle_id2 != . 

drop vehicle_id2 _m slot transformer_slot

sort treatment vehicle_id 

save "$data/treatment group assignment.dta", replace 

** Save as CSV

outsheet treatment group transformer vehicle_id using "$data/treatment group assignment.csv" , comma replace 

** Test group size 

gen ones = 1 

bysort group transformer: egen test = sum(ones)  
 
** Check for duplicate vehicle_id 

duplicates report vehicle_id  


********************************************************************************
********************************************************************************
** Multi-EVs that are not initially eligible 
** NOTE: Used in transformer constraint calculation
******************************************************************************** 
******************************************************************************** 

use "$data/treatment group assignment.dta", clear 

** Merge with eligible EV list to link to home_id 
 
merge 1:1 vehicle_id using "$data/EV_List_Randomization.dta" 
 
drop _m 
 
keep treatment group transformer vehicle_id home_id
 
** Merge with baseline vehicles data set that includes all EVs in the initial data 

merge 1:1 vehicle_id using "$data/vehicle_data_randomization.dta"

** Identify homes with multiple EVs and those that made it into the randomization 

gen ones = 1 

bysort home_id: egen EV_count = sum(ones) 

gen randomized_flag = 1 if _m == 3 

bysort home_id: egen randomized_home = sum(randomized_flag) 

** Focus only on homes with multiple EVs and at least one of their EVs made it into the randomization 

keep if EV_count > 1 

drop if randomized_home == 0 

** Drop EVs that disenrolled, were Tesla loaner EVs, and one PHEV - Do not want to match these if they are multi EV homes 

drop if vehicle_id == 6584516 | vehicle_id == 6586486 | vehicle_id == 6589741 | ///
		vehicle_id == 6591412 | vehicle_id == 6588791 | vehicle_id == 6591481 | ///
		vehicle_id ==  6591994 | vehicle_id ==  6580075
		
** Clean up dataset 

drop make model year tesla_powerwall tesla_solar est_battery_range_miles  ones _m  

** Drop homes where the number of EVs that are in the final randomized data set = EV_count (the initial number of EVs in the baseline sample)

drop if EV_count == randomized_home 

** There are 8 unique homes with 18 EVs 
** 7 of these EVs didn't make it into the randomization because of the selection criteria 
** Note: we actually dropped 12 EVs from multi-EV homes, but 5 of these were disenrolled from Optiwatt 

unique (home_id)

count if treatment == "" 

** Fill in the treatment group and transformer variables 

gen group_num = . 
replace group_num = 1 if group == "C"
replace group_num = 2 if group == "T"
replace group_num = 3 if group == "M"

bysort home_id: egen group_num_max = max(group_num)

replace group = "C" if group == "" & group_num_max == 1 
replace group = "T" if group == "" & group_num_max == 2 
replace group = "M" if group == "" & group_num_max == 3 

bysort home_id: egen transformer_max = max(transformer)

replace transformer = transformer_max if transformer == . 

egen treatment_temp = concat(group transformer)

replace treatment = treatment_temp if treatment == ""

keep treatment group transformer vehicle_id  

** Append the orginal EV file and delete duplicate vehicle_id entries 

append using "$data/treatment group assignment.dta"

duplicates tag vehicle_id, gen(duplicates)

sort vehicle_id 

browse if duplicates == 1 

drop duplicates

duplicates drop vehicle_id, force 

sort treatment vehicle_id 

save "$data/treatment group assignment_merged.dta", replace 

** Save as CSV

outsheet treatment group transformer vehicle_id using "$data/treatment group assignment_merged.csv" , comma replace 





