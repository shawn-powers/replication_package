********************************************************************************
********************************************************************************
*************************** Balance Analysis  **********************************
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
********************************************************************************

** Metrics to use to evaluate balanec
* 1. off-peak charging share (need interval data)
* 2. home share of charging (session data)
* 3. daily charge duration (minutes) (session data, home)
* 4. total kWh charged per day (session data, home)
* 5. max rate of home charge (kW) (session data, home)
* 6. charger type (L1,L2,L3)
* 7. average number of sessions per day (session data)
* 8. Tesla/non-Tesla (vehicle data)

********************************************************************************
********************************************************************************

****
** Understand when the majority of EVs assigned to groups were in our sample 
****

use "$panel/panel_hourly_analysis.dta", clear 

bysort vehicle_id: egen min_date = min(date)

format min_date %td 

collapse (max) min_date, by(vehicle_id)

** Merge in Group Assignments 

merge m:1 vehicle_id using "$data/treatment group assignment.dta"

keep if _m == 3 

drop _m 

** drop group C8

drop if treatment == "C8"

sort min_date 

gen ones = 1 

gen sum_ones = sum(ones)

** Vast majority are on the App by April 1 (85%)
twoway line sum_ones min_date if min_date >= td(01Dec2022)

** Present the results as a cumulative percentage 

gen cumul_percentage = sum_ones/202

display td(01Jan2023)

display td(01Apr2023)

twoway line cumul_percentage min_date if min_date >= td(01Dec2022), ///
			xline(23026) xline(23101) yscale(r(0 1)) ylabel(0(0.20)1) ///
			xtitle("") ytitle("Percentage") xlabel(22980 23011 23042 23070 23101 23131 23162, format(%tdmy)) ///
			text(0.98 23027 "Jan 16, 2023", place(e)) ///
			text(0.98 23102 "Apr 1, 2023", place(e))

** Calculate the number of days on the App 

display td(05July2023)

gen num_days = 23196 - min_date

sum num_days if group == "M", detail
sum num_days if group == "T", detail
sum num_days if group == "C", detail

** Do a formal ttest 

gen Group_M_C = . 
replace Group_M_C = 1 if group == "M"
replace Group_M_C = 2 if group == "C"

ttest num_days, by(Group_M_C) unequal

gen Group_M_T = . 
replace Group_M_T = 1 if group == "M"
replace Group_M_T = 2 if group == "T"


ttest num_days, by(Group_M_T) unequal

gen Group_T_C = . 
replace Group_T_C = 1 if group == "T"
replace Group_T_C = 2 if group == "C"

ttest num_days, by(Group_T_C) unequal

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
* 6. Tesla/non-Tesla (vehicle data)
********

use "$data/vehicle_data_analysis.dta", clear 

gen tesla_type = 0 
replace tesla_type = 1 if make == "tesla"

keep vehicle_id tesla_type est_battery_range_miles year

** Store 

tempfile Tesla_type
save `Tesla_type'

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

merge 1:1 vehicle_id using `Tesla_type'

drop _m 

** Merge in treatment assignments 

merge 1:1 vehicle_id using "$data/treatment group assignment.dta"

keep if _m == 3 

drop _m

