********************************************************************************
********************************************************************************
*************************** Cluster Robustness  ********************************
********************************************************************************
** This file clusters the Control and TOU groups based on pre-treatment observables 
** Then, aggregates the clusters into groups of 10 to evaluate if the violations are more 
** when similar EVs are allocated to the same transformer
** Idea: EVs living on the same transformer will have similar attributes (and driving/charging habits) 
** compared to our main analysis that does a pure randomization 
********************************************************************************
********************************************************************************
********************************************************************************

// SET DIRECTORY

global statapath "Insert Directory"
global data "$statapath/Data"
global panel "$statapath/Data/Panel"
global results "$statapath/Results"
global fortisdata "$statapath/Data/Fortis Data"

********************************************************************************
********************************************************************************
** Step 1: Clustering and Allocating to alternative virtual transformers
** Approach 1: Use a cluster-based approach 
********************************************************************************
********************************************************************************

 

********************************************************************************
** Construct Variables that summarize characteristics  
** For now, use all EVs - Eligible EVs identified below
********************************************************************************

* 1. off-peak charging share (need interval data)
* 2. home share of charging (session data)
* 3. session duration (minutes) (session data, home)
* 4. average kWh per charge session (session data, home)
* 5. max rate of home charge (kW) (session data, home)
* 6. charger type (L1,L2,L3)
* 7. average number of sessions per day (session data)
* 8. Tesla/non-Tesla (vehicle data)
* 9. Calculate the number of EVs at the household 

*******
* 1A. off-peak charging share (need interval data) - Home and Away 
*******

use "$panel/panel_hourly_analysis.dta", clear 

** Focus on data between April 1 and July 4th (pre-treatment)

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

** Flag hours as midday and evening off_peak 10 AM - 2 PM, 10 PM - 6 AM (hour start 22 - 5, 10 - 13)

order vehicle_id time date hour 

gen off_peak = 0 
replace off_peak = 1 if hour >= 22 | hour <= 5 
replace off_peak = 1 if hour >= 10 & hour <= 13

** Calculate the proportion of charging in the off_peak 

bysort vehicle_id: egen total_KWhs = sum(kWh_added_hour)

gen off_peak_KWhs = off_peak*kWh_added_hour

bysort vehicle_id: egen total_off_peak_KWhs = sum(off_peak_KWhs)

gen off_peak_share = 100*(total_off_peak_KWhs/total_KWhs)

** Collapse data and store 
collapse (max) off_peak_share, by(vehicle_id)

** Save as a temp file 

tempfile OffPeak_Share_vehicle
save `OffPeak_Share_vehicle'


*******
* 1B. off-peak charging share (need interval data) - Home Only 
*******

use "$panel/panel_hourly_analysis.dta", clear 

** Focus on data between April 1 and July 4th (pre-treatment)

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

** Flag hours as midday and evening off_peak 10 AM - 2 PM, 10 PM - 6 AM (hour start 22 - 5, 10 - 13)

order vehicle_id time date hour 

gen off_peak = 0 
replace off_peak = 1 if hour >= 22 | hour <= 5 
replace off_peak = 1 if hour >= 10 & hour <= 13

** Focus on at-home only 

keep if location == 0 

** Calculate the proportion of charging in the off_peak 

bysort vehicle_id: egen total_KWhs = sum(kWh_added_hour)

gen off_peak_KWhs = off_peak*kWh_added_hour

bysort vehicle_id: egen total_off_peak_KWhs = sum(off_peak_KWhs)

gen off_peak_share_home = 100*(total_off_peak_KWhs/total_KWhs)

** Collapse data and store 
collapse (max) off_peak_share_home, by(vehicle_id)

** Save as a temp file 

tempfile OffPeak_Share_vehicle_Home
save `OffPeak_Share_vehicle_Home'


*******
* 2. home share of charging (session data)
*******

use "$data/charge_event_analysis.dta", clear 

** Create a date variable 

gen date = dofc(s_start)

format date %td 

** Focus on data between April 1 and July 4th (pre-treatment)

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

** Calculate the share of charging at home 

gen home_flag = 0 
replace home_flag = 1 if location == 0 

bysort vehicle_id: egen total_KWhs = sum(st_kwh_added_to_car_battery)

gen st_kwh_added_to_car_battery_home = st_kwh_added_to_car_battery*home_flag

bysort vehicle_id: egen total_KWhs_home = sum(st_kwh_added_to_car_battery_home)

gen home_share = 100*(total_KWhs_home/total_KWhs) 

** Collapse data and store 
collapse (max) home_share, by(vehicle_id)

tempfile Home_Share_vehicle
save `Home_Share_vehicle'


*******
** 3. daily charge duration (minutes) (session data, home)
** 4. total kWh charged per day (session data, home)
** 5. max rate of home charge (kW) (session data, home)
*******

use "$data/charge_event_analysis.dta", clear 

** Create a date variable 

gen date = dofc(s_start)

format date %td 

** Focus on data between April 1 and July 4th (pre-treatment)

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

** Focus on at-home charging only 

keep if location == 0 

** 3. daily charge duration (minutes) (session data, home)

gen st_duration_minutes = (s_end - s_start)/(60*1000)

bysort vehicle_id date: egen daily_duration_minutes = total(st_duration_minutes)

** 4. total kWh charged per day (session data, home)

bysort vehicle_id date: egen total_KWhs_charged = total(st_kwh_added_to_car_battery)

** 5. max rate of home charge (kW) (session data, home)

bysort vehicle_id date: egen max_power = max(power_used_by_charger)

** Collapse data and store 
collapse (mean) daily_duration_minutes total_KWhs_charged max_power, by(vehicle_id)

tempfile Mins_KWhs_Power_vehicle
save `Mins_KWhs_Power_vehicle'


********
** 6. charger type (L1,L2,L3)
********

use "$data/charge_event_analysis.dta", clear 

** Create a date variable 

gen date = dofc(s_start)

format date %td 

** Focus on data between April 1 and July 4th (pre-treatment)

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

** Mean charger type by EV 

bysort vehicle_id: egen mean_charger_type = mean(charger_type)

** Collapse data and store 

collapse   (max) mean_charger_type, by(vehicle_id)

tempfile Chargetype
save `Chargetype'

********
** 7. average number of sessions per day (session data)
********

** First, we need to take all of the EVs in the charge session data and create a template that has one observation per EV for each day
** EVs that are not part of the program will be dropped below 

use "$data/charge_event_analysis.dta", clear 

keep vehicle_id 

duplicates drop 

** Date variable ranging from April 1 2023 - July 4 2023  

display td(01Apr2023)

display td(04July2023)

gen date = 23101

expand 95

sort vehicle_id 

gen ones = 1 

bysort vehicle_id: gen sum_ones = sum(ones) 

replace sum_ones = sum_ones - 1 

replace date = date + sum_ones 

format date %td 

drop ones sum_ones

tempfile EV_Date_Template
save `EV_Date_Template'


