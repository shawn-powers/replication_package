********************************************************************************
********************************************************************************
************************** Extensive Margin Analysis  **************************
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
** Construct a panel data set to do Extensive Margin analysis 
********************************************************************************
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
** Merge in transformer limits file - necessary to understand the "room" available on each transformer 
*******

** Merge by treatment group and time 

merge m:1 treatment time using "$data/group limits_Adjusted.dta"

** _m == 2 are hours that are either before our sample or after the data ends 

drop if _m == 2 

drop _m  datetime hour
 
sort vehicle_id time

*******
** Create charging variables
*******

gen kWh_added_hour_home = 0 
replace kWh_added_hour_home = kWh_added_hour if location == 0 

gen charging=0
replace charging=1 if kWh_added_hour>0


*******
** Drop observations for EVs that unenrolled (in the data template file)
** Otherwise, we are assigning zero charge to these EVs when they unenrolled 
*******

drop if date >= unenroll_date & unenroll_date != . 

*******
** Remove days with "DR Events"
*******

drop if date == td(11aug2023)
drop if date == td(12aug2023)
drop if date == td(28aug2023)
drop if date == td(22nov2023)

*******
** Clean up data set 
*******

** Drop 14 non-controllable EVs in transformer C8 

drop if treatment == "C8"

** Define a day to be between 9:00 AM and 8:00 AM hour_start the following day 

sort vehicle_id date hour_start 

gen Time_9AM_flag = 0
replace Time_9AM_flag = 1 if hour_start == 9 

bysort vehicle_id (date hour_start ): gen Electricity_Day_Flag = sum(Time_9AM_flag)

** Post-Treatment Flag 

gen Post_Treatment_Flag = 0 
replace Post_Treatment_Flag = 1 if date >= td(05jul2023)

order vehicle_id treatment group transformer date time hour_start kWh_added_hour kWh_added_hour_home Electricity_Day_Flag Post_Treatment_Flag

**************************************
** Table C1 - Extensive Margin Analysis
**************************************

** Setup table

putexcel set "$results/Table C1.xlsx", sheet("Extensive Margin Analysis", replace) replace 

putexcel B1 = "Charging Indicator"
putexcel B2 = "Home-Only"
putexcel C2 = "Home and Away"

putexcel E1 = "Charging kWh"
putexcel E2 = "Home-Only"
putexcel F2 = "Home and Away"

putexcel A3 = "TOU × Post"
putexcel A5 = "Managed × Post"
putexcel A7 = "Observations"

**************************************
** Charging Indicator
**************************************

preserve

** Data preparation

** Charging amounts on each electric day by vehicle_id: 1- Charging (home or away), 2- Home Charging

* 1- Charging 

bys vehicle_id Electricity_Day_Flag: egen ed_tot_charging=total(kWh_added_hour)

* 2- Home Charging

bys vehicle_id Electricity_Day_Flag: egen ed_home_charging=total(kWh_added_hour) if location==0

		replace ed_home_charging=0 if ed_home_charging==.
		
		bys vehicle_id Electricity_Day_Flag: egen temp=max(ed_home_charging)
		
		replace ed_home_charging=temp
		
		drop temp
	
** Indexing charging days: 1- Charging (home or away) and 2- Home Charging

* 1- Charging

gen ed_chrging_ind=0
bys vehicle_id Electricity_Day_Flag: replace ed_chrging_ind=1 if ed_tot_charging>0

* 2- Home Charging

gen ed_chrging_home_ind=0
bys vehicle_id Electricity_Day_Flag: replace ed_chrging_home_ind=1 if ed_home_charging>0


** Collapse data: keep vehicle and electricity day level information

collapse (firstnm) treatment group transformer min_time profile_id home_id make model car_year unenrolled_reason deleted_vehicle_reason unenroll_date EV_Count (min) date Post_Treatment (max) ed_tot_charging ed_home_charging ed_chrging_ind ed_chrging_home_ind, by(vehicle_id Electricity_Day_Flag)


** Creating calendar variables

gen month = month(date)
	
gen dow=dow(date)

** Encode treatment group 

encode group, gen(group_num)

** Group-specific variable

gen TOU_group = 0 
replace TOU_group = 1 if group == "T"

gen Control_group = 0 
replace Control_group = 1 if group == "C"

gen Managed_group = 0 
replace Managed_group = 1 if group == "M"

** Group - Post variables 

gen TOU_Post = TOU_group*Post_Treatment 

gen Managed_Post = Managed_group*Post_Treatment 

** Regression Results:

reghdfe ed_chrging_home_ind ib0.TOU_Post  ib0.Managed_Post  , absorb(date vehicle_id )  vce(cluster vehicle_id)

