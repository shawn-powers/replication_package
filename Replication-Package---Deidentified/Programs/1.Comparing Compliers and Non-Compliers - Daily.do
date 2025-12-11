********************************************************************************
********************************************************************************
********** Comparing Characteristics of Compliers and Non-Compliers ************
********************************************************************************
********************************************************************************

// SET DIRECTORY

global statapath "Insert Directory"
global data "$statapath/Data"
global panel "$statapath/Data/Panel"
global results "$statapath/Results"
global fortisdata "$statapath/Data/Fortis Data"


********************************************************************************
** Comparing Characteristics by Enrollment Status 
********************************************************************************

** Storing drop-out list before December 13th
use "$data/Unenroll_Vehicles_List.dta", clear

keep if unenroll_date<=td(13dec2023)

save "$data/CNCA_Unenroll_Vehicles_List.dta", replace

********************************************************************************
********************************************************************************

** Metrics to use to evaluate
* 1. off-peak charging share (need interval data)
* 2. home share of charging (session data)
* 3. daily charge duration (minutes) (session data, home)
* 4. total kWh charged per day (session data, home)
* 5. max rate of home charge (kW) (session data, home)
* 6. Tesla/non-Tesla (vehicle data)

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

sort min_date 

gen ones = 1 

gen sum_ones = sum(ones)

** Vast majority are on the App by April 1 (85%)
*twoway line sum_ones min_date if min_date >= td(01Dec2022)

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


** Merge in group assignments

merge 1:1 vehicle_id using "$data/treatment group assignment.dta"

keep if _m == 3 

drop _m 

** Merge in compliers and non-compliers

merge m:1 vehicle_id using "$data/CNCA_Unenroll_Vehicles_List.dta"
drop if _merge==2

gen compliers=0
	replace compliers=1 if _merge==1

drop _merge

label define comp 0 "Non-Compliers" 1 "Compliers " , modify
label values compliers comp

** Drop group C8 - non-controllable EVs 

drop if treatment == "C8"

** Password-reset dummy

gen password_reset=0
replace password_reset=1 if unenrolled_reason=="user_reset_password"

********************************************************************************
** Setup Summary Stats Table B1
********************************************************************************

** Save as an excel file 
putexcel set "$results/Table B1.xlsx", sheet("All Vehicles - PrePost", replace) replace 

putexcel A2 = "Variable"

putexcel B1 = "Pre-Treatment"
putexcel B2 = "Completed"
putexcel C2 = "Left"
putexcel D2 = "t-test (p-value)"

putexcel F1 = "Post-Treatment"
putexcel F2 = "Completed"
putexcel G2 = "Left"
putexcel H2 = "t-test (p-value)"

putexcel A3 = "Home Share (%)"
putexcel A5 = "Charge Duration (Minutes)"
putexcel A7 = "Energy Charged (kWh)"
putexcel A9 = "Max kW Charge (Power)"
putexcel A11 = "Off-Peak Share (%)"
putexcel A13 = "Off-Peak Share (%) - Home Only"
putexcel A15 = "Tesla (%)"
putexcel A17 = "Number of EVs"

********************************************************************************
** Summary Stats Table B1 - Pre-Treatment Period 
********************************************************************************

**********
** Home Share
**********

