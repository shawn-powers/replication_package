********************************************************************************
********************************************************************************
************* Construction of Panel Data Sets - For Analysis *******************
********************************************************************************
********************************************************************************

// SET DIRECTORY

global statapath "Insert Directory"
global data "$statapath/Data"
global panel "$statapath/Data/Panel"
global results "$statapath/Results"
global fortisdata "$statapath/Data/Fortis Data"

********************************************************************************
*				      Construct Vehicle Data File          			    	   *				
********************************************************************************

// Generate Data flagging EVs that have unenrolled from the program 
import excel "$fortisdata/Fortis Data Transfer - 2024_01_29 UCalgary.xlsx", sheet("Vehicle Owner Data") firstrow clear

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

save "$data/Unenroll_Vehicles_List.dta", replace 


// Vehicles List - all EVs that ever enrolled in Optiwatt - Merge with Unenrollment flags 
** Note: Need to pull from all files - need the full history of vehicles 

tempfile EV_Data1
import excel "$fortisdata/Fortis Data Transfer - 06_19_2023 UCalgary.xlsx", sheet("Vehicle Data") firstrow clear
save `EV_Data1'

tempfile EV_Data2
import excel "$fortisdata/Fortis Data Transfer - 07_07_2023 UCalgary.xlsx", sheet("Vehicle Data") firstrow clear
save `EV_Data2'

tempfile EV_Data3
import excel "$fortisdata/Fortis Data Transfer - 07_28_2023 UCalgary.xlsx", sheet("Vehicle Data") firstrow clear
save `EV_Data3'

tempfile EV_Data4
import excel "$fortisdata/Fortis Data Transfer - 08_22_2023.xlsx", sheet("Vehicle Data") firstrow clear
save `EV_Data4'

tempfile EV_Data5
import excel "$fortisdata/Fortis Data Transfer - 09_06_2023 - UCalgary.xlsx", sheet("Vehicle Data") firstrow clear
save `EV_Data5'

tempfile EV_Data6
import excel "$fortisdata/Fortis Data Transfer - 09_13_2023 - UCalgary.xlsx", sheet("Vehicle Data") firstrow clear
save `EV_Data6'

tempfile EV_Data7
import excel "$fortisdata/Fortis Data Transfer - 10_10_2023 - UCalgary.xlsx", sheet("Vehicle Data") firstrow clear
save `EV_Data7'

tempfile EV_Data8
import excel "$fortisdata/Fortis Data Transfer - 2023_11_08 UCalgary.xlsx", sheet("Vehicle Data") firstrow clear

replace est_battery_range_miles = "." if est_battery_range_miles == "NULL"

destring est_battery_range_miles, replace

save `EV_Data8'

tempfile EV_Data9 
import excel "$fortisdata/Fortis Data Transfer - 2023_12_18 UCalgary.xlsx", sheet("Vehicle data") firstrow clear

replace est_battery_range_miles = "." if est_battery_range_miles == "NULL"

destring est_battery_range_miles, replace

save `EV_Data9'


** Most recent data - final Phase 2 data file 
import excel "$fortisdata/Fortis Data Transfer - 2024_01_29 UCalgary.xlsx", sheet("Vehice Data") firstrow clear

** Clean up data 

replace est_battery_range_miles = "." if est_battery_range_miles == "NULL"

destring est_battery_range_miles, replace 

gen most_recent_data = 1 

append using `EV_Data1' 
append using `EV_Data2'
append using `EV_Data3'
append using `EV_Data4'
append using `EV_Data5'
append using `EV_Data6'
append using `EV_Data7'
append using `EV_Data8'
append using `EV_Data9'

** Keep most updated data, but fill in EVs that were listed at some point in time over the sample 

sort vehicle_id

bysort vehicle_id: egen max_most_recent_data = max(most_recent_data)

drop if max_most_recent_data == 1 & most_recent_data == . 

** Now drop the EVs that have duplicates 
 
duplicates drop vehicle_id, force 

** Merge in unenrolled EV list 
merge 1:1 vehicle_id using "$data/Unenroll_Vehicles_List.dta"

drop _m 

drop most_recent_data max_most_recent_data

save "$data/vehicle_data_analysis.dta", replace



** Make sure all EVs that made it into the treatment assignment are in this data set 

merge 1:1 vehicle_id using "$data/treatment group assignment.dta"

drop _m 


********************************************************************************
*				      Investigate Unenrollments           			    	   *				
********************************************************************************