** Now calculate the number of charge sessions per day 

use "$data/charge_event_analysis.dta", clear 

** Create a date variable 

gen date = dofc(s_start)

format date %td 

** Find the min date an EV was in the sample 

bysort vehicle_id: egen min_date =min(date)

format min_date %td 

** Focus on data between April 1 and July 4th (pre-treatment)

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

** Count the number of sessions per day 

sort vehicle_id date  

gen ones = 1 

bysort vehicle_id date: egen dailycount_sessions = sum(ones)

** Collapse data down to the daily - vehicle level 

collapse  (max) dailycount_sessions min_date, by(vehicle_id date)

sort date 

** Merge in Daily-EV template file to fill in 0's 
** EVs that are not part of the trial will be dropped below 

merge m:1 vehicle_id date using `EV_Date_Template'

sort vehicle_id date 

replace dailycount_sessions = 0 if dailycount_sessions == . 

drop _m 

** Fill in min_date and drop observations that fall before the min_date 

bysort vehicle_id: egen min_date2 = max(min_date)

format min_date2 %td 

drop if date < min_date2 

** Collapse data and store 

collapse   (mean) dailycount_sessions, by(vehicle_id)

tempfile  Sessionscount
save `Sessionscount'

********
* 8. Tesla/non-Tesla (vehicle data)
********

use "$data/vehicle_data_analysis.dta", clear 

gen tesla_type = 0 
replace tesla_type = 1 if make == "tesla"

keep vehicle_id tesla_type est_battery_range_miles year

** Store 

tempfile Tesla_type
save `Tesla_type'


********
** 9. Daily Charge kWh Off Peak
********

** First, we need to take all of the EVs in the charge session data and create a template that has one observation per EV for each day
** EVs that are not part of the program will be dropped below 

use "$data/charge_event_analysis.dta", clear 

keep vehicle_id 

duplicates drop 

** Date variable ranging from April 1 2023 - July 4 2023  

display td(01Apr2023)

display td(04July2023)

gen date = 23101

expand 95

sort vehicle_id 

gen ones = 1 

bysort vehicle_id: gen sum_ones = sum(ones) 

replace sum_ones = sum_ones - 1 

replace date = date + sum_ones 

format date %td 

drop ones sum_ones

tempfile EV_Date_Template
save `EV_Date_Template'

** Calculate the Daily Off-peak charged kWhs at home 

use "$panel/panel_hourly_analysis.dta", clear 

** Flag the min_date for each EV (to account for EVs below that entered after April 1)

bysort vehicle_id: egen min_date = min(date)

format %td min_date 

** Focus on data between April 1 and July 4th (pre-treatment)

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

** Flag hours as midday and evening off_peak 10 AM - 2 PM, 10 PM - 6 AM (hour start 22 - 5, 10 - 13)

order vehicle_id time date hour 

gen off_peak = 0 
replace off_peak = 1 if hour >= 22 | hour <= 5 
replace off_peak = 1 if hour >= 10 & hour <= 13

** Focus on at-home only 

keep if location == 0 

** off_peak charged kWhs at home  

gen off_peak_KWhs = off_peak*kWh_added_hour
 
** Collapse data and store 
collapse (min) min_date (sum) off_peak_KWhs, by(vehicle_id date)

** Merge in date template file 

merge 1:1 vehicle_id date using `EV_Date_Template'

sort vehicle_id date

drop _m 

** Replace min_date 

bysort vehicle_id: egen min_date2 = min(min_date)

format %td min_date2

drop min_date 

rename min_date2 min_date 

** Replace missing days with zero off-peak charging kWhs 

replace off_peak_KWhs = 0 if off_peak_KWhs == . 


** Drop dates less than min_date 
drop if date < min_date 

** Compute the average daily off_peak Charge kWhs by EV 

collapse (mean) off_peak_KWhs ,by(vehicle_id)

** Store 

tempfile ChargekWhDailyOffPeak
save `ChargekWhDailyOffPeak'



****************
** Bring the characteristics together and Isolate Eligible vehicles 
****************

use `OffPeak_Share_vehicle', clear 

merge 1:1 vehicle_id using `OffPeak_Share_vehicle_Home'

drop _m 

merge 1:1 vehicle_id using `Home_Share_vehicle'

drop _m 

merge 1:1 vehicle_id using `Mins_KWhs_Power_vehicle'

drop _m 

merge 1:1 vehicle_id using `Chargetype'

drop _m 

merge 1:1 vehicle_id using `Sessionscount'

drop _m 

merge 1:1 vehicle_id using `Tesla_type'

drop _m 

merge 1:1 vehicle_id using `ChargekWhDailyOffPeak'

drop _m 



** Merge in vehicle eligibility flags - focus only on Control and TOU EVs, drop C8 

merge m:1 vehicle_id using "$data/treatment group assignment.dta"

** _m == 1 are EVs that didnt make it into our trial, but have some charging data 
** Sizable numbers are coming from the fact that we have a number of unverified EVs that would have been eligible otherwise 

drop if _m == 1

drop _m 


tab group 

drop if group == "M"

** Drop C8 control group - non-controllable EVs 

drop if treatment == "C8"

tab group 

********************************************************************************
** Cluster remaining EVs into groups of 10 EVs 
** Cluster within TOU and then Control 
********************************************************************************

set seed 1234

** Create a temporary file

tempfile temp_clustering
save `temp_clustering'

** Create an empty file for control and TOU groups 
preserve
clear
save "$data/rc_clustering_C" , emptyok replace
save "$data/rc_clustering_T" , emptyok replace
restore

** Start with TOU 

** Cluster and create 7 groups of 10

use `temp_clustering', clear

keep if group == "T"

// Iterative Clustering
gen converged = 0
gen iteration = 100