*reghdfe ed_chrging_home_ind ib0.TOU_group##ib0.Post_Treat  ib0.Managed_group##ib0.Post_Treat  /// 
*       , absorb(date vehicle_id) vce(cluster vehicle_id)

matrix list r(table)

scalar coef1 =  r(table)[1,2]
putexcel B3=coef1, nformat(#.000)

scalar coef2 =  r(table)[1,4]
putexcel B5=coef2, nformat(#.000)

scalar sd1 =  r(table)[2,2]
putexcel B4=sd1, nformat(#.000)

scalar sd2 =  r(table)[2,4]
putexcel B6=sd2, nformat(#.000)

scalar n1 =  e(N)
putexcel B7=n1



reghdfe ed_chrging_ind ib0.TOU_Post ib0.Managed_Post, absorb(date vehicle_id)  vce(cluster vehicle_id)

*reghdfe ed_chrging_ind ib0.TOU_group##ib0.Post_Treat  ib0.Managed_group##ib0.Post_Treat  /// 
*       , absorb(date vehicle_id) vce(cluster vehicle_id)


matrix list r(table)

scalar coef1 =  r(table)[1,2]
putexcel C3=coef1, nformat(#.000)

scalar coef2 =  r(table)[1,4]
putexcel C5=coef2, nformat(#.000)

scalar sd1 =  r(table)[2,2]
putexcel C4=sd1, nformat(#.000)

scalar sd2 =  r(table)[2,4]
putexcel C6=sd2, nformat(#.000)

scalar n1 =  e(N)
putexcel C7=n1

restore

**************************************
** Charging kWh
**************************************

preserve 

** Data preparation

** Charging amounts on each electric day by vehicle_id: 1- Charging (home or away), 2- Home Charging

* 1- Charging 

bys vehicle_id Electricity_Day_Flag: egen ed_tot_charging=total(kWh_added_hour)

* 2- Home Charging

bys vehicle_id Electricity_Day_Flag: egen ed_home_charging=total(kWh_added_hour) if location==0

		replace ed_home_charging=0 if ed_home_charging==.
		
		bys vehicle_id Electricity_Day_Flag: egen temp=max(ed_home_charging)
		
		replace ed_home_charging=temp
		
		drop temp
		
** Collapse data: keep vehicle and electricity day level information

collapse (firstnm) treatment group transformer min_time profile_id home_id make model car_year unenrolled_reason deleted_vehicle_reason unenroll_date EV_Count (min) date Post_Treatment (max) ed_tot_charging ed_home_charging , by(vehicle_id Electricity_Day_Flag)

**************************************

** Creating calendar variables

gen month = month(date)
	
gen dow=dow(date)

** Encode treatment group 

encode group, gen(group_num)

** Group-specific variable

gen TOU_group = 0 
replace TOU_group = 1 if group == "T"

gen Control_group = 0 
replace Control_group = 1 if group == "C"

gen Managed_group = 0 
replace Managed_group = 1 if group == "M"

** Group - Post variables 

gen TOU_Post = TOU_group*Post_Treatment 

gen Managed_Post = Managed_group*Post_Treatment 


** Regressions:

reghdfe ed_home_charging ib0.TOU_Post  ib0.Managed_Post  , absorb(date vehicle_id)  vce(cluster vehicle_id)

*reghdfe ed_home_charging ib0.TOU_group##ib0.Post_Treat  ib0.Managed_group##ib0.Post_Treat  /// 
*        , absorb(date vehicle_id) vce(cluster vehicle_id)

matrix list r(table)

scalar coef1 =  r(table)[1,2]
putexcel E3=coef1, nformat(#.000)

scalar coef2 =  r(table)[1,4]
putexcel E5=coef2, nformat(#.000)

scalar sd1 =  r(table)[2,2]
putexcel E4=sd1, nformat(#.000)

scalar sd2 =  r(table)[2,4]
putexcel E6=sd2, nformat(#.000)

scalar n1 =  e(N)
putexcel E7=n1


reghdfe ed_tot_charging ib0.TOU_Post ib0.Managed_Post  , absorb(date vehicle_id )  vce(cluster vehicle_id)

*reghdfe ed_tot_charging ib0.TOU_group##ib0.Post_Treat  ib0.Managed_group##ib0.Post_Treat  /// 
*        , absorb(date vehicle_id) vce(cluster vehicle_id)
		

matrix list r(table)

scalar coef1 =  r(table)[1,2]
putexcel F3=coef1, nformat(#.000)

scalar coef2 =  r(table)[1,4]
putexcel F5=coef2, nformat(#.000)

scalar sd1 =  r(table)[2,2]
putexcel F4=sd1, nformat(#.000)

scalar sd2 =  r(table)[2,4]
putexcel F6=sd2, nformat(#.000)

scalar n1 =  e(N)
putexcel F7=n1

restore