// Understand how unenrolled EVs compare to the households we assigned to groups 

use "$data/treatment group assignment.dta", clear 

tab group 


** Merge in the ID for unenrolled EVs 

merge 1:1 vehicle_id using "$data/Unenroll_Vehicles_List.dta"

drop if _m == 2 

drop _m 

** Merge in EV Characteristics 

merge 1:1 vehicle_id using "$data/vehicle_data_analysis.dta"

drop if _m == 2 

drop _m 

** Focus on unenrollments before December 14, 2023
** Understand Unenrollment 

tab group if unenroll_date != . & unenroll_date < td(14Dec2023)

tab group 

*******
** Test if M and T have differential unenrollment rates - removing "user_reset_password" unenrollment 
*******

gen unenrolled = 0
replace unenrolled = 1 if unenroll_date != . & unenroll_date < td(14Dec2023)

gen user_reset_password_flag = 0 
replace user_reset_password_flag = 1 if unenroll_date != . & unenroll_date < td(14Dec2023) & unenrolled_reason == "user_reset_password"

tab unenrolled if group == "M" 

tab unenrolled if group == "T"  

tab unenrolled if group == "C" & treatment != "C8"  

tab unenrolled if group == "M"  & user_reset_password_flag != 1 

tab unenrolled if group == "T"  & user_reset_password_flag != 1 

tab unenrolled if group == "C" & treatment != "C8"   & user_reset_password_flag != 1 

gen group_M_T = . 
replace group_M_T = 1 if group == "M"
replace group_M_T = 2 if group == "T"

prtest unenrolled, by(group_M_T)

prtest unenrolled if  user_reset_password_flag != 1  , by(group_M_T)

gen unenrolled_nonpass = 0
replace unenrolled_nonpass = 1 if unenroll_date != . & unenroll_date < td(14Dec2023) & user_reset_password_flag != 1 

prtest unenrolled_nonpass  , by(group_M_T)


*******
** Test if M and C have differential unenrollment rates - removing "user_reset_password" unenrollment 
** Drop C8 in the comparison 
*******
 
tab unenrolled if group == "M" 

tab unenrolled if group == "C" & treatment != "C8"

tab unenrolled if group == "M"  & user_reset_password_flag != 1 

tab unenrolled if group == "C"  & user_reset_password_flag != 1  & treatment != "C8"

gen group_M_C = . 
replace group_M_C = 1 if group == "M"
replace group_M_C = 2 if group == "C"

prtest unenrolled if treatment != "C8" , by(group_M_C)

prtest unenrolled if  user_reset_password_flag != 1 & treatment != "C8" , by(group_M_C)

prtest unenrolled_nonpass if  treatment != "C8" , by(group_M_C)


*******
** Test if T and C have differential unenrollment rates - removing "user_reset_password" unenrollment 
*******
 
tab unenrolled if group == "T" 

tab unenrolled if group == "C" & treatment != "C8"

tab unenrolled if group == "T"  & user_reset_password_flag != 1

tab unenrolled if group == "C" & user_reset_password_flag != 1 & treatment != "C8"

gen group_T_C = . 
replace group_T_C = 1 if group == "T"
replace group_T_C = 2 if group == "C"

prtest unenrolled if treatment != "C8" , by(group_T_C)

prtest unenrolled if  user_reset_password_flag != 1 & treatment != "C8" , by(group_T_C)

prtest unenrolled_nonpass if  treatment != "C8" , by(group_T_C)


*******
** Focus on unenrolled EVS 
*******

keep if unenroll_date != . & treatment != "" & unenroll_date < td(14Dec2023)

** drop EVs in C8

drop if treatment == "C8"

** Tabulate unenrollment reason 

tab unenrolled_reason if group != ""  

tab unenrolled_reason if group == "M"  

tab unenrolled_reason if group == "T"  

tab unenrolled_reason if group == "C"  

** What are the EV characteristics when the unenrolment reason is "user_reset_password"?

tab make if group != "" & unenroll_date != .

tab make if group != "" & unenrolled_reason == "user_reset_password"

tab unenroll_date if unenrolled_reason == "user_reset_password"

** Understand distribution of unenrolments by transformer 

tab transformer if group == "M"  & unenroll_date != .
tab transformer if group == "T"  & unenroll_date != .
tab transformer if group == "C"  & unenroll_date != .

** Summarize Unenrollment Dates 