sum home_share if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel B3 = mean_compliers, nformat(#.00)
putexcel B4 = sd_compliers, nformat(#.00)

sum home_share if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel C3 = mean_noncompliers, nformat(#.00)
putexcel C4 = sd_noncompliers, nformat(#.00)

ttest home_share, by(compliers) unequal
scalar tpval =  r(p)
putexcel D3 = tpval, nformat(#.00)

**********
** Minutes
**********

sum daily_duration_minutes if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel B5 = mean_compliers, nformat(#.00)
putexcel B6 = sd_compliers, nformat(#.00)

sum daily_duration_minutes if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel C5 = mean_noncompliers, nformat(#.00)
putexcel C6 = sd_noncompliers, nformat(#.00)

ttest daily_duration_minutes, by(compliers) unequal
scalar tpval =  r(p)

putexcel D5 = tpval, nformat(#.00)

**********
** KWh
**********

sum total_KWhs_charged if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel B7 = mean_compliers, nformat(#.00)
putexcel B8 = sd_compliers, nformat(#.00)

sum total_KWhs_charged if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel C7 = mean_noncompliers, nformat(#.00)
putexcel C8 = sd_noncompliers, nformat(#.00)


ttest total_KWhs_charged, by(compliers) unequal
scalar tpval =  r(p)
putexcel D7 = tpval, nformat(#.00)

**********
** Power
**********

sum max_power if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel B9 = mean_compliers, nformat(#.00)
putexcel B10 = sd_compliers, nformat(#.00)

sum max_power if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel C9 = mean_noncompliers, nformat(#.00)
putexcel C10 = sd_noncompliers, nformat(#.00)
  

ttest max_power, by(compliers) unequal
scalar tpval =  r(p)

putexcel D9 = tpval, nformat(#.00)

**********
** Off-Peak Share - Home and Away 
**********

sum off_peak_share if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel B11 = mean_compliers, nformat(#.00)
putexcel B12 = sd_compliers, nformat(#.00)

sum off_peak_share if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel C11 = mean_noncompliers, nformat(#.00)
putexcel C12 = sd_noncompliers, nformat(#.00)
 

ttest off_peak_share, by(compliers) unequal
scalar tpval =  r(p)

putexcel D11 = tpval, nformat(#.00)

**********
** Off-Peak Share - Home only 
**********

sum off_peak_share_home if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel B13 = mean_compliers, nformat(#.00)
putexcel B14 = sd_compliers, nformat(#.00)

sum off_peak_share_home if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel C13 = mean_noncompliers, nformat(#.00)
putexcel C14 = sd_noncompliers, nformat(#.00)
 

ttest off_peak_share_home, by(compliers) unequal
scalar tpval =  r(p)

putexcel D13 = tpval, nformat(#.00)

**********
** Tesla 
**********

replace tesla_type = tesla_type*100 

sum tesla_type if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel B15 = mean_compliers, nformat(#.00)
putexcel B16 = sd_compliers, nformat(#.00)

sum tesla_type if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel C15 = mean_noncompliers, nformat(#.00)
putexcel C16 = sd_noncompliers, nformat(#.00)

** Rescale to do differences in proportions test
replace tesla_type = tesla_type/100 

*ttest tesla_type, by(compliers) unequal
prtest tesla_type, by(compliers)
scalar tpval =  r(p)

putexcel D15 = tpval , nformat(#.00)

**********
** Count 
**********

bys compliers : gen count_all=_N
bys compliers group : gen count_groups=_N

sum count_all if compliers == 1

scalar mean_compliers = r(mean)

putexcel B17 = mean_compliers

sum count_all if compliers == 0

scalar mean_noncompliers = r(mean)

putexcel C17 = mean_noncompliers

********************************************************************************
** Build Summary Stats Table B1 - Post-Treatment 
********************************************************************************

********************************************************************************
********************************************************************************

** Metrics to use to evaluate

* 1. off-peak charging share (need interval data)
* 2. home share of charging (session data)
* 3. daily charge duration (minutes) (session data, home)
* 4. total kWh charged per day (session data, home)
* 5. average number of sessions per day (session data)
* 6. Tesla/non-Tesla (vehicle data)

********************************************************************************
********************************************************************************

*******
* 1A. off-peak charging share (need interval data) - Home and Away 
*******

use "$panel/panel_hourly_analysis.dta", clear 

** Focus on data between July 5 to July 31 (post-treatment)

keep if date >= td(05jul2023)  

drop if date > td(31jul2023)

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

** Focus on data between July 5 to July 31 (post-treatment)

keep if date >= td(05jul2023)  

drop if date > td(31jul2023)

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

** Focus on data between July 5 to July 31 (post-treatment)

keep if date >= td(05jul2023)  

drop if date > td(31jul2023)

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

** Focus on data between July 5 to July 31 (post-treatment)

keep if date >= td(05jul2023)  

drop if date > td(31jul2023)

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

** Merge in group assignments

merge 1:1 vehicle_id using "$data/treatment group assignment.dta"

keep if _m == 3 

drop _m 

** Merge in compliers and non-compliers

merge m:1 vehicle_id using "$data/CNCA_Unenroll_Vehicles_List.dta"
drop if _merge==2

gen compliers=0
	replace compliers=1 if _merge==1

drop _merge

label define comp 0 "Non-Compliers" 1 "Compliers " , modify
label values compliers comp

** Drop group C8 - non-controllable EVs 

drop if treatment == "C8"

** Password-reset dummy

gen password_reset=0
replace password_reset=1 if unenrolled_reason=="user_reset_password"

********************************************************************************
** Summary Stats Table B1 - Post-Treatment Period 
********************************************************************************

**********
** Home Share
**********

sum home_share if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel F3 = mean_compliers, nformat(#.00)
putexcel F4 = sd_compliers, nformat(#.00)

sum home_share if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel G3 = mean_noncompliers, nformat(#.00)
putexcel G4 = sd_noncompliers, nformat(#.00)

ttest home_share, by(compliers) unequal
scalar tpval =  r(p)
putexcel H3 = tpval, nformat(#.00)

**********
** Minutes
**********

sum daily_duration_minutes if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel F5 = mean_compliers, nformat(#.00)
putexcel F6 = sd_compliers, nformat(#.00)

sum daily_duration_minutes if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel G5 = mean_noncompliers, nformat(#.00)
putexcel G6 = sd_noncompliers, nformat(#.00)

ttest daily_duration_minutes, by(compliers) unequal
scalar tpval =  r(p)

putexcel H5 = tpval, nformat(#.00)

**********
** KWh
**********

sum total_KWhs_charged if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel F7 = mean_compliers, nformat(#.00)
putexcel F8 = sd_compliers, nformat(#.00)

sum total_KWhs_charged if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel G7 = mean_noncompliers, nformat(#.00)
putexcel G8 = sd_noncompliers, nformat(#.00)


ttest total_KWhs_charged, by(compliers) unequal
scalar tpval =  r(p)
putexcel H7 = tpval, nformat(#.00)

**********
** Power
**********

sum max_power if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel F9 = mean_compliers, nformat(#.00)
putexcel F10 = sd_compliers, nformat(#.00)

sum max_power if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel G9 = mean_noncompliers, nformat(#.00)
putexcel G10 = sd_noncompliers, nformat(#.00)
  

ttest max_power, by(compliers) unequal
scalar tpval =  r(p)

putexcel H9 = tpval, nformat(#.00)

**********
** Off-Peak Share - Home and Away 
**********

sum off_peak_share if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel F11 = mean_compliers, nformat(#.00)
putexcel F12 = sd_compliers, nformat(#.00)

sum off_peak_share if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel G11 = mean_noncompliers, nformat(#.00)
putexcel G12 = sd_noncompliers, nformat(#.00)
 

ttest off_peak_share, by(compliers) unequal
scalar tpval =  r(p)

putexcel H11 = tpval, nformat(#.00)

**********
** Off-Peak Share - Home only 
**********

sum off_peak_share_home if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel F13 = mean_compliers, nformat(#.00)
putexcel F14 = sd_compliers, nformat(#.00)

sum off_peak_share_home if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel G13 = mean_noncompliers, nformat(#.00)
putexcel G14 = sd_noncompliers, nformat(#.00)
 
ttest off_peak_share_home, by(compliers) unequal
scalar tpval =  r(p)

putexcel H13 = tpval, nformat(#.00)

**********
** Tesla 
**********

replace tesla_type = tesla_type*100 

sum tesla_type if compliers == 1

scalar mean_compliers = r(mean)
scalar sd_compliers = r(sd)

putexcel F15 = mean_compliers, nformat(#.00)
putexcel F16 = sd_compliers, nformat(#.00)

sum tesla_type if compliers == 0

scalar mean_noncompliers = r(mean)
scalar sd_noncompliers = r(sd)

putexcel G15 = mean_noncompliers, nformat(#.00)
putexcel G16 = sd_noncompliers, nformat(#.00)

** Rescale to do differences in proportions test
replace tesla_type = tesla_type/100 

*ttest tesla_type, by(compliers) unequal
prtest tesla_type, by(compliers)
scalar tpval =  r(p)

putexcel H15 = tpval , nformat(#.00)

**********
** Count 
**********

bys compliers : gen count_all=_N
bys compliers group : gen count_groups=_N

sum count_all if compliers == 1

scalar mean_compliers = r(mean)

putexcel F17 = mean_compliers

sum count_all if compliers == 0

scalar mean_noncompliers = r(mean)

putexcel G17 = mean_noncompliers
