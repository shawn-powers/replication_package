********************************************************************************
********************************************************************************
*************************** Descriptive Analysis *******************************
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
** Understand where the EVs in our Experiment are Located 
********************************************************************************
********************************************************************************

import excel "$data/Vehicle_List_LocationID -6-24-2024 - GC Value Update.xlsx", firstrow clear

merge 1:1 vehicle_id using "$data/treatment group assignment.dta"

drop if _m == 1 

drop _m 

** Drop group C8 (not part of our analysis)

drop if treatment == "C8"

tab group 

generate municipality=substr(Municipality,2,.)
drop Municipality

tempfile Vehicle_List_LocationID
save `Vehicle_List_LocationID'

****************************************
** Define whether EVs are rural or Urban 
****************************************

** Definition 1: rural1 = Alberta's List of Urban and Rural Communities (2016 Census) 
** Definition 2: rural2 = Statistics Canada definition of rural areas 

import delimited "$data/community_data.csv", delimiter(comma) varnames(1) clear

** Deal with cases that are not mapped 
replace rural1=1 if rural1==. & municipality=="AB" // Assign to rural - conservative approach 
replace rural1=0 if rural1==. & municipality=="Balzac"  
replace rural1=1 if rural1==. & municipality=="Blairmore"
replace rural1=1 if rural1==. & municipality=="Bragg Creek"
replace rural1=1 if rural1==. & municipality=="De Winton"
replace rural1=1 if rural1==. & municipality=="Entwistle"
replace rural1=1 if rural1==. & municipality=="Foothills County" // A large area - conservative approach

replace rural1=1 if rural1==. & municipality=="Gunn"
replace rural1=1 if rural1==. & municipality=="Gwynne"
replace rural1=1 if rural1==. & municipality=="Keoma"
replace rural1=1 if rural1==. & municipality=="Lorrelind Estates"
replace rural1=1 if rural1==. & municipality=="Millarville"
replace rural1=0 if rural1==. & municipality=="Nisku"
replace rural1=1 if rural1==. & municipality=="Rosebud"

** Definition 2: 

replace rural2=1 if rural2==. & municipality=="AB" // Assign to rural - conservative approach 

** Merge 

merge 1:m municipality using `Vehicle_List_LocationID'
drop _merge

tab rural2



********************************************************************************
********************************************************************************
** Construct a panel data set to do descriptive analysis 
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

*******
** Clean up data set 
*******

order vehicle_id treatment group transformer date time hour_start kWh_added_hour kWh_added_hour_home

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

collapse (max) transformer evloadlimit  evloadlimit_adj EV_Count (firstnm) group (sum) kWh_added_hour_home, by(treatment date hour_start)

** Create transformer space variable 
** Use adjusted EV Limit 

gen Transformer_Space = evloadlimit_adj - kWh_added_hour_home

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

sort  treatment  date hour_start  		

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

collapse (max) transformer (mean) Violation ones Violation_KWhs,  by(group Post_Treatment_Flag hour_start)

save "$data/Violations_Descriptive_Plots_Data.dta", replace 		
		
**************************
** Plot of Violation KWhs - Average violation kWhs at the day-group-hour for both pre and post 
**************************	

replace Violation_KWhs = -1*Violation_KWhs

sum Violation_KWhs , detail 

twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "M" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs hour_start if group == "M" & Post_Treatment_Flag == 1,  color(black) ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Managed") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Pre-Treatment" 5 "Post-Treatment") cols(2)) name(Managed_daily ,replace) 
									
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "T" & Post_Treatment_Flag == 0, lpattern(dash) color(black)  ) ///
	   (line Violation_KWhs hour_start if group == "T" & Post_Treatment_Flag == 1, color(black)  ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("TOU") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Pre-Treatment" 5 "Post-Treatment") cols(2)) name(TOU_daily ,replace) 
					  										
twoway (scatteri 0 0 0 6 4.5 6 4.5 0, recast(area) color(gs14)   ) ///
	   (scatteri 0 10 0 14 4.5 14 4.5 10 , recast(area) color(gs14)  ) ///
	   (scatteri 0 22 0 23 4.5 23 4.5 22, recast(area) color(gs14)    ) ///
	   (line Violation_KWhs hour_start if group == "C" & Post_Treatment_Flag == 0, lpattern(dash)  color(black)  ) ///
	   (line Violation_KWhs hour_start if group == "C" & Post_Treatment_Flag == 1, color(black)  ) ///
					, xlabel(0 6 12 18 23)   yscale(range(0, 4))  ylabel(0 1 2 3 4) ///
					  graphregion(color(white) ) title("Control") ///
					  ytitle("kWh") xtitle("Hour") ///
					  legend( order( 4 "Pre-Treatment" 5 "Post-Treatment") cols(2)) name(Control_daily ,replace) 
					  
grc1leg Control_daily TOU_daily Managed_daily  , cols(1)  graphregion(color(white) ) name(grc1leggraph ,replace)
gr draw grc1leggraph,  ysize(4.5) xsize(2.5)

graph export "$results/Figure2b.pdf", replace 					


restore 


********************************************************************************
** Descriptive Plots of Charging Patterns - Focus on Charging Days only - by Group (Pre and Post)
********************************************************************************

preserve 

** Focus on all cars (i.e., including those with randomized_eligible == 0)

** Drop days where an EV did not charge 
** Define a day to be between 9:00 AM and 8:00 AM hour_start the following day 

sort vehicle_id date hour_start 

gen Time_9AM_flag = 0
replace Time_9AM_flag = 1 if hour_start == 9 

bysort vehicle_id (date hour_start ): gen Electricity_Day_Flag = sum(Time_9AM_flag)

bysort vehicle_id Electricity_Day_Flag: egen sum_ChargeEnergykWh_ElectricDay = sum(kWh_added_hour_home)

drop Time_9AM_flag

** Only keep electricity days where the car had some positive charge at home 

keep if sum_ChargeEnergykWh_ElectricDay > 0 

** Collapse to the treatment group-date-hour level, taking the mean of charging 

collapse (mean) kWh_added_hour kWh_added_hour_home, by(group date hour_start)

** Post-Treatment Flag 

gen Post_Treatment_Flag = 0 
replace Post_Treatment_Flag = 1 if date >= td(05jul2023)

** Collapse down to group - hour - pre and post-treatment  

collapse (mean)  kWh_added_hour kWh_added_hour_home,  by(group Post_Treatment_Flag hour_start)


*********************
** Home-Only Charging 
*********************

	   
** Plot pre and post for each group in the same graph 

twoway (scatteri 0 0 0 6 2.35 6 2.35 0, recast(area) color(gs14) ylabel(0 0.5 1 1.5 2) yscale(range(0, 2.35))   ) ///
	   (scatteri 0 10 0 14 2.35 14 2.35 10, recast(area) color(gs14) ylabel(0 0.5 1 1.5 2) yscale(range(0, 2.35))   ) ///	
	   (scatteri 0 22 0 23 2.35 23 2.35 22, recast(area) color(gs14) ylabel(0 0.5 1 1.5 2) yscale(range(0, 2.35))   ) ///	
	   (line kWh_added_hour_home hour_start if group == "C" & Post_Treatment_Flag == 0, lpattern(dash)  color(black) ) ///
	   (line kWh_added_hour_home hour_start if group == "C" & Post_Treatment_Flag == 1,  color(black) ) , ///
	   graphregion(color(white) )   ytitle("kWh") xtitle("Hour") title("Control") xlabel(0 6 12 18 23) ///
	   legend( order( 4 "Pre-Treatment" 5 "Post-Treatment") cols(2)) name(HomeCharging_C ,replace) 
	   	  
	   
twoway (scatteri 0 0 0 6 2.35 6 2.35 0, recast(area) color(gs14) ylabel(0 0.5 1 1.5 2) yscale(range(0, 2.35))   ) ///
	   (scatteri 0 10 0 14 2.35 14 2.35 10, recast(area) color(gs14) ylabel(0 0.5 1 1.5 2) yscale(range(0, 2.35))   ) ///	
	   (scatteri 0 22 0 23 2.35 23 2.35 22, recast(area) color(gs14) ylabel(0 0.5 1 1.5 2) yscale(range(0, 2.35))   ) ///	
	   (line kWh_added_hour_home hour_start if group == "T" & Post_Treatment_Flag == 0, lpattern(dash)  color(black) ) ///
	   (line kWh_added_hour_home hour_start if group == "T" & Post_Treatment_Flag == 1,  color(black) ) , ///
	   graphregion(color(white) ) ytitle("kWh") xtitle("Hour")  title("TOU") xlabel(0 6 12 18 23) ///
	   legend( order( 4 "Pre-Treatment" 5 "Post-Treatment") cols(2)) name(HomeCharging_T ,replace) 
	   

twoway (scatteri 0 0 0 6 2.35 6 2.35 0, recast(area) color(gs14) ylabel(0 0.5 1 1.5 2) yscale(range(0, 2.35))   ) ///
	   (scatteri 0 10 0 14 2.35 14 2.35 10, recast(area) color(gs14) ylabel(0 0.5 1 1.5 2) yscale(range(0, 2.35))   ) ///	
	   (scatteri 0 22 0 23 2.35 23 2.35 22, recast(area) color(gs14) ylabel(0 0.5 1 1.5 2) yscale(range(0, 2.35))   ) ///		
	   (line kWh_added_hour_home hour_start if group == "M" & Post_Treatment_Flag == 0, lpattern(dash)  color(black) ) ///
	   (line kWh_added_hour_home hour_start if group == "M" & Post_Treatment_Flag == 1,  color(black) ) , ///
	   graphregion(color(white) ) ytitle("kWh") xtitle("Hour") title("Managed") xlabel(0 6 12 18 23) ///
	   legend( order( 4 "Pre-Treatment" 5 "Post-Treatment") cols(2) ) name(HomeCharging_M ,replace)   
	   

grc1leg HomeCharging_C HomeCharging_T HomeCharging_M  , cols(1)  graphregion(color(white) ) name(grc1leggraph ,replace)
gr draw grc1leggraph,  ysize(4.5) xsize(2.5)

graph export "$results/Figure2a.pdf", replace 			   
	   
restore 