tempfile Combined_Date
save `Combined_Date'


********************************************************************************
** Build Summary Stats Table 1 - Balance Pre-Treatment 
** Removing Non-Controllable EVs and the 1 EV at a non-controllable home 
********************************************************************************

** encode group assignment 

encode group, gen(GroupAssignment)

** Drop group C8 - non-controllable EVs 

drop if treatment == "C8"

** Save as an excel file 
putexcel set "$results/Table 1.xlsx", sheet("Balance", replace) replace 

putexcel A1 = "Variable"

putexcel B1 = "Control"
putexcel C1 = "TOU"
putexcel D1 = "Managed"

putexcel E1 = "ANOVA (p-value)"

putexcel A2 = "Home Share"
putexcel A4 = "Charge Duration (Minutes)"
putexcel A6 = "Energy Charged (kWh)"

putexcel A8 = "Max KW Charge (Power)"
putexcel A10 = "Off-Peak Share (%)"
putexcel A12 = "Off-Peak Share (%) - Home Only"
putexcel A14 = "Tesla (%)"
putexcel A16 = "Number of EVs"
putexcel A17 = "Number of Virtual Transfomers"

**********
** Home Share
**********

sum home_share if group == "C"

scalar mean_control = r(mean)
scalar sd_control = r(sd)

putexcel B2 = mean_control, nformat(#.00)
putexcel B3 = sd_control, nformat(#.00)

sum home_share if group == "T"

scalar mean_tou = r(mean)
scalar sd_tou = r(sd)

putexcel C2 = mean_tou, nformat(#.00)
putexcel C3 = sd_tou, nformat(#.00)

sum home_share if group == "M"

scalar mean_managed = r(mean)
scalar sd_managed = r(sd)

putexcel D2 = mean_managed, nformat(#.00)
putexcel D3 = sd_managed, nformat(#.00)

anova home_share GroupAssignment  

scalar Fanova = e(F)
scalar Fpval =  Ftail(e(df_m),e(df_r),e(F))

putexcel E2 = Fpval, nformat(#.00)


**********
** Minutes
**********

sum daily_duration_minutes if group == "C"

scalar mean_control = r(mean)
scalar sd_control = r(sd)

putexcel B4 = mean_control, nformat(#.00)
putexcel B5 = sd_control, nformat(#.00)

sum daily_duration_minutes if group == "T"

scalar mean_tou = r(mean)
scalar sd_tou = r(sd)

putexcel C4 = mean_tou, nformat(#.00)
putexcel C5 = sd_tou, nformat(#.00)

sum daily_duration_minutes if group == "M"

scalar mean_managed = r(mean)
scalar sd_managed = r(sd)

putexcel D4 = mean_managed, nformat(#.00)
putexcel D5 = sd_managed, nformat(#.00)

anova daily_duration_minutes GroupAssignment  

scalar Fanova = e(F)
scalar Fpval =  Ftail(e(df_m),e(df_r),e(F))

putexcel E4 = Fpval, nformat(#.00)


**********
** KWh
**********

sum total_KWhs_charged if group == "C"

scalar mean_control = r(mean)
scalar sd_control = r(sd)

putexcel B6 = mean_control, nformat(#.00)
putexcel B7 = sd_control, nformat(#.00)

sum total_KWhs_charged if group == "T"

scalar mean_tou = r(mean)
scalar sd_tou = r(sd)

putexcel C6 = mean_tou, nformat(#.00)
putexcel C7 = sd_tou, nformat(#.00)

sum total_KWhs_charged if group == "M"

scalar mean_managed = r(mean)
scalar sd_managed = r(sd)

putexcel D6 = mean_managed, nformat(#.00)
putexcel D7 = sd_managed, nformat(#.00)

anova total_KWhs_charged GroupAssignment  

scalar Fanova = e(F)
scalar Fpval =  Ftail(e(df_m),e(df_r),e(F))

putexcel E6 = Fpval, nformat(#.00)

**********
** Power
**********

sum max_power if group == "C"

scalar mean_control = r(mean)
scalar sd_control = r(sd)

putexcel B8 = mean_control, nformat(#.00)
putexcel B9 = sd_control, nformat(#.00)

sum max_power if group == "T"

scalar mean_tou = r(mean)
scalar sd_tou = r(sd)

putexcel C8 = mean_tou, nformat(#.00)
putexcel C9 = sd_tou, nformat(#.00)

sum max_power if group == "M"

scalar mean_managed = r(mean)
scalar sd_managed = r(sd)

putexcel D8 = mean_managed, nformat(#.00)
putexcel D9 = sd_managed, nformat(#.00)

anova max_power GroupAssignment  

scalar Fanova = e(F)
scalar Fpval =  Ftail(e(df_m),e(df_r),e(F))

putexcel E8 = Fpval, nformat(#.00)

**********
** Off-Peak Share - Home and Away 
**********

sum off_peak_share if group == "C"

scalar mean_control = r(mean)
scalar sd_control = r(sd)

putexcel B10 = mean_control, nformat(#.00)
putexcel B11 = sd_control, nformat(#.00)

sum off_peak_share if group == "T"

scalar mean_tou = r(mean)
scalar sd_tou = r(sd)

putexcel C10 = mean_tou, nformat(#.00)
putexcel C11 = sd_tou, nformat(#.00)

sum off_peak_share if group == "M"

scalar mean_managed = r(mean)
scalar sd_managed = r(sd)

putexcel D10 = mean_managed, nformat(#.00)
putexcel D11 = sd_managed, nformat(#.00)

anova off_peak_share GroupAssignment  

scalar Fanova = e(F)
scalar Fpval =  Ftail(e(df_m),e(df_r),e(F))

putexcel E10 = Fpval, nformat(#.00)


**********
** Off-Peak Share - Home only 
**********

sum off_peak_share_home if group == "C"

scalar mean_control = r(mean)
scalar sd_control = r(sd)

putexcel B12 = mean_control, nformat(#.00)
putexcel B13 = sd_control, nformat(#.00)

sum off_peak_share_home if group == "T"

scalar mean_tou = r(mean)
scalar sd_tou = r(sd)

putexcel C12 = mean_tou, nformat(#.00)
putexcel C13 = sd_tou, nformat(#.00)

sum off_peak_share_home if group == "M"

scalar mean_managed = r(mean)
scalar sd_managed = r(sd)

putexcel D12 = mean_managed, nformat(#.00)
putexcel D13 = sd_managed, nformat(#.00)

anova off_peak_share_home GroupAssignment  

scalar Fanova = e(F)
scalar Fpval =  Ftail(e(df_m),e(df_r),e(F))

putexcel E12 = Fpval, nformat(#.00)


**********
** Tesla 
**********

replace tesla_type = tesla_type*100 

sum tesla_type if group == "C"

scalar mean_control = r(mean)
scalar sd_control = r(sd)

putexcel B14 = mean_control, nformat(#.00)
putexcel B15 = sd_control, nformat(#.00)

sum tesla_type if group == "T"

scalar mean_tou = r(mean)
scalar sd_tou = r(sd)

putexcel C14 = mean_tou, nformat(#.00)
putexcel C15 = sd_tou, nformat(#.00)

sum tesla_type if group == "M"

scalar mean_managed = r(mean)
scalar sd_managed = r(sd)

putexcel D14 = mean_managed, nformat(#.00)
putexcel D15 = sd_managed, nformat(#.00)

anova tesla_type GroupAssignment  

scalar Fanova = e(F)
scalar Fpval =  Ftail(e(df_m),e(df_r),e(F))

putexcel E14 = Fpval, nformat(#.00)


**********
** Count 
**********

gen group_count = 1 

collapse (sum) group_count, by(group)

** Summarize values and store them

sum group_count if group == "C"

scalar mean_control = r(mean)

putexcel B16 = mean_control

sum group_count if group == "T"

scalar mean_tou = r(mean)

putexcel C16 = mean_tou

sum group_count if group == "M"

scalar mean_managed = r(mean)

putexcel D16 = mean_managed 
 
 
**********
** Number of Virtual Transformers  
**********

putexcel B17 = 7

putexcel C17 = 7

putexcel D17 = 7
 
 
 
********************************************************************************
* US Charging data prep
********************************************************************************
********************************************************************************

** Metrics to use to evaluate balanec
* 1. off-peak charging share (need interval data)
* 2. home share of charging (session data)
* 3. daily charge duration (minutes) (session data, home)
* 4. total kWh charged per day (session data, home)
* 5. max rate of home charge (kW) (session data, home)
* 6. Tesla/non-Tesla (vehicle data)

********************************************************************************
********************************************************************************

*******
* 1A. off-peak charging share (need interval data) - Home and Away 
*******

use "$data/Optiwatt US/charge_sessions_hourly_panel.dta", clear 

** Focus on data between April 1 and July 4th (pre-treatment)

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

** Flag hours as midday and evening off_peak 10 AM - 2 PM, 10 PM - 6 AM (hour start 22 - 5, 10 - 13)

order vehicle_id time date hour 

gen off_peak = 0 
replace off_peak = 1 if hour >= 22 | hour <= 5 
replace off_peak = 1 if hour >= 10 & hour <= 13

** Calculate the proportion of charging in the off_peak 

bysort vehicle_id: egen total_KWhs = sum(kwh_added)

gen off_peak_KWhs = off_peak*kwh_added

bysort vehicle_id: egen total_off_peak_KWhs = sum(off_peak_KWhs)

gen off_peak_share = 100*(total_off_peak_KWhs/total_KWhs)

** Collapse data and store 
collapse (max) off_peak_share (firstnm) plan_type, by(vehicle_id)

** Save as a temp file 

tempfile OffPeak_Share_vehicle
save `OffPeak_Share_vehicle'