tab unenroll_date if group == "M" 
tab unenroll_date if group == "T" 
tab unenroll_date if group == "C" 







********************************************************************************
*				      Fortis Charging Data              			    	   *				
********************************************************************************


// CHARGING SESSIONS DATA
import excel "$fortisdata/Fortis Data Transfer - 2024_01_29 UCalgary.xlsx",  sheet("Charge Event Data") firstrow clear

// CHARGER TYPE 
encode charger_type, generate (charger)
drop charger_type
rename charger charger_type

//LOCATION
gen location=0
replace location=1 if home_id==.
label var location "1 Away - 0 Home"
label define loc 0 "Home" 1 "Away"
label values location loc

// SOME CLEANING (these variables are average per hour)
drop power_used_by_battery

rename kwh_used_by_charger st_kwh_used_by_charger
rename total_kwh_added_to_car_battery st_kwh_added_to_car_battery
rename total_est_battery_range_miles st_range_miles_added
rename duration_hours st_duration_hours

// BATTERY LEVEL ADDED
generate st_battry_level_added=end_battery_percent - start_battery_percent
label var st_battry_level_added "Session's Total Battery Level Added"

//CORRECTION OF STRING TIME VARIABLES 
gen stime=substr(start_time,1,19)
gen etime=substr(end_time,1,19) 


// TIME VARIABLES
gen double stime_utc = clock(stime, "YMDhms")
format stime_utc %tc

gen double etime_utc = clock(etime, "YMDhms")
format etime_utc %tc
drop stime etime

// UTC to MST
clonevar start_mst = stime_utc
clonevar start_mdt = stime_utc

local 7hours = msofhours(7)
local 6hours = msofhours(6)
replace start_mst=start_mst-`7hours'
replace start_mdt=start_mdt-`6hours'

clonevar end_mst = etime_utc
clonevar end_mdt = etime_utc

local 7hours = msofhours(7)
local 6hours = msofhours(6)
replace end_mst=end_mst-`7hours'
replace end_mdt=end_mdt-`6hours'

** 

gen mst_flag = 0 
replace mst_flag = 1 if start_mst >= tc(01nov2020 01:00:00) & start_mst < tc(14mar2021 02:00:00)
replace mst_flag = 1 if start_mst >= tc(07nov2021 01:00:00) & start_mst < tc(13mar2022 02:00:00)
replace mst_flag = 1 if start_mst >= tc(06nov2022 01:00:00) & start_mst < tc(12mar2023 02:00:00)
replace mst_flag = 1 if start_mst >= tc(05nov2023 01:00:00) & start_mst < tc(10mar2024 02:00:00)

gen mdt_flag = 0
replace mdt_flag = 1 if start_mdt >= tc(08mar2020 03:00:00) & start_mdt < tc(01nov2020 02:00:00)
replace mdt_flag = 1 if start_mdt >= tc(14mar2021 03:00:00) & start_mdt < tc(07nov2021 02:00:00)
replace mdt_flag = 1 if start_mdt >= tc(13mar2022 03:00:00) & start_mdt < tc(06nov2022 02:00:00)
replace mdt_flag = 1 if start_mdt >= tc(12mar2023 03:00:00) & start_mdt < tc(05nov2023 02:00:00)
replace mdt_flag = 1 if start_mdt >= tc(10mar2024 03:00:00)  

count if mst_flag == 1 & mdt_flag == 1
count if mst_flag == 0 & mdt_flag == 0

gen double s_start = . 
replace s_start = start_mst if mst_flag == 1 
replace s_start = start_mdt if mdt_flag == 1

count if s_start == . 

drop mst_flag mdt_flag
**

gen mst_flag = 0 
replace mst_flag = 1 if end_mst >= tc(01nov2020 01:00:00) & end_mst < tc(14mar2021 02:00:00)
replace mst_flag = 1 if end_mst >= tc(07nov2021 01:00:00) & end_mst < tc(13mar2022 02:00:00)
replace mst_flag = 1 if end_mst >= tc(06nov2022 01:00:00) & end_mst < tc(12mar2023 02:00:00)
replace mst_flag = 1 if end_mst >= tc(05nov2023 01:00:00) & end_mst < tc(10mar2024 02:00:00)