while (converged == 0) {

	local n = _N
	local cluster_size = `n' / 10


	// Initial K-Means Clustering
	cluster kmeans off_peak_KWhs home_share daily_duration_minutes est_battery_range_miles max_power, k(`cluster_size') gen(cluster_var)

	
	
    // Calculate Group Means
    foreach var in off_peak_KWhs home_share daily_duration_minutes est_battery_range_miles max_power{
        bys cluster_var : egen cm_`var' = mean(`var') // Calculate cluster means
    }

    // Calculate SSE for each observation
    gen sse_current_cluster = 0
    foreach var in off_peak_KWhs home_share daily_duration_minutes est_battery_range_miles max_power {
        gen sq_diff_`var' = (`var' - cm_`var')^2 // Calculate squared differences
        replace sse_current_cluster = sse_current_cluster + sq_diff_`var' // Add squared differences to SSE
        drop sq_diff_`var' // Drop temporary variable
    }
	
    replace sse_current_cluster = sse_current_cluster^(0.5)

    // Calculate Group Sizes
    bysort cluster_var: gen group_size = _N
    bysort cluster_var (sse_current_cluster): gen over_ten = _n - 10

    // Mark Observations to Reassign
	gen to_leave = (over_ten > 0)

	preserve
	
	keep if group_size>=10 & over_ten<1
	drop group_size over_ten to_leave sse_current_cluster cm_off_peak_KWhs-cm_max_power
	
	replace cluster_var=cluster_var*iteration
	drop converged iteration
	append using "$data/rc_clustering_T"
	save "$data/rc_clustering_T" , replace

	restore
	
	
    // Save Complete Clusters
    drop if group_size>=10 & over_ten<1
	
	drop group_size over_ten to_leave cluster_var sse_current_cluster cm_off_peak_KWhs-cm_max_power

	count
	if r(N) == 0 {
		display "No observations left in the dataset. Exiting the program."
        qui set obs 1
		qui replace converged=1
}

	qui replace iteration = iteration*10

}


** Control 

use `temp_clustering', clear
 
keep if group == "C"

** Start with creating 5 groups of 10
 
// Iterative Clustering

gen converged = 0
gen iteration = 100

while (converged == 0 & _N>12) {

	local n = _N
	local cluster_size = floor(`n' / 10) 

	// Initial K-Means Clustering
	cluster kmeans off_peak_KWhs home_share daily_duration_minutes est_battery_range_miles max_power, k(	`cluster_size') gen(cluster_var)

    // Calculate Group Means
    foreach var in off_peak_KWhs home_share daily_duration_minutes est_battery_range_miles max_power {
        bys cluster_var : egen cm_`var' = mean(`var') // Calculate cluster means
    }

    // Calculate SSE for each observation
    gen sse_current_cluster = 0
    foreach var in off_peak_KWhs home_share daily_duration_minutes est_battery_range_miles max_power {
        gen sq_diff_`var' = (`var' - cm_`var')^2 // Calculate squared differences
        replace sse_current_cluster = sse_current_cluster + sq_diff_`var' // Add squared differences to SSE
        drop sq_diff_`var' // Drop temporary variable
    }
	
    replace sse_current_cluster = sse_current_cluster^(0.5)

    // Calculate Group Sizes
    bysort cluster_var: gen group_size = _N
    bysort cluster_var (sse_current_cluster): gen over_ten = _n - 10

    // Mark Observations to Reassign
	gen to_leave = (over_ten > 0)

	// Save Complete Clusters
	
	preserve
	
		keep if group_size>=10 & over_ten<1
		drop group_size over_ten to_leave sse_current_cluster cm_off_peak_KWhs-cm_max_power
		replace cluster_var=cluster_var*iteration
		drop converged iteration
		
	append using "$data/rc_clustering_C"
	save "$data/rc_clustering_C" , replace

	restore
	
 
    drop if group_size>=10 & over_ten<1
	drop group_size over_ten to_leave cluster_var sse_current_cluster cm_off_peak_KWhs-cm_max_power

	count
	
	replace iteration = iteration*10
	
}

** Rmaining Observations Clustering 

    // Calculate Group Means
    foreach var in off_peak_KWhs home_share daily_duration_minutes est_battery_range_miles max_power {
        egen cm_`var' = mean(`var') // Calculate cluster means
    }

    // Calculate SSE for each observation
    gen sse_current_cluster = 0
    foreach var in off_peak_KWhs home_share daily_duration_minutes est_battery_range_miles max_power {
        gen sq_diff_`var' = (`var' - cm_`var')^2 // Calculate squared differences
        replace sse_current_cluster = sse_current_cluster + sq_diff_`var' // Add squared differences to SSE
        drop sq_diff_`var' // Drop temporary variable
    }
	
    replace sse_current_cluster = sse_current_cluster^(0.5)

    // Calculate Group Size (which is 12)
    gen group_size = _N
    bysort group_size (sse_current_cluster): gen over_ten = _n - 10

    // Mark Observations to Reassign
	gen to_leave = (over_ten > 0)

	preserve
	
		keep if group_size>=10 & over_ten<1
		drop group_size over_ten to_leave sse_current_cluster cm_off_peak_KWhs-cm_max_power
		generate cluster_var=iteration
		drop converged iteration
		
	append using "$data/rc_clustering_C"
	save "$data/rc_clustering_C" , replace

	restore
	
    // Save Complete Clusters
		drop if group_size>=10 & over_ten<1
		drop group_size over_ten to_leave sse_current_cluster cm_off_peak_KWhs-cm_max_power
		generate cluster_var= iteration*10
		drop iteration converged

	append using "$data/rc_clustering_C"
	
		egen cluster = group(cluster_var)
		drop cluster_var
	
	save "$data/rc_clustering_C" , replace

** Combine Control and TOU Clusters	
	
	
	use "$data/rc_clustering_T" , clear

		egen cluster = group(cluster_var)
		replace cluster=cluster*10 // makes cluster numbers distinct from control groups
		drop cluster_var

	append using "$data/rc_clustering_C"
	
	
** Create a new cluster variable 

gen treatment2 = "C1" if cluster == 1
replace treatment2 = "C2" if cluster == 2
replace treatment2 = "C3" if cluster == 3
replace treatment2 = "C4" if cluster == 4
replace treatment2 = "C5" if cluster == 5
replace treatment2 = "C6" if cluster == 6
replace treatment2 = "C7" if cluster == 7

replace treatment2 = "T1" if cluster == 10
replace treatment2 = "T2" if cluster == 20
replace treatment2 = "T3" if cluster == 30
replace treatment2 = "T4" if cluster == 40
replace treatment2 = "T5" if cluster == 50
replace treatment2 = "T6" if cluster == 60
replace treatment2 = "T7" if cluster == 70

** Clean up file to only keep vehicle id and new clusters 

keep vehicle_id treatment2

save "$data/rc_clustering_Approach1.dta" , replace

	
********************************************************************************
** Need to create a transformer-day group limit for the new clusters 
** Use the original group limits for the correspondings groups (EVs are just resorted)
** Need to then adjust these new group limits by the number of EVs on the new transformers 
********************************************************************************

use "$data/group limits.dta", clear 

rename treatment treatment2 

drop if treatment2 == "C8"

rename constraint constraint_alt 
rename loadtransgrp10 loadtransgrp10_alt 
rename evloadlimit evloadlimit_alt