*******
* 1B. off-peak charging share (need interval data) - Home Only 
*******

use "$data/Optiwatt US/charge_sessions_hourly_panel.dta", clear 


** Focus on data between April 1 and July 4th (pre-treatment)

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

gen location=0
replace location=1 if home_id==.
label var location "1 Away - 0 Home"
label define loc 0 "Home" 1 "Away"
label values location loc

** Flag hours as midday and evening off_peak 10 AM - 2 PM, 10 PM - 6 AM (hour start 22 - 5, 10 - 13)

order vehicle_id time date hour 

gen off_peak = 0 
replace off_peak = 1 if hour >= 22 | hour <= 5 
replace off_peak = 1 if hour >= 10 & hour <= 13

** Focus on at-home only 

keep if location == 0 

** Calculate the proportion of charging in the off_peak 

bysort vehicle_id: egen total_KWhs = sum(kwh_added)

gen off_peak_KWhs = off_peak*kwh_added

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

use "$data/Optiwatt US/charge_sessions_hourly_panel.dta", clear 

** Create a location variable 

gen location=0
replace location=1 if home_id==.
label var location "1 Away - 0 Home"
label define loc 0 "Home" 1 "Away"
label values location loc

** Focus on data between April 1 and July 4th (pre-treatment)

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

** Calculate the share of charging at home 

