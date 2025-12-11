********************************************************************************
********************************************************************************
******************* Attrition Simulation - Robustness  *************************
********************************************************************************
********************************************************************************

// SET DIRECTORY

global statapath "Insert Directory"
global data "$statapath/Data"
global panel "$statapath/Data/Panel"
global results "$statapath/Results"
global fortisdata "$statapath/Data/Fortis Data"

********************************************************************************
** Create a list of attritted EVs
********************************************************************************

use "$data/treatment group assignment.dta", clear 

merge 1:1 vehicle_id using "$data/vehicle_data_analysis.dta"

drop if _m == 2 

drop _m 

keep vehicle_id home_id treatment group transformer unenroll_date unenrolled_reason

sort treatment 

drop if treatment == "C8"

keep if unenroll_date != .

** Focus on EVs that unenrolled over the relevant time period 

keep if unenroll_date < td(13Dec2023)

tempfile unenrolled_list
save `unenrolled_list'


********************************************************************************
** Characterize the "average" Control household 
** Construct the panel data set used in regression analysis
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

** Drop C8 control group - non-controllable EVs 

drop if treatment == "C8"


*******
** For each hour of the sample, construct the average at-home charging profile of Control EVs 
*******

keep if group == "C"

sort date hour_start 

preserve 

** Randomly select at Control EV for each day of the sample ==> Get a broad representation of the Control group 

gen ones = 1 

collapse (max) ones, by(vehicle_id date)

set seed 123

gen random_num = runiform(0, 1)

sort date random_num

bysort date (random_num): gen Unenrolled_EV_Count = sum(ones)
 
keep if Unenrolled_EV_Count <= 32

keep vehicle_id date Unenrolled_EV_Count

tempfile random_Control 
save `random_Control'

restore 

** Merge with broader set of control EVs 
** keep only the matched car 

merge m:1 vehicle_id date using `random_Control' 

keep if _m == 3 

drop _m 

hist kWh_added_hour_home , graphregion(fcolor(white))

hist kWh_added_hour_home if kWh_added_hour_home > 0 , graphregion(fcolor(white))

sort date hour_start Unenrolled_EV_Count

keep date hour_start Unenrolled_EV_Count kWh_added_hour_home

tempfile avg_control 
save `avg_control'

********************************************************************************
** Construct a panel for EVs that unenrolled 
** Assign average control profile post-exit 
********************************************************************************

use `unenrolled_list', clear 

sort vehicle_id

gen ones = 1 

gen Unenrolled_EV_Count = sum(ones)

drop ones 

** Merge in the vehicle template file 
** Focus only on matched EVs (that eventually left)

merge 1:m vehicle_id using "$data/Daily_Template_Analysis.dta"

drop if _m ==2 

drop _m 

sort vehicle_id date 

** Focus only on sample period (Apr 1, 2023 to Dec 13, 2023)

drop if date < td(01Apr2023)
drop if date > td(13Dec2023)

** Only include data starting the day of unenrollment 

keep if date >= unenroll_date

** Expand data to the hourly level 

expand 24

gen ones = 1 

sort vehicle_id date 

bysort vehicle_id date: gen hour_start = sum(ones)

replace hour_start = hour_start - 1 

drop ones 

** Merge in the average control charging kWh at home 

merge m:1 date hour_start Unenrolled_EV_Count using `avg_control'

drop if _m == 2 

drop _m 

sort vehicle_id date hour_start

** Save file to append to main Panel analysis file 

tempfile Attrition_Charging_Data 
save `Attrition_Charging_Data'

********************************************************************************
** Recreate Main Analysis - replace attrited households with "average control"
** Rerun results 
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
** Append charging data for attritted EVs 
*******

append using `Attrition_Charging_Data'

*******
** Remove days with "DR Events"
*******

drop if date == td(11aug2023)
drop if date == td(12aug2023)
drop if date == td(28aug2023)
drop if date == td(22nov2023)
 
 
preserve 

********************************************************************************
********************************************************************************
** EV-Level: Regression Analysis 
********************************************************************************
********************************************************************************

** Create time-based controls 

gen year = year(date)

gen month = month(date)

gen day = day(date)

egen year_month = group(year month)

gen dow = dow( mdy( month, day, year) )

egen hour_sample = group(date hour_start)

gen off_peak = 0 
replace off_peak = 1 if hour_start >= 10 & hour_start <= 13
replace off_peak = 1 if hour_start >= 22
replace off_peak = 1 if hour_start >= 0 & hour_start <= 5

** Encode treatment group 

encode group, gen(group_num)

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

** Create a dependent variable that is 0-1 if the EV has charged at all 

gen charge_dummy = 0 
replace charge_dummy = 1 if kWh_added_hour_home > 0 

** Create a new ID that is unique for each EV in Control and TOU, but the same for all EVs within a given Managed transformer 

gen cluster_var = . 
replace cluster_var = vehicle_id if group == "C" | group == "T"

replace cluster_var = 1 if treatment == "M1"
replace cluster_var = 2 if treatment == "M2"
replace cluster_var = 3 if treatment == "M3"
replace cluster_var = 4 if treatment == "M4"
replace cluster_var = 5 if treatment == "M5"
replace cluster_var = 6 if treatment == "M6"
replace cluster_var = 7 if treatment == "M7"

egen group_cluster = group(cluster_var)

************
** DID with heterogeneous effects by off-peak  
************
		
** Charge KWHs 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
		
** TOU marginal effect 