** Save as a tempfile 
tempfile group_limits_clusteralt
save `group_limits_clusteralt'


** Create a transformer-by-day specific count of EVs 
** Merge in the new randomized group assignments 

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

** Merge in new transformer assignments 

merge m:1 vehicle_id using "$data/rc_clustering_Approach1.dta" 

** _m == 1 are C8 and Managed EVs 

drop if treatment == "C8" 

replace treatment2 = treatment if _m== 1 

** Collapse to the treatment group - date level - counting the number of EVs that remain 

gen EV_Count = 1 

collapse (sum) EV_Count, by(treatment2 date)

merge 1:m treatment2 date using `group_limits_clusteralt'

** _m == 2 are observations are outside of our sample period 

drop if _m == 2 

drop _m 

sort treatment2 time 

****
** Create an adjusted constraint 
****

** Underlying HH load per EV 
gen double loadtransgrp_perEV_alt = loadtransgrp10_alt/10 

** Create an adjusted underlying load by the number of EVs enrolled 
gen double loadtransgrp_adj_alt = EV_Count*loadtransgrp_perEV_alt

** Adjust Constraint (which is based on a 10 EV transformer) - multiple the number of EVs by the constraint per EV 

gen double constraint_adj_alt = EV_Count*(constraint_alt/10)

** Adjusted EV Load Limit 
gen double evloadlimit_adj_alt = constraint_adj_alt - loadtransgrp_adj_alt

drop loadtransgrp_perEV_alt

** Only keep the key variables 

rename EV_Count EV_Count_alt 

order treatment2 date hour hour time evloadlimit_adj_alt EV_Count_alt

keep treatment2 date hour hour time evloadlimit_adj_alt EV_Count_alt

** Save 
save "$data/group_limits_Adjusted_alternate.dta", replace 



********************************************************************************
********************************************************************************
** Step 2: Descriptive analysis - Evaluating violations with new clusters 
********************************************************************************
********************************************************************************

** Construct a panel data set to do descriptive analysis 
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

** Clean up data 

drop hour 

order vehicle_id date time hour_start 

sort  vehicle_id date hour_start 

** Verify that everyone in the sample has a treatment group assignment 

count if treatment == ""

******* 
** Merge in new clusters 
*******

merge m:1 vehicle_id using "$data/rc_clustering_Approach1.dta" 

** _M == 1 if C8 or Managed 

drop if treatment == "C8"

replace treatment2 = treatment if _m == 1 

drop _m 

*******
** Merge in adjusted transformer limits file - necessary to understand the "room" available on each transformer 
*******

** Merge by treatment group and time 

merge m:1 treatment2 time using "$data/group_limits_Adjusted_alternate.dta"

** _m == 2 are hours that are either before our sample or after the data ends 

drop if _m == 2 

drop _m  hour
 
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

*******
** Clean up data set 
*******

order vehicle_id treatment2 group transformer date time hour_start kWh_added_hour kWh_added_hour_home

** Drop 14 non-controllable EVs in transformer C8 

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
** Descriptive Plots 
********************************************************************************
********************************************************************************


********************************************************************************
** Transformer-Level: Graphs of Violations - By Group, Pre and Post-Treatment 
********************************************************************************

** Approach, collapse data down to the transformer group by hour, pre and post-treatment 
** Then take the average transformer violation across transformers within the same group for each hour 

preserve 

** Focus on all cars (i.e., including those with randomized_eligible == 0)

** Collapse to the transformer-day-hour level, summing up the amount charged at home 

collapse (max)  evloadlimit_adj_alt EV_Count_alt (firstnm) group (sum) kWh_added_hour_home, by(treatment2 date hour_start)

** Create transformer space variable 
** Use adjusted EV Limit 

gen Transformer_Space = evloadlimit_adj_alt - kWh_added_hour_home

** Violation flag 

gen Violation = 0 
replace Violation = 1 if Transformer_Space < 0 

** Collapse to the transformer-month-hour level, taking the summation of Violation 
** Also add up the number of hour_starts within each month 
** Goal: At the treatment-month level, compute the percentage of cases where the transformer was violated 

gen ones = 1 

gen year = year(date)

gen month = month(date)

gen day = day(date)

** Generate Mean and Median of the Transformer_Space variable 

gen Median_Transformer_Space = Transformer_Space

gen Mean_Transformer_Space = Transformer_Space

** Create a variable that adds up the Violation KWhs 

gen Violation_KWhs = Violation*Transformer_Space

sort  treatment2  date hour_start  		

** Post-Treatment Flag 

gen Post_Treatment_Flag = 0 
replace Post_Treatment_Flag = 1 if date >= td(05jul2023)

** Descriptive stats

sum Violation_KWhs if group == "C" & Post_Treatment_Flag == 0 
sum Violation_KWhs if group == "C" & Post_Treatment_Flag == 1 

sum Violation_KWhs if group == "M" & Post_Treatment_Flag == 0 
sum Violation_KWhs if group == "M" & Post_Treatment_Flag == 1 

sum Violation_KWhs if group == "T" & Post_Treatment_Flag == 0 
sum Violation_KWhs if group == "T" & Post_Treatment_Flag == 1 

hist Violation_KWhs if group == "C" & Post_Treatment_Flag == 0  &  Violation_KWhs < 0 
hist Violation_KWhs if group == "C" & Post_Treatment_Flag == 1  &  Violation_KWhs < 0 

hist Violation_KWhs if group == "T" & Post_Treatment_Flag == 0  &  Violation_KWhs < 0 
hist Violation_KWhs if group == "T" & Post_Treatment_Flag == 1  &  Violation_KWhs < 0 

** Collapse down to group - hour - pre and post-treatment  

collapse (mean) Violation ones Violation_KWhs,  by(group Post_Treatment_Flag hour_start)

drop ones 

rename Violation Violation_alt
rename Violation_KWhs Violation_KWhs_alt

** Merge in data file from main analysis to compare violations 

merge 1:1 group Post_Treatment_Flag hour_start using "$data/Violations_Descriptive_Plots_Data.dta"		

drop _m 

sum Violation_KWhs_alt Violation_KWhs if group == "C" & Post_Treatment_Flag == 0 
sum Violation_KWhs_alt Violation_KWhs if group == "C" & Post_Treatment_Flag == 1 

sum Violation_KWhs_alt Violation_KWhs if group == "T" & Post_Treatment_Flag == 0 
sum Violation_KWhs_alt Violation_KWhs if group == "T" & Post_Treatment_Flag == 1

sum Violation_KWhs_alt Violation_KWhs if group == "M" & Post_Treatment_Flag == 0 
sum Violation_KWhs_alt Violation_KWhs if group == "M" & Post_Treatment_Flag == 1
		
**************************
** Plot of Violation KWhs - Average violation kWhs at the day-group-hour for both pre and post 
**************************	

replace Violation_KWhs_alt = -1*Violation_KWhs_alt

replace Violation_KWhs = -1*Violation_KWhs