gen home_flag = 0 
replace home_flag = 1 if location == 0 

bysort vehicle_id: egen total_KWhs = sum(kwh_added)

gen kwh_added_home = kwh_added*home_flag

bysort vehicle_id: egen total_KWhs_home = sum(kwh_added_home)

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

use "$data/Optiwatt US/charge_sessions_hourly_panel.dta", clear 


** Focus on data between April 1 and July 4th (pre-treatment)

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

** Focus on at-home charging only 

gen location=0
replace location=1 if home_id==.
label var location "1 Away - 0 Home"
label define loc 0 "Home" 1 "Away"
label values location loc

keep if location == 0

 
** 3. daily charge duration (minutes) (session data, home)

bysort vehicle_id date: egen daily_duration_minutes = total(minutes_charged)

** 4. total kWh charged per day (session data, home)

bysort vehicle_id date: egen total_KWhs_charged = total(kwh_added)

** 5. max rate of home charge (kW) (session data, home)

gen power=(kwh_added)/(minutes_charged/60)
bysort vehicle_id date: egen max_power = max(power)

** Collapse data and store 
collapse (mean) daily_duration_minutes total_KWhs_charged max_power, by(vehicle_id)

tempfile Mins_KWhs_Power_vehicle
save `Mins_KWhs_Power_vehicle'

********
* 6. Tesla/non-Tesla (vehicle data)
********

use "$data/Optiwatt US/charge_sessions_hourly_panel.dta", clear 

keep if date >= td(01Apr2023)  

drop if date > td(04July2023)

gen tesla_type = 0 
replace tesla_type = 1 if make == "tesla"

keep vehicle_id tesla_type range model_year primary_city state

duplicates drop
** Store 

tempfile Tesla_type
save `Tesla_type'

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

merge 1:1 vehicle_id using `Tesla_type'

drop _m 

**

drop if home_share==0

gen fortis=0

rename model_year year 

save "$data/Optiwatt US/US_EVs.dta" , replace
 
********************************************************************************
** Create Balance Table C2
********************************************************************************

use `Combined_Date', clear 

append using "$data/Optiwatt US/US_EVs.dta"

replace fortis=1 if fortis==.

** encode group assignment 

encode group, gen(GroupAssignment)

** Drop group C8 - non-controllable EVs 

drop if treatment == "C8"

** Exclusion of California - uncomment this line to get the table for all states 

drop if state=="CA" 

** Save as an excel file

putexcel set "$results/Table C2.xlsx", sheet("Fortis vs. US", replace) replace 

putexcel A1 = "Variable"

putexcel B1 = "Fortis Sample"
putexcel C1 = "U.S. Sample"
putexcel D1 = "ttest (p-value)"

putexcel A2 = "Home Share"
putexcel A4 = "Charge Duration (Minutes)"
putexcel A6 = "Energy Charged (kWh)"

putexcel A8 = "Max kW Charge (Power)"
putexcel A10 = "Off-Peak Share (%)"
putexcel A12 = "Off-Peak Share (%) - Home Only"
putexcel A14 = "Tesla (%)"
putexcel A16 = "Number of EVs"

********************************************************************************

** All Fortis EVs vs. All US non-TOU EVs 

drop if plan_type == "tou"

**********
** Home Share
**********