gen mdt_flag = 0
replace mdt_flag = 1 if end_mdt >= tc(08mar2020 03:00:00) & end_mdt < tc(01nov2020 02:00:00)
replace mdt_flag = 1 if end_mdt >= tc(14mar2021 03:00:00) & end_mdt < tc(07nov2021 02:00:00)
replace mdt_flag = 1 if end_mdt >= tc(13mar2022 03:00:00) & end_mdt < tc(06nov2022 02:00:00)
replace mdt_flag = 1 if end_mdt >= tc(12mar2023 03:00:00) & end_mdt < tc(05nov2023 02:00:00)
replace mdt_flag = 1 if end_mdt >= tc(10mar2024 03:00:00)  

count if mst_flag == 1 & mdt_flag == 1
count if mst_flag == 0 & mdt_flag == 0

gen double s_end = . 
replace s_end = end_mst if mst_flag == 1 
replace s_end = end_mdt if mdt_flag == 1 

count if s_end == . 

format s_start %tc 
format s_end %tc

label var s_start "Session's start time"
label var s_end "Session's end time"

drop mst_flag mdt_flag end_mdt end_mst start_mdt start_mst etime_utc stime_utc
drop start_time end_time    

** Note: Check that there are no duplicates across all variables - if so, drop 

duplicates drop  

** There are still a number of duplicate vehicle - charging sessions 

duplicates tag vehicle_id charge_id, gen(duplicates_flag)

browse if duplicates_flag > 0 

duplicates drop vehicle_id charge_id, force 

drop duplicates_flag

save "$data/charge_event_analysis.dta", replace



********************************************************************************
*				      Fortis Interval Data               			    	   *				
********************************************************************************


import delimited "$fortisdata/Fortis - Interval Charger Data 2024-01-29.csv" ,  asdouble clear 

//CORRECTION OF STRING TIME VARIABLE
gen time=substr(timestamp,1,19) 
drop timestamp scheduled_departure_time

// TIME VAR
gen double datetime_utc = clock(time, "YMDhms")
format datetime_utc %tc
drop time

// UTC to MST
clonevar hour_start_mst = datetime_utc
clonevar hour_start_mdt = datetime_utc

local 7hours = msofhours(7)
local 6hours = msofhours(6)
replace hour_start_mst=hour_start_mst-`7hours'
replace hour_start_mdt=hour_start_mdt-`6hours'

** Combine into a single date variable  

gen mst_flag = 0 
replace mst_flag = 1 if hour_start_mst >= tc(01nov2020 01:00:00) & hour_start_mst < tc(14mar2021 02:00:00)
replace mst_flag = 1 if hour_start_mst >= tc(07nov2021 01:00:00) & hour_start_mst < tc(13mar2022 02:00:00)
replace mst_flag = 1 if hour_start_mst >= tc(06nov2022 01:00:00) & hour_start_mst < tc(12mar2023 02:00:00)
replace mst_flag = 1 if hour_start_mst >= tc(05nov2023 01:00:00) & hour_start_mst < tc(10mar2024 02:00:00)

gen mdt_flag = 0
replace mdt_flag = 1 if hour_start_mdt >= tc(08mar2020 03:00:00) & hour_start_mdt < tc(01nov2020 02:00:00)
replace mdt_flag = 1 if hour_start_mdt >= tc(14mar2021 03:00:00) & hour_start_mdt < tc(07nov2021 02:00:00)
replace mdt_flag = 1 if hour_start_mdt >= tc(13mar2022 03:00:00) & hour_start_mdt < tc(06nov2022 02:00:00)
replace mdt_flag = 1 if hour_start_mdt >= tc(12mar2023 03:00:00) & hour_start_mdt < tc(05nov2023 02:00:00)
replace mdt_flag = 1 if hour_start_mdt >= tc(10mar2024 02:00:00)  

count if mst_flag == 1 & mdt_flag == 1
count if mst_flag == 0 & mdt_flag == 0

gen double timestamp = . 
replace timestamp = hour_start_mst if mst_flag == 1 
replace timestamp = hour_start_mdt if mdt_flag == 1 

count if timestamp == . 
 
format timestamp %tc

drop mdt_flag mst_flag hour_start_mdt hour_start_mst

// DROP DUPLICATE OBS & SINGLE OBS
duplicates drop

duplicates tag vehicle_id charge_id timestamp, gen(dup)
by vehicle_id charge_id  ( timestamp total_kwh_added_to_car_battery), sort: drop if timestamp[_n]==timestamp[_n+1] & dup[_n]==1 & dup[_n+1]==1
drop dup

bys vehicle_id charge_id (timestamp) : gen no_obs=_N
drop if no_obs==1
drop no_obs