** Managed (Verify the results are identical)

twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs_alt hour_start if group == "M" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "M" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Managed") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Pre-Treatment" 5 "Post-Treatment") cols(2) ) 
							
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "M" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "M" & Post_Treatment_Flag == 0,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Pre-Treatment") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Baseline" 5 "Alternative") cols(2) ) 
							
														
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "M" & Post_Treatment_Flag == 1, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "M" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Post-Treatment") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Baseline" 5 "Alternative") cols(2) ) 
							
													
** TOU 						
							
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs_alt hour_start if group == "T" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "T" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("TOU") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Pre-Treatment" 5 "Post-Treatment") cols(2) ) 
							
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "T" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "T" & Post_Treatment_Flag == 0,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Pre-Treatment") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Baseline" 5 "Alternative 2") cols(2) )  name(TOU_Pre ,replace) 
							
														
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "T" & Post_Treatment_Flag == 1, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "T" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Post-Treatment") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Baseline" 5 "Alternative 2") cols(2) )  name(TOU_Post ,replace) 
					  

grc1leg TOU_Pre TOU_Post , cols(1)  graphregion(color(white) ) name(grc1leggraph ,replace)
gr draw grc1leggraph,  ysize(4.5) xsize(2.5)						  
					
graph export "$results/FigureC5b.pdf", replace 					
					
					
** Control 						
							
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs_alt hour_start if group == "C" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "C" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Control") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Pre-Treatment" 5 "Post-Treatment") cols(2) ) 
							
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "C" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "C" & Post_Treatment_Flag == 0,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Pre-Treatment") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Baseline" 5 "Alternative 2") cols(2) )  name(Control_Pre ,replace) 
							
														
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "C" & Post_Treatment_Flag == 1, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "C" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Post-Treatment") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Baseline" 5 "Alternative 2") cols(2) ) name(Control_Post ,replace) 
					  

grc1leg Control_Pre Control_Post , cols(1)  graphregion(color(white) ) name(grc1leggraph ,replace)
gr draw grc1leggraph,  ysize(4.5) xsize(2.5)					

graph export "$results/FigureC5a.pdf", replace 	  
					  
restore 


********************************************************************************
********************************************************************************
** Step 3: Transformer-Level: Regression Analysis 
********************************************************************************
********************************************************************************


** Building off of the panel above 

preserve 

** Collapse to the transformer-day-hour level, summing up the amount charged at home 

collapse (max) evloadlimit_adj_alt    EV_Count_alt   (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment2 date hour_start)

** Create time-based controls 

gen off_peak = 0 
replace off_peak = 1 if hour_start >= 10 & hour_start <= 13
replace off_peak = 1 if hour_start >= 22
replace off_peak = 1 if hour_start >= 0 & hour_start <= 5

** Encode treatment group and transfomer grouping 

encode group, gen(group_num)

encode treatment2, gen(transformer_group)

** Post-Treatment Flag 

gen Post_Treat = 0 
replace Post_Treat = 1 if date >= td(05Jul2023) 

** Group-specific variable

gen TOU_group = 0 
replace TOU_group = 1 if group == "T"

gen Control_group = 0 
replace Control_group = 1 if group == "C"

gen Managed_group = 0 
replace Managed_group = 1 if group == "M"

** Group - Post variables 

gen TOU_Post = TOU_group*Post_Treat 

gen Managed_Post = Managed_group*Post_Treat 


********************************************************************************
** Dependent Variable: Violation KWhs  
********************************************************************************

** Construct Violation Kwhs Variable - Include measure adjusted by attrition 

gen Transformer_Space_adj = evloadlimit_adj_alt - kWh_added_hour_home

gen Violation_KWhs_adj = 0 
replace Violation_KWhs_adj = -1*Transformer_Space_adj if Transformer_Space_adj < 0 


*********
** Clustering: Transformer level with wild bootstrap 
** Works after reghdfe only if there is a single FE in absorb
** Manually do the FEs in the regression with factor variables 
** Note. Marginal effects are consistent to the main specification with these FEs in absorb 
** Reference (boottest): https://www.econ.queensu.ca/sites/econ.queensu.ca/files/qed_wp_1406.pdf 
*********		

** ssc install boottest


** Adjusted Measure - Only run on TOU and Control 

** TOU Treatment Effects 

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
								i.transformer_group i.hour_start if group != "M" ///
        , absorb(date) vce(robust)
		
		
xlincom  1.TOU_group#1.Post_Treat, post
matrix b = e(b)
scalar viol_tou_alt2_coeff = b[1,1]		

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
								i.transformer_group i.hour_start if group != "M" ///
        , absorb(date) vce(robust)
boottest 1.TOU_group#1.Post_Treat = 0 , reps (9999) seed(12345) nograph cluster(transformer_group)
matrix ci_viol_tou_alt2 = r(CI)
scalar ll_viol_tou_alt2 = ci_viol_tou_alt2[1,1]
scalar ul_viol_tou_alt2 = ci_viol_tou_alt2[1,2]
scalar pval_viol_tou_alt2 = r(p)

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
								i.transformer_group i.hour_start if group != "M" ///
        , absorb(date) vce(robust)
xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak, post
matrix b = e(b)
scalar viol_tou_offp_alt2_coeff = b[1,1]		
	
reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
								i.transformer_group i.hour_start if group != "M" ///
        , absorb(date) vce(robust)
boottest 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak  = 0 , reps (9999) seed(12345) nograph cluster(transformer_group)
matrix ci_viol_tou_offp_alt2 = r(CI)
scalar ll_viol_tou_offp_alt2 = ci_viol_tou_offp_alt2[1,1]
scalar ul_viol_tou_offp_alt2 = ci_viol_tou_offp_alt2[1,2]
scalar pval_viol_tou_offp_alt2 = r(p)

scalar obs2 = e(N)

	
restore 

* export results for Table C5

scalar viol_tou_alt2_coeff = round(viol_tou_alt2_coeff, 0.001)
scalar viol_tou_offp_alt2_coeff = round(viol_tou_offp_alt2_coeff, 0.001)
scalar ci_viol_tou_alt2 = "[" + string(matrix(ll_viol_tou_alt2), "%9.3f") + "," + string(matrix(ul_viol_tou_alt2), "%9.3f") + "]"
scalar ci_viol_tou_offp_alt2 = "[" + string(matrix(ll_viol_tou_offp_alt2), "%9.3f") + "," + string(matrix(ul_viol_tou_offp_alt2), "%9.3f") + "]"
scalar pval_viol_tou_alt2 = round(pval_viol_tou_alt2, 0.001)
scalar pval_viol_tou_offp_alt2 = round(pval_viol_tou_offp_alt2, 0.001)
scalar pval_viol_tou_alt2 = "(" + string(pval_viol_tou_alt2, "%9.3f") + ")"
scalar pval_viol_tou_offp_alt2 = "(" + string(pval_viol_tou_offp_alt2, "%9.3f") + ")"