* For Fortis EVs
sum home_share if fortis == 1
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel B2 = mean_fa, nformat(#.00)
putexcel B3 = sd_fa, nformat(#.00)

* For US EVs - Non TOU
sum home_share if fortis == 0 
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel C2 = mean_fa, nformat(#.00)
putexcel C3 = sd_fa, nformat(#.00)

* T-test for Home Share
ttest home_share , by(fortis) unequal
scalar tpval = r(p)
putexcel D2 = tpval, nformat(#.00)

**********
** Minutes
**********

* For Fortis EVs
sum daily_duration_minutes if fortis == 1
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel B4 = mean_fa, nformat(#.00)
putexcel B5 = sd_fa, nformat(#.00)

* For US EVs - Non TOU
sum daily_duration_minutes if fortis == 0 
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel C4 = mean_fa, nformat(#.00)
putexcel C5 = sd_fa, nformat(#.00)

* T-test for Daily Charge Duration (Minutes)
ttest daily_duration_minutes , by(fortis) unequal
scalar tpval = r(p)
putexcel D4 = tpval, nformat(#.00)

**********
** kWh
**********

* For Fortis EVs
sum total_KWhs_charged if fortis == 1
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel B6 = mean_fa, nformat(#.00)
putexcel B7 = sd_fa, nformat(#.00)

* For US EVs - Non TOU
sum total_KWhs_charged if fortis == 0 
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel C6 = mean_fa, nformat(#.00)
putexcel C7 = sd_fa, nformat(#.00)

* T-test for Daily Energy Charged (kWh)
ttest total_KWhs_charged , by(fortis) unequal
scalar tpval = r(p)
putexcel D6 = tpval, nformat(#.00)

**********
** Power
**********

* For Fortis EVs
sum max_power if fortis == 1
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel B8 = mean_fa, nformat(#.00)
putexcel B9 = sd_fa, nformat(#.00)

* For US EVs - Non TOU
sum max_power if fortis == 0 
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel C8 = mean_fa, nformat(#.00)
putexcel C9 = sd_fa, nformat(#.00)

* T-test for Max KW Charge (Power)
ttest max_power , by(fortis) unequal
scalar tpval = r(p)
putexcel D8 = tpval, nformat(#.00)

**********
** Off-Peak Share (%)
**********

* For Fortis EVs
sum off_peak_share if fortis == 1
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel B10 = mean_fa, nformat(#.00)
putexcel B11 = sd_fa, nformat(#.00)

* For US EVs - Non TOU
sum off_peak_share if fortis == 0 
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel C10 = mean_fa, nformat(#.00)
putexcel C11 = sd_fa, nformat(#.00)

* T-test for Off-Peak Share (%)
ttest off_peak_share , by(fortis) unequal
scalar tpval = r(p)
putexcel D10 = tpval, nformat(#.00)

**********
** Off-Peak Share (%) - Home Only
**********

* For Fortis EVs
sum off_peak_share_home if fortis == 1
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel B12 = mean_fa, nformat(#.00)
putexcel B13 = sd_fa, nformat(#.00)

* For US EVs - Non TOU
sum off_peak_share_home if fortis == 0 
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel C12 = mean_fa, nformat(#.00)
putexcel C13 = sd_fa, nformat(#.00)

* T-test for Off-Peak Share (%) - Home Only
ttest off_peak_share_home , by(fortis) unequal
scalar tpval = r(p)
putexcel D12 = tpval, nformat(#.00)

**********
** Tesla
**********

replace tesla_type = tesla_type*100 

* For Fortis EVs
sum tesla_type if fortis == 1
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel B14 = mean_fa, nformat(#.00)
putexcel B15 = sd_fa, nformat(#.00)

* For US EVs - Non TOU
sum tesla_type if fortis == 0 
scalar mean_fa = r(mean)
scalar sd_fa = r(sd)
putexcel C14 = mean_fa, nformat(#.00)
putexcel C15 = sd_fa, nformat(#.00)

* T-test for Tesla (%)
ttest tesla_type , by(fortis) unequal
scalar tpval = r(p)
putexcel D14 = tpval, nformat(#.00)

**********
** Count 
**********

* For Fortis EVs
count if fortis == 1
scalar count_fa = r(N)
putexcel B16 = count_fa

* For US EVs - Non TOU
count if fortis == 0 
scalar count_fa = r(N)
putexcel C16 = count_fa