//  GET RANGE OF TIME VALUES FOR EACH SESSION
by vehicle_id charge_id (timestamp), sort: gen double session_start = timestamp[1]
by vehicle_id charge_id (timestamp), sort: gen double session_end = timestamp[_N]
format session_start session_end %tc


//  DEFINE 10 MINUTES
local 10min = msofminutes(10)

//  CREATE OBSERVATIONS CORRESPONDING TO INTERVALS BETWEEN THE
//  ORIGINAL OBSERVATIONS
//by vehicle_id charge_id (timestamp), sort: replace timestamp = `10min'*floor(timestamp/`10min') if _n == 1

// ADDED KWH IN EACH INTERVAL
by vehicle_id charge_id (timestamp), sort: gen delta_khw_added = total_kwh_added_to_car_battery[_n+1] - total_kwh_added_to_car_battery 
replace delta_khw_added=round(delta_khw_added, 0.0001)

// ADDED RANGE IN EACH INTERVAL
by vehicle_id charge_id (timestamp), sort: gen delta_range = battery_range[_n+1] - battery_range
replace delta_range=round(delta_range, 0.0001)

// ADDED BATTERY LEVEL IN EACH INTERVAL
by vehicle_id charge_id (timestamp), sort: gen delta_battery_level = battery_level[_n+1] - battery_level
replace delta_battery_level=round(delta_battery_level, 0.0001)

// INTERVAL'S END TIME 
by vehicle_id charge_id (timestamp), sort: gen double timestamp2 = timestamp[_n+1]
format timestamp2 %tc

// LAST OBSERVATION IN EACH SESSION IS NOT NECESSARY
by vehicle_id charge_id (timestamp), sort: drop if _n == _N

// SAVE DATA - Temp data file 
gen `c(obs_t)' obs_no = _n
tempfile holding
save `holding'

//  CREATE TEN MINUTE INTERVALS
keep vehicle_id charge_id session_start session_end
duplicates drop

clonevar start_org=session_start
clonevar end_org=session_end
format start_org %tc
format end_org %tc

replace session_start = `10min'*floor(session_start/`10min')
replace session_end = `10min'*ceil(session_end/`10min')

gen expander=(session_end-session_start)/`10min' + 1
expand expander

by vehicle_id charge_id  (start_org), sort: gen double from = session_start if _n == 1
by vehicle_id charge_id  (session_start), sort: replace from = from[_n-1] + `10min' if _n > 1
format from %tc

by  vehicle_id charge_id  (from), sort: gen double to = from[_n+1]
format to %tc

by  vehicle_id charge_id  (from), sort: drop if _n == _N
drop session_start session_end expander start_org end_org