putexcel set "$results/Table C5.xlsx", modify

putexcel E2 = viol_tou_alt2_coeff
putexcel E3 = pval_viol_tou_alt2
putexcel E4 = ci_viol_tou_alt2

putexcel E5 = viol_tou_offp_alt2_coeff
putexcel E6 = pval_viol_tou_offp_alt2	
putexcel E7 = ci_viol_tou_offp_alt2

putexcel E8 = obs2

********************************************************************************
********************************************************************************
** Approach 2: Clustering and Allocating to alternative virtual transformers
** Group EVs based on a single measure: kWhs charged at home in the off-peak (pre-treatment)
********************************************************************************
********************************************************************************
 
** First, we need to take all of the EVs in the charge session data and create a template that has one observation per EV for each day
** EVs that are not part of the program will be dropped below 

use "$data/charge_event_analysis.dta", clear 

keep vehicle_id 

duplicates drop 

** Date variable ranging from April 1 2023 - July 4 2023  

display td(01Apr2023)

display td(04July2023)

gen date = 23101

expand 95

sort vehicle_id 

gen ones = 1 

bysort vehicle_id: gen sum_ones = sum(ones) 

replace sum_ones = sum_ones - 1 

replace date = date + sum_ones 

format date %td 

drop ones sum_ones

tempfile EV_Date_Template
save `EV_Date_Template'

** Calculate the Daily Off-peak charged kWhs at home 

use "$panel/panel_hourly_analysis.dta", clear 

** Flag the min_date for each EV (to account for EVs below that entered after April 1)

bysort vehicle_id: egen min_date = min(date)

format %td min_date 

** Focus on data between April 1 and July 4th (pre-treatment)

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

** Flag hours as midday and evening off_peak 10 AM - 2 PM, 10 PM - 6 AM (hour start 22 - 5, 10 - 13)

order vehicle_id time date hour 

gen off_peak = 0 
replace off_peak = 1 if hour >= 22 | hour <= 5 
replace off_peak = 1 if hour >= 10 & hour <= 13

** Focus on at-home only 

keep if location == 0 

** off_peak charged kWhs at home  

gen off_peak_KWhs = off_peak*kWh_added_hour
 
** Collapse data and store 
collapse (min) min_date (sum) off_peak_KWhs, by(vehicle_id date)

** Merge in date template file 

merge 1:1 vehicle_id date using `EV_Date_Template'

sort vehicle_id date

drop _m 

** Replace min_date 

bysort vehicle_id: egen min_date2 = min(min_date)

format %td min_date2

drop min_date 

rename min_date2 min_date 

** Replace missing days with zero off-peak charging kWhs 

replace off_peak_KWhs = 0 if off_peak_KWhs == . 

** Only include EVs that were part of the experiment 

merge m:1 vehicle_id using "$data/treatment group assignment.dta"

drop if _m == 1 

drop _m 

** Drop group C8 

drop if treatment == "C8"

** Drop dates less than min_date 
drop if date < min_date 

** Compute the average daily off_peak Charge kWhs by EV 

collapse (firstnm) group treatment (mean) off_peak_KWhs ,by(vehicle_id)

sort group 	off_peak_KWhs
	
** Assign EVs to new treatment groups based on their value for 	off_peak_KWhs

gen ones = 1 

bysort group (off_peak_KWhs): gen group_cumul_sum = sum(ones)
	
gen treatment2 = "C1" if group_cumul_sum <= 10 & group == "C"
replace treatment2 = "C2" if group_cumul_sum > 10 & group_cumul_sum <= 20 & group == "C"
replace treatment2 = "C3" if group_cumul_sum > 20 & group_cumul_sum <= 30 & group == "C"
replace treatment2 = "C4" if group_cumul_sum > 30 & group_cumul_sum <= 40 & group == "C"
replace treatment2 = "C5" if group_cumul_sum > 40 & group_cumul_sum <= 50 & group == "C"
replace treatment2 = "C6" if group_cumul_sum > 50 & group_cumul_sum <= 60 & group == "C"
replace treatment2 = "C7" if group_cumul_sum > 60 & group == "C"

replace treatment2 = "T1" if group_cumul_sum <= 10 & group == "T"
replace treatment2 = "T2" if group_cumul_sum > 10 & group_cumul_sum <= 20 & group == "T"
replace treatment2 = "T3" if group_cumul_sum > 20 & group_cumul_sum <= 30 & group == "T"
replace treatment2 = "T4" if group_cumul_sum > 30 & group_cumul_sum <= 40 & group == "T"
replace treatment2 = "T5" if group_cumul_sum > 40 & group_cumul_sum <= 50 & group == "T"
replace treatment2 = "T6" if group_cumul_sum > 50 & group_cumul_sum <= 60 & group == "T"
replace treatment2 = "T7" if group_cumul_sum > 60 & group == "T"
	
drop if group == "M"

tab treatment2

keep vehicle_id treatment2

save "$data/rc_clustering_Approach2.dta" , replace

	

	
********************************************************************************
** Need to create a transformer-day group limit for the new clusters 
** Use the original group limits for the correspondings groups (EVs are just resorted)
** Need to then adjust these new group limits by the number of EVs on the new transformers 
********************************************************************************

use "$data/group limits.dta", clear 

rename treatment treatment2 

drop if treatment2 == "C8"

rename constraint constraint_alt 
rename loadtransgrp10 loadtransgrp10_alt 
rename evloadlimit evloadlimit_alt

** Save as a tempfile 
tempfile group_limits_clusteralt
save `group_limits_clusteralt'


** Create a transformer-by-day specific count of EVs 
** Merge in the new randomized group assignments 

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

** Merge in new transformer assignments 

merge m:1 vehicle_id using "$data/rc_clustering_Approach2.dta" 

** _m == 1 are C8 and Managed EVs 

drop if treatment == "C8" 

replace treatment2 = treatment if _m== 1 

** Collapse to the treatment group - date level - counting the number of EVs that remain 

gen EV_Count = 1 

collapse (sum) EV_Count, by(treatment2 date)

merge 1:m treatment2 date using `group_limits_clusteralt'

** _m == 2 are observations are outside of our sample period 

drop if _m == 2 

drop _m 

sort treatment2 time 

****
** Create an adjusted constraint 
****

** Underlying HH load per EV 
gen double loadtransgrp_perEV_alt = loadtransgrp10_alt/10 

** Create an adjusted underlying load by the number of EVs enrolled 
gen double loadtransgrp_adj_alt = EV_Count*loadtransgrp_perEV_alt

** Adjust Constraint (which is based on a 10 EV transformer) - multiple the number of EVs by the constraint per EV 