xlincom  1.TOU_group#1.Post_Treat,post
est store kwh_tou_post 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak, post 
est store kwh_tou_post_offp

	
** Managed marginal effect 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
xlincom  1.Managed_group#1.Post_Treat, post
est store kwh_man_post  

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
xlincom  1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak, post
est store kwh_man_post_offp
 
 
** Test for differences across TOU and Managed 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
xlincom 1.TOU_group#1.Post_Treat - 1.Managed_group#1.Post_Treat, post
est store kwh_tou_man_post

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
test 1.TOU_group#1.Post_Treat = 1.Managed_group#1.Post_Treat	

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
xlincom 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak   - (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak), post
est store kwh_tou_man_post_offp
		
quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
test 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak   = (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )	
	

restore 

preserve 
 
********************************************************************************
********************************************************************************
** Transformer-Level: Regression Analysis 
********************************************************************************
********************************************************************************

** Collapse to the transformer-day-hour level, summing up the amount charged at home 

collapse (max) transformer evloadlimit  evloadlimit_adj  EV_Count_on  (firstnm) group (sum) kWh_added_hour_home , by(treatment date hour_start)

** Create time-based controls 

gen year = year(date)

gen month = month(date)

gen day = day(date)

egen year_month = group(year month)

gen dow = dow( mdy( month, day, year) )

gen off_peak = 0 
replace off_peak = 1 if hour_start >= 10 & hour_start <= 13
replace off_peak = 1 if hour_start >= 22
replace off_peak = 1 if hour_start >= 0 & hour_start <= 5

** Encode treatment group and transfomer grouping 

encode group, gen(group_num)

encode treatment, gen(transformer_group)

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
** Replace evloadlimit with evloadlimit_adj prior to July 1, 2023 
** Accounts for the fact that we have an unbalanced panel pre-treatment with EVs coming online after April 1, 2023
** evloadlimit_adj builds this in, but it also builds in attrition (which we do not want to consider here post-treatment ==> only replace pre July)

replace evloadlimit = evloadlimit_adj if date < td(01Jul2023)

gen Transformer_Space = evloadlimit - kWh_added_hour_home

gen Violation_KWhs = 0 
replace Violation_KWhs = -1*Transformer_Space if Transformer_Space < 0 


********
** Group by Post-Treatment Interactions - Off-Peak Interaction 
********

** Adjusted Measure - with additional fixed effects 

quietly reghdfe Violation_KWhs ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
						
** TOU marginal effect 

xlincom  1.TOU_group#1.Post_Treat, post
est store viol_tou_post 

quietly reghdfe Violation_KWhs ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak, post 
est store viol_tou_post_offp 
	
** Managed marginal effect 

quietly reghdfe Violation_KWhs ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
xlincom  1.Managed_group#1.Post_Treat, post
est store viol_man_post 
 
quietly reghdfe Violation_KWhs ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
xlincom  1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak, post 
est store viol_man_post_offp 

** Test for differences across TOU and Managed 

quietly reghdfe Violation_KWhs ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
xlincom 1.TOU_group#1.Post_Treat - 1.Managed_group#1.Post_Treat, post
est store viol_tou_man_post 

quietly reghdfe Violation_KWhs ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
test 1.TOU_group#1.Post_Treat = 1.Managed_group#1.Post_Treat	

quietly reghdfe Violation_KWhs ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
xlincom 	 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak - (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak ), post
est store viol_tou_man_post_offp 
		
quietly reghdfe Violation_KWhs ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
test 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak = (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak)	

restore 

* Create results output


esttab kwh_tou_post viol_tou_post using "$results/Table B2.csv", noobs rename(lc_1 "TOU Peak") ///
cells(b(fmt(3)) se(par fmt(3))) title("Table B2. Estimated Treatment Effects by Group - Attrition Robust") ///
collabels(,none) mtitles("Charge kWh" "Constraint Violations") replace

esttab kwh_tou_post_offp viol_tou_post_offp using "$results/Table B2.csv", noobs rename(lc_1 "TOU Off-Peak") ///
cells(b(fmt(3)) se(par fmt(3))) collabels(,none) mlabels(,none) nonumbers append

esttab kwh_man_post viol_man_post using "$results/Table B2.csv", noobs rename(lc_1 "Managed Peak") ///
cells(b(fmt(3)) se(par fmt(3))) collabels(,none) mlabels(,none) nonumbers append

esttab kwh_man_post_offp viol_man_post_offp using "$results/Table B2.csv", noobs rename(lc_1 "Managed Off-Peak") ///
cells(b(fmt(3)) se(par fmt(3))) collabels(,none) mlabels(,none) nonumbers addnotes("") append

esttab kwh_tou_man_post viol_tou_man_post using "$results/Table B2.csv", cells(b(fmt(3)) p(par fmt(3))) ///
noobs title("Treatment Effect Comparison") rename(lc_1 "TOU-Managed Peak (p-value)") collabels(,none) mlabels(,none) nonumbers append

esttab kwh_tou_man_post_offp viol_tou_man_post_offp using "$results/Table B2.csv", cells(b(fmt(3)) p(par fmt(3))) ///
rename(lc_1 "TOU-Managed Off-Peak (p-value)") collabels(,none) mlabels(,none) nonumbers ///
addnotes("This table provides the estimated treatment effects using at-home charging only." ///
"All specifications include fixed effects at the day-of-sample and hour-of-day level." ///
"The Column 1 specification includes EV-level fixed effects." /// 
"The Column 2 includes transformer-level fixed effects." ///
"Standard errors in parentheses in Column 1 are clustered at the transformer level for vehicles assigned to Managed and the EV-level for vehicles assigned to Control and TOU." ///
"Standard errors in Column 2 are clustered at the transformer level." ///
"Treatment Effect Comparison compares the treatment effects for TOU and Managed by Peak and Off-Peak with p-values reported in the parentheses for the Wald tests" "") append



