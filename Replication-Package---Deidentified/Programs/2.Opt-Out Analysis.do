********************************************************************************
********************************************************************************
*********************** Opt-out of Managed Charging  ***************************
********************************************************************************
********************************************************************************

// SET DIRECTORY

global statapath "Insert Directory"
global data "$statapath/Data"
global panel "$statapath/Data/Panel"
global results "$statapath/Results"
global fortisdata "$statapath/Data/Fortis Data"


********************************************************************************
** Load, Clean, and analyze Opt-Out data 
********************************************************************************

import excel using "$fortisdata/Fortis Data Transfer - 2024_01_29 UCalgary.xlsx", firstrow sheet("Event Opt-outs") clear 

//CORRECTION OF STRING TIME VARIABLES 
gen stime=substr(event_start,1,19)
gen etime=substr(event_end,1,19) 

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

** Create hour_start and date variables 

gen hour_start=hh(s_start)
gen date=dofc(s_start)

format date %td 

** Focus on data prior to Dec 14 

drop if date >= td(14Dec2023)

*******
** Remove days with "DR Events"
*******

drop if date == td(11aug2023)
drop if date == td(12aug2023)
drop if date == td(28aug2023)
drop if date == td(22nov2023)

** Only 44 event opt outs over the relevant sample period 

count

tab type

tab vehicle_id




********************************************************************************
** Compare event opt outs to the number of EV charging days in the Managed group 
********************************************************************************

** Upload hourly charge data 

use "$panel/panel_hourly_analysis.dta" , clear 

** Merge in Group Assignments 

merge m:1 vehicle_id using "$data/treatment group assignment.dta"

** _m == 1 are EVs that didnt make it into our trial, but have some charging data 
** Sizable numbers are coming from the fact that we have a number of unverified EVs that would have been eligible otherwise 

drop if _m == 1

drop _m 

** Focus on data post-treatment and before Dec 14
keep if date >= td(05Jul2023)

drop if date >= td(14Dec2023)

** Focus only on charging from managed EVs 

keep if group == "M"

*******
** Remove days with "DR Events"
*******

drop if date == td(11aug2023)
drop if date == td(12aug2023)
drop if date == td(28aug2023)
drop if date == td(22nov2023)

*******
** Focusing on at-home charging only 
** replace charge KWhs away with zero 
*******

gen kWh_added_hour_home = 0 
replace kWh_added_hour_home = kWh_added_hour if location == 0 

** Drop days where an EV did not charge 
** Define a day to be between 9:00 AM and 8:00 AM hour_start the following day 

sort vehicle_id date hour 

gen Time_9AM_flag = 0
replace Time_9AM_flag = 1 if hour == 9 

bysort vehicle_id (date hour ): gen Electricity_Day_Flag = sum(Time_9AM_flag)

bysort vehicle_id Electricity_Day_Flag: egen sum_ChargeEnergykWh_ElectricDay = sum(kWh_added_hour_home)

drop Time_9AM_flag

** Only keep electricity days where the car had some positive charge at home 

keep if sum_ChargeEnergykWh_ElectricDay > 0 

*******
** Collapse the data down to an EV-Home Charge Day
*******

gen ones = 1 

collapse (max) ones, by(vehicle_id date)

count 