gen double constraint_adj_alt = EV_Count*(constraint_alt/10)

** Adjusted EV Load Limit 
gen double evloadlimit_adj_alt = constraint_adj_alt - loadtransgrp_adj_alt

drop loadtransgrp_perEV_alt

** Only keep the key variables 

rename EV_Count EV_Count_alt 

order treatment2 date hour hour time evloadlimit_adj_alt EV_Count_alt

keep treatment2 date hour hour time evloadlimit_adj_alt EV_Count_alt

** Save 
save "$data/group_limits_Adjusted_alternate.dta", replace 



********************************************************************************
********************************************************************************
** Step 2: Descriptive analysis - Evaluating violations with new clusters 
********************************************************************************
********************************************************************************

** Construct a panel data set to do descriptive analysis 
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

** Clean up data 

drop hour 

order vehicle_id date time hour_start 

sort  vehicle_id date hour_start 

** Verify that everyone in the sample has a treatment group assignment 

count if treatment == ""

******* 
** Merge in new clusters 
*******

merge m:1 vehicle_id using "$data/rc_clustering_Approach2.dta" 

** _M == 1 if C8 or Managed 

drop if treatment == "C8"

replace treatment2 = treatment if _m == 1 

drop _m 

*******
** Merge in adjusted transformer limits file - necessary to understand the "room" available on each transformer 
*******

** Merge by treatment group and time 

merge m:1 treatment2 time using "$data/group_limits_Adjusted_alternate.dta"

** _m == 2 are hours that are either before our sample or after the data ends 

drop if _m == 2 

drop _m  hour
 
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

*******
** Clean up data set 
*******

order vehicle_id treatment2 group transformer date time hour_start kWh_added_hour kWh_added_hour_home

** Drop 14 non-controllable EVs in transformer C8 

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
** Descriptive Plots 
********************************************************************************
********************************************************************************


********************************************************************************
** Transformer-Level: Graphs of Violations - By Group, Pre and Post-Treatment 
********************************************************************************

** Approach, collapse data down to the transformer group by hour, pre and post-treatment 
** Then take the average transformer violation across transformers within the same group for each hour 

preserve 

** Focus on all cars (i.e., including those with randomized_eligible == 0)

** Collapse to the transformer-day-hour level, summing up the amount charged at home 

collapse (max)  evloadlimit_adj_alt EV_Count_alt (firstnm) group (sum) kWh_added_hour_home, by(treatment2 date hour_start)

** Create transformer space variable 
** Use adjusted EV Limit 

gen Transformer_Space = evloadlimit_adj_alt - kWh_added_hour_home

** Violation flag 

gen Violation = 0 
replace Violation = 1 if Transformer_Space < 0 

** Collapse to the transformer-month-hour level, taking the summation of Violation 
** Also add up the number of hour_starts within each month 
** Goal: At the treatment-month level, compute the percentage of cases where the transformer was violated 

gen ones = 1 

gen year = year(date)

gen month = month(date)

gen day = day(date)

** Generate Mean and Median of the Transformer_Space variable 

gen Median_Transformer_Space = Transformer_Space

gen Mean_Transformer_Space = Transformer_Space

** Create a variable that adds up the Violation KWhs 

gen Violation_KWhs = Violation*Transformer_Space

sort  treatment2  date hour_start  		

** Post-Treatment Flag 

gen Post_Treatment_Flag = 0 
replace Post_Treatment_Flag = 1 if date >= td(05jul2023)

** Descriptive stats

sum Violation_KWhs if group == "C" & Post_Treatment_Flag == 0 
sum Violation_KWhs if group == "C" & Post_Treatment_Flag == 1 

sum Violation_KWhs if group == "M" & Post_Treatment_Flag == 0 
sum Violation_KWhs if group == "M" & Post_Treatment_Flag == 1 

sum Violation_KWhs if group == "T" & Post_Treatment_Flag == 0 
sum Violation_KWhs if group == "T" & Post_Treatment_Flag == 1 

hist Violation_KWhs if group == "C" & Post_Treatment_Flag == 0  &  Violation_KWhs < 0 
hist Violation_KWhs if group == "C" & Post_Treatment_Flag == 1  &  Violation_KWhs < 0 

hist Violation_KWhs if group == "T" & Post_Treatment_Flag == 0  &  Violation_KWhs < 0 
hist Violation_KWhs if group == "T" & Post_Treatment_Flag == 1  &  Violation_KWhs < 0 

** Collapse down to group - hour - pre and post-treatment  

collapse (mean) Violation ones Violation_KWhs,  by(group Post_Treatment_Flag hour_start)

drop ones 

rename Violation Violation_alt
rename Violation_KWhs Violation_KWhs_alt

** Merge in data file from main analysis to compare violations 

merge 1:1 group Post_Treatment_Flag hour_start using "$data/Violations_Descriptive_Plots_Data.dta"		

drop _m 

sum Violation_KWhs_alt Violation_KWhs if group == "C" & Post_Treatment_Flag == 0 
sum Violation_KWhs_alt Violation_KWhs if group == "C" & Post_Treatment_Flag == 1 

sum Violation_KWhs_alt Violation_KWhs if group == "T" & Post_Treatment_Flag == 0 
sum Violation_KWhs_alt Violation_KWhs if group == "T" & Post_Treatment_Flag == 1

sum Violation_KWhs_alt Violation_KWhs if group == "M" & Post_Treatment_Flag == 0 
sum Violation_KWhs_alt Violation_KWhs if group == "M" & Post_Treatment_Flag == 1
		
**************************
** Plot of Violation KWhs - Average violation kWhs at the day-group-hour for both pre and post 
**************************	

replace Violation_KWhs_alt = -1*Violation_KWhs_alt

replace Violation_KWhs = -1*Violation_KWhs

** Managed (Verify the results are identical)

twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs_alt hour_start if group == "M" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "M" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Managed") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Pre-Treatment" 5 "Post-Treatment") cols(2) ) 
							
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "M" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "M" & Post_Treatment_Flag == 0,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Pre-Treatment") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Baseline" 5 "Alternative") cols(2) ) 
							
														
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "M" & Post_Treatment_Flag == 1, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "M" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Post-Treatment") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Baseline" 5 "Alternative") cols(2) ) 
							
													
** TOU 						
							
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs_alt hour_start if group == "T" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "T" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("TOU") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Pre-Treatment" 5 "Post-Treatment") cols(2) ) 
							
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "T" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "T" & Post_Treatment_Flag == 0,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Pre-Treatment") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Baseline" 5 "Alternative 1") cols(2) )  name(TOU_Pre ,replace) 
							
														
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "T" & Post_Treatment_Flag == 1, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "T" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Post-Treatment") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Baseline" 5 "Alternative 1") cols(2) )  name(TOU_Post ,replace) 
					  

