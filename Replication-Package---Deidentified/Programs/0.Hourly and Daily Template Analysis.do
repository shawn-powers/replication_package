********************************************************************************
********************************************************************************
*********** Creates Hourly and Daily Template Files - for Analysis *************
********************************************************************************
********************************************************************************

// SET DIRECTORY

global statapath "Insert Directory"
global data "$statapath/Data"
global panel "$statapath/Data/Panel"
global results "$statapath/Results"
global fortisdata "$statapath/Data/Fortis Data"

********************************************************************************
** Daily Template File 
********************************************************************************

** For all Vehicles, create a template file that has one row per day 
** Start on Jan 1, 2023 - June 30, 2024

use "$data/vehicle_data_analysis.dta", clear

keep vehicle_id

expand 547 

sort vehicle_id

gen ones = 1 

by vehicle_id: gen cumul_ones = sum(ones)

drop ones 

** Fill in Date variable 

display td(01Jan2023)

by vehicle_id: gen date = 23011 if cumul_ones == 1 

replace date = date[_n-1] + 1 if vehicle_id == vehicle_id[_n-1]

format date %td 

drop cumul_ones

save "$data/Daily_Template_Analysis.dta", replace 


********************************************************************************
** Hourly Template File 
********************************************************************************

** For all Vehicles, create a template file that has one row per hour 
** Start on Jan 1, 2023 - June 30, 2024

use "$data/vehicle_data_analysis.dta", clear

keep vehicle_id

expand 547 

sort vehicle_id

gen ones = 1 

by vehicle_id: gen cumul_ones = sum(ones)

drop ones 

** Fill in Date variable 

display td(01Jan2023)

by vehicle_id: gen date = 23011 if cumul_ones == 1 

replace date = date[_n-1] + 1 if vehicle_id == vehicle_id[_n-1]

format date %td 

drop cumul_ones

** Create an hour variable 

expand 24

sort vehicle_id date 

gen ones = 1 

by vehicle_id date : gen hour_start = sum(ones)

replace hour_start = hour_start - 1 

drop ones 

** Create a time variable 

gen month = month(date)
gen day = day(date)
gen year = year(date)

gen double time = mdyhms(month, day, year, hour_start, 0, 0)

format time %tc 

drop year month day 

save "$data/Hourly_Template_Analysis.dta", replace 