//  COMBINE WITH ORIGINAL DATA; RETAIN ONLY OVERLAPS
joinby vehicle_id charge_id using `holding'
 
keep if min(timestamp2, to) >= max(timestamp, from)
gen double overlap_time = min(timestamp2, to) - max(timestamp, from)
sort vehicle_id charge_id timestamp

//  WEIGHT EACH ORIGINAL OBSERVATION'S CONTRIBUTION TO THE 10 MINUTE INTERVAL
//  IN PROPORTION TO THE TIME OVERLAPPING THAT INTERVAL

gen double weight = overlap_time/(timestamp2-timestamp)

gen double kwh_contribution = weight*delta_khw_added
gen double range_contribution = weight*delta_range 
gen double battery_level_contribution = weight*delta_battery_level

by obs_no, sort: egen checksum = total(weight)

bysort vehicle_id charge_id from to ( timestamp) : egen double kwh_added_to_car_battery=total(kwh_contribution)
bysort vehicle_id charge_id from to ( timestamp) : egen double range_added=total(range_contribution)
bysort vehicle_id charge_id from to ( timestamp) : egen double battery_level_added=total(battery_level_contribution)

replace kwh_added_to_car_battery=round(kwh_added_to_car_battery, 0.001)
replace range_added=round(range_added, 0.001)
replace battery_level_added=round(battery_level_added, 0.001)

bys vehicle_id charge_id from : egen median_amp_10m=median(charge_amps) 
label var median_amp_10m "10 min's Median Amp"

bys vehicle_id charge_id from : egen max_amp_10m=max(charge_amps) 
label var max_amp_10m "10 min's Max Amp"


bys vehicle_id charge_id from : egen median_voltage_10m=median(charger_voltage) 
label var median_voltage_10m "10 min's Median Volt"

bys vehicle_id charge_id from : egen max_voltage_10m=max(charger_voltage) 
label var max_voltage_10m "10 min's Median Volt"

duplicates drop vehicle_id charge_id from to, force

drop total_kwh_added_to_car_battery battery_range timestamp battery_level delta_khw_added delta_range timestamp2 obs_no overlap_time weight checksum range_contribution kwh_contribution delta_battery_level battery_level_contribution 
 
rename session_start s_start
rename session_end s_end

label var s_start "Session's start time"
label var s_end "Session's end time"

//duplicates t vehicle_id from to, gen(dup)

merge m:1 vehicle_id charge_id using "$data/charge_event_analysis.dta"
drop if _merge==2 // Obs in the other category (data from charge event sheet that are not matched) have zero kwh added
drop if _m == 1 // Observations beyond sample period - After Jan 1, 2024
drop _merge

** Merge with Vehicle Data 
merge m:1 vehicle_id  using "$data/vehicle_data_analysis.dta"

drop if _merge == 2 // EVs with no charge data (not assigned to any groups)

drop _merge

order vehicle_id charge_id from to charge_amps charger_voltage kwh_added_to_car_battery range_added battery_level_added location charger_type make model year est_battery_range_miles tesla_powerwall tesla_solar  datetime_utc s_start s_end st_duration_hours st_kwh_used_by_charger st_kwh_added_to_car_battery st_range_miles_added st_battry_level_added  start_battery_range_miles end_battery_range_miles

** Note: Small number of negative charge outliers (replace with 0)

replace kwh_added_to_car_battery = 0 if kwh_added_to_car_battery < 0  

save "$panel/panel_10min_analysis.dta" , replace

********************************************************************************
*							      Hourly Panel						    	   *				
********************************************************************************

use "$panel/panel_10min_analysis.dta" , clear
gen hour=hh(from)
gen date=dofc(from)
format date %td

generate double time=dhms(date,hour,00,00)
format time %tc

order vehicle_id charge_id time date hour

bysort vehicle_id date hour (from) : egen median_amp_h=median(charge_amps) 
label var median_amp_h "Hour's Median Amp"
bysort vehicle_id date hour (from) : egen median_voltage_h=median(charger_voltage) 
label var median_voltage_h "Hour's Median Volt"

bysort vehicle_id  date hour (from) : egen max_amp_h=max(charge_amps) 
label var max_amp_h "Hour's Max Amp"
bysort vehicle_id  date hour (from) : egen max_voltage_h=max(charger_voltage) 
label var max_voltage_h "Hour's Max Volt"

bysort vehicle_id date hour (from) : egen double kWh_added_hour=total(kwh_added_to_car_battery)
bysort vehicle_id date hour (from) : egen double range_added_hour=total(range_added)
bysort vehicle_id date hour (from) : egen double batterylvl_added_hour=total(battery_level_added)

	label var batterylvl_added_hour "Battery Level Added (%)"
	label var range_added_hour "Range Added (miles)"

replace kWh_added_hour=round(kWh_added_hour, 0.001)
replace range_added_hour=round(range_added_hour, 0.001)
replace batterylvl_added_hour=round(batterylvl_added_hour, 0.001)

** Calculate session minutes 

gen st_duration_minutes = (s_end - s_start)/(60*1000)

** Clean Up data set 

drop from to  datetime_utc kwh_added_to_car_battery range_added battery_level_added charge_amps charger_voltage median_amp_10m max_amp_10m median_voltage_10m max_voltage_10m 

** Compress data down to one observation per hour 
** First delete duplicate charge sessions at the hourly level 

duplicates drop vehicle_id charge_id date hour, force 

** Deal with duplicate hours - multiple charge sessions per hour 
** Take the (max) of the variables that are already summarized by the hour 
** Take the (max) of charger location and charger level - very few multi-charge sessions within an hour that differ on these dimensions

rename year car_year

collapse (max) time median_amp_h median_voltage_h max_amp_h max_voltage_h kWh_added_hour range_added_hour batterylvl_added_hour ///
		 (max) location charger_type tesla_powerwall tesla_solar car_year est_battery_range_miles ///	
         (firstnm) make model  /// 
         , by(vehicle_id date hour)
		 
** Label location Variable 
label var location "1 Away - 0 Home"
label values location loc
		 
save "$panel/panel_hourly_analysis.dta", replace



 