grc1leg TOU_Pre TOU_Post , cols(1)  graphregion(color(white) ) name(grc1leggraph ,replace)
gr draw grc1leggraph,  ysize(4.5) xsize(2.5)						  
					
graph export "$results/FigureC4b.pdf", replace 					
					
					
** Control 						
							
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs_alt hour_start if group == "C" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "C" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Control") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Pre-Treatment" 5 "Post-Treatment") cols(2) ) 
							
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "C" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "C" & Post_Treatment_Flag == 0,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Pre-Treatment") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Baseline" 5 "Alternative 1") cols(2) )  name(Control_Pre ,replace) 
							
														
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "C" & Post_Treatment_Flag == 1, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs_alt hour_start if group == "C" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Post-Treatment") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Baseline" 5 "Alternative 1") cols(2) ) name(Control_Post ,replace) 
					  

grc1leg Control_Pre Control_Post , cols(1)  graphregion(color(white) ) name(grc1leggraph ,replace)
gr draw grc1leggraph,  ysize(4.5) xsize(2.5)					

graph export "$results/FigureC4a.pdf", replace 	  
					  
restore 


********************************************************************************
********************************************************************************
** Step 3: Transformer-Level: Regression Analysis 
********************************************************************************
********************************************************************************

 
** Building off of the panel above 

preserve 

** Collapse to the transformer-day-hour level, summing up the amount charged at home 

collapse (max) evloadlimit_adj_alt    EV_Count_alt   (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment2 date hour_start)

** Create time-based controls 

gen off_peak = 0 
replace off_peak = 1 if hour_start >= 10 & hour_start <= 13
replace off_peak = 1 if hour_start >= 22
replace off_peak = 1 if hour_start >= 0 & hour_start <= 5

** Encode treatment group and transfomer grouping 

encode group, gen(group_num)

encode treatment2, gen(transformer_group)

** Post-Treatment Flag 

gen Post_Treat = 0 
replace Post_Treat = 1 if date >= td(05Jul2023) 

** Group-specific variable

gen TOU_group = 0 
replace TOU_group = 1 if group == "T"

gen Control_group = 0 
replace Control_group = 1 if group == "C"

gen Managed_group = 0 
replace Managed_group = 1 if group == "M"

** Group - Post variables 

gen TOU_Post = TOU_group*Post_Treat 

gen Managed_Post = Managed_group*Post_Treat 


********************************************************************************
** Dependent Variable: Violation KWhs  
********************************************************************************

** Construct Violation Kwhs Variable - Include measure adjusted by attrition 

gen Transformer_Space_adj = evloadlimit_adj_alt - kWh_added_hour_home

gen Violation_KWhs_adj = 0 
replace Violation_KWhs_adj = -1*Transformer_Space_adj if Transformer_Space_adj < 0 

********
** Group by Post-Treatment Interactions - Off-Peak Interaction 
********

** Adjusted Measure - Pooled all groups 

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
		
** TOU Treatment Effects 
		
xlincom  1.TOU_group#1.Post_Treat	

xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak	
		


*********
** Clustering: Transformer level with wild bootstrap 
** Works after reghdfe only if there is a single FE in absorb
** Manually do the FEs in the regression with factor variables 
** Note. Marginal effects are consistent to the main specification with these FEs in absorb 
** Reference (boottest): https://www.econ.queensu.ca/sites/econ.queensu.ca/files/qed_wp_1406.pdf 
*********		

** ssc install boottest


** Adjusted Measure - Only run on TOU and Control 
** TOU Treatment Effects 

quietly reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
								i.transformer_group i.hour_start if group != "M" ///
        , absorb(date) vce(robust)
		
		
xlincom  1.TOU_group#1.Post_Treat, post	
matrix b = e(b)
scalar viol_tou_alt1_coeff = b[1,1]		

quietly reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
								i.transformer_group i.hour_start if group != "M" ///
        , absorb(date) vce(robust)
boottest 1.TOU_group#1.Post_Treat = 0 , reps (9999) seed(12345) nograph cluster(transformer_group)
matrix ci_viol_tou_alt1 = r(CI)
scalar ll_viol_tou_alt1 = ci_viol_tou_alt1[1,1]
scalar ul_viol_tou_alt1 = ci_viol_tou_alt1[1,2]
scalar pval_viol_tou_alt1 = r(p)
	
quietly reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
								i.transformer_group i.hour_start if group != "M" ///
        , absorb(date) vce(robust)
xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak, post	
matrix b = e(b)
scalar viol_tou_offp_alt1_coeff = b[1,1]
	
quietly reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
								i.transformer_group i.hour_start if group != "M" ///
        , absorb(date) vce(robust)
boottest 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak  = 0 , reps (9999) seed(12345) nograph cluster(transformer_group)
matrix ci_viol_tou_offp_alt1 = r(CI)
scalar ll_viol_tou_offp_alt1 = ci_viol_tou_offp_alt1[1,1]
scalar ul_viol_tou_offp_alt1 = ci_viol_tou_offp_alt1[1,2]
scalar pval_viol_tou_offp_alt1 = r(p)

scalar obs1 = e(N)

* export results to create Table C5

scalar viol_tou_alt1_coeff = round(viol_tou_alt1_coeff, 0.001)
scalar viol_tou_offp_alt1_coeff = round(viol_tou_offp_alt1_coeff, 0.001)
scalar ci_viol_tou_alt1 = "[" + string(matrix(ll_viol_tou_alt1), "%9.3f") + "," + string(matrix(ul_viol_tou_alt1), "%9.3f") + "]"
scalar ci_viol_tou_offp_alt1 = "[" + string(matrix(ll_viol_tou_offp_alt1), "%9.3f") + "," + string(matrix(ul_viol_tou_offp_alt1), "%9.3f") + "]"
scalar pval_viol_tou_alt1 = round(pval_viol_tou_alt1, 0.001)
scalar pval_viol_tou_offp_alt1 = round(pval_viol_tou_offp_alt1, 0.001)
scalar pval_viol_tou_alt1 = "(" + string(pval_viol_tou_alt1, "%9.3f") + ")"
scalar pval_viol_tou_offp_alt1 = "(" + string(pval_viol_tou_offp_alt1, "%9.3f") + ")"

putexcel set "$results/Table C5.xlsx", modify

putexcel D2 = viol_tou_alt1_coeff
putexcel D3 = pval_viol_tou_alt1
putexcel D4 = ci_viol_tou_alt1

putexcel D5 = viol_tou_offp_alt1_coeff
putexcel D6 = pval_viol_tou_offp_alt1	
putexcel D7 = ci_viol_tou_offp_alt1

putexcel D8 = obs1
		
restore 



