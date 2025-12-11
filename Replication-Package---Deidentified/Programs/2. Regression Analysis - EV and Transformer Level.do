********************************************************************************
********************************************************************************
********************* EV-Level Regression Analysis  ****************************
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
** Construct a panel data set to do regression analysis 
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

** Drop C8 control group - 14 non-controllable EVs 

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
** EV-Level: Regression Analysis 
********************************************************************************
********************************************************************************

**************************
** Start with a regression that permits differential effects by peak and off-peak 
**************************

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

** TOU marginal effect 


quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
xlincom  1.TOU_group#1.Post_Treat, post
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
		  
		
** Pre-treatment metrics 

eststo sum_kwh_home_T: estpost sum kWh_added_hour_home if group == "T" & Post_Treat == 0 & off_peak == 0 

eststo sum_kwh_home_M: estpost sum kWh_added_hour_home if group == "M" & Post_Treat == 0 & off_peak == 0 

eststo sum_kwh_home_T_offp: estpost sum kWh_added_hour_home if group == "T" & Post_Treat == 0 & off_peak == 1 

eststo sum_kwh_home_M_offp: estpost sum kWh_added_hour_home if group == "M" & Post_Treat == 0 & off_peak == 1 		
				
** Post-treatment metrics

eststo sum_kwh_home_C_post: estpost sum kWh_added_hour_home if group == "C" & Post_Treat == 1 & off_peak == 0 
eststo sum_kwh_home_C_post_offp: estpost sum kWh_added_hour_home if group == "C" & Post_Treat == 1 & off_peak == 1 
						
				
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
	
************
** DID with heterogeneous effects by hour 
************		
	
quietly reghdfe kWh_added_hour_home ib0.TOU_group##ib0.Post_Treat##ib21.hour_start  ///
								ib0.Managed_group##ib0.Post_Treat##ib21.hour_start /// 
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)

** TOU Effects 
		
forvalues i = 0(1)23{ 
	
xlincom 1.TOU_group#1.Post_Treat  +  1.TOU_group#1.Post_Treat#`i'.hour_start 
 
}

* Graph
matrix Coefficients = J(1, 24, .)
matrix CI = J(2,24,.)

forvalues i=0(1)23{
	
xlincom 1.TOU_group#1.Post_Treat  +  1.TOU_group#1.Post_Treat#`i'.hour_start 
 
	matrix Coefficients[1,`i'+1]=r(table)[1,1]
	matrix CI[1,`i'+1]=r(table)[5,1]
	matrix CI[2,`i'+1]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13) ///
 ytitle("kWh") xtitle("Hour") yline(0) ylabel(-1(0.5)1) xlabel ( 1 "0" 2 "1" 3 "2" 4 "3" 5 "4" 6 "5" 7 "6" 8 "7" 9 "8" 10 "9" 11 "10" 12 "11" 13 "12" 14 "13" 15 "14" 16 "15" 17 "16" 18 "17" 19 "18" 20 "19" 21 "20" 22 "21" 23 "22" 24 "23") graphregion(color(white)) ///
			 note("", size(7pt)) name(TOU_ChargekWh_EVLvl ,replace)  title("TOU")
			 	 
sum kWh_added_hour_home if Post_Treat == 0 & group == "T"

** Managed Effects 

forvalues i = 0(1)23{ 
lincom 1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#`i'.hour_start 

}
	
* Graph
matrix Coefficients = J(1, 24, .)
matrix CI = J(2,24,.)

forvalues i=0(1)23{
	
xlincom 1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#`i'.hour_start 
 
	matrix Coefficients[1,`i'+1]=r(table)[1,1]
	matrix CI[1,`i'+1]=r(table)[5,1]
	matrix CI[2,`i'+1]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13) ///
 ytitle("kWh") xtitle("Hour") yline(0) ylabel(-1(0.5)1) xlabel ( 1 "0" 2 "1" 3 "2" 4 "3" 5 "4" 6 "5" 7 "6" 8 "7" 9 "8" 10 "9" 11 "10" 12 "11" 13 "12" 14 "13" 15 "14" 16 "15" 17 "16" 18 "17" 19 "18" 20 "19" 21 "20" 22 "21" 23 "22" 24 "23") graphregion(color(white)) ///
			 note("", size(7pt)) name(Managed_ChargekWh_EVLvl ,replace)  title("Managed")
			 
sum kWh_added_hour_home if Post_Treat == 0 & group == "M"

sleep 1000 

grc1leg2 TOU_ChargekWh_EVLvl Managed_ChargekWh_EVLvl   , cols(1) loff graphregion(color(white) )   name(grc1leggraph ,replace)

gr draw grc1leggraph,  ysize(3.5) xsize(2.5)

graph export "$results/Figure3a.pdf", replace 					
	
 

********************************************************************************
********************************************************************************
** Heterogeneous Effects by Peak/Off-Peak and Month 
********************************************************************************
********************************************************************************

** Deal with the fact that the first 4 days of July were pre-treatment - Place with June
replace month = 6 if month == 7 & date <= td(04july2023)

*************************
** Specification with peak/off-peak differential - kWhs added at home per EV on Transformer - Additional FEs
*************************		
	
reghdfe kWh_added_hour_home ib0.TOU_group##ib0.off_peak##ib6.month ///
						   ib0.Managed_group##ib0.off_peak##ib6.month ///
		, absorb(vehicle_id date hour_start) vce(cluster group_cluster)
       
** TOU marginal effect - PEAK 

xlincom  1.TOU_group#7.month

xlincom  1.TOU_group#8.month

xlincom  1.TOU_group#9.month

xlincom  1.TOU_group#10.month

xlincom  1.TOU_group#11.month

xlincom  1.TOU_group#12.month



* Graph
matrix Coefficients = J(1, 6, .)
matrix CI = J(2,6,.)

forvalues i=7(1)12{
	xlincom  1.TOU_group#`i'.month

	matrix Coefficients[1,`i'-6]=r(table)[1,1]
	matrix CI[1,`i'-6]=r(table)[5,1]
	matrix CI[2,`i'-6]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13) ///
 ytitle("Charge kWh") xtitle("Month") yline(0) ylabel(-0.5(0.5)0.6) xlabel ( 1 "July" 2 "August" 3 "September" 4 "October" 5 "November" 6 "December") graphregion(color(white)) ///
			 note("", size(7pt))

** Export graph
  graph export "$results/FigureB2a.pdf", replace  	
		
 
** TOU marginal effect - Off-PEAK 

xlincom  1.TOU_group#7.month + 1.off_peak#7.month#1.TOU_group

xlincom  1.TOU_group#8.month + 1.off_peak#8.month#1.TOU_group

xlincom  1.TOU_group#9.month + 1.off_peak#9.month#1.TOU_group

xlincom  1.TOU_group#10.month + 1.off_peak#10.month#1.TOU_group

xlincom  1.TOU_group#11.month + 1.off_peak#11.month#1.TOU_group

xlincom  1.TOU_group#12.month + 1.off_peak#12.month#1.TOU_group

 
* Graph
matrix Coefficients = J(1, 6, .)
matrix CI = J(2,6,.)

forvalues i=7(1)12{
	xlincom  1.TOU_group#`i'.month + 1.off_peak#`i'.month#1.TOU_group

	matrix Coefficients[1,`i'-6]=r(table)[1,1]
	matrix CI[1,`i'-6]=r(table)[5,1]
	matrix CI[2,`i'-6]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13) ///
 ytitle("Charge kWh") xtitle("Month") yline(0) ylabel(-0.5(0.5)0.6) xlabel ( 1 "July" 2 "August" 3 "September" 4 "October" 5 "November" 6 "December") graphregion(color(white)) ///
			 note("", size(7pt))

** Export graph
  graph export "$results/FigureB2b.pdf", replace 
  
 
** Managed marginal effect - PEAK 

xlincom  1.Managed_group#7.month

xlincom  1.Managed_group#8.month

xlincom  1.Managed_group#9.month

xlincom  1.Managed_group#10.month

xlincom  1.Managed_group#11.month

xlincom  1.Managed_group#12.month

 
* Graph
matrix Coefficients = J(1, 6, .)
matrix CI = J(2,6,.)

forvalues i=7(1)12{
	xlincom  1.Managed_group#`i'.month

	
	matrix Coefficients[1,`i'-6]=r(table)[1,1]
	matrix CI[1,`i'-6]=r(table)[5,1]
	matrix CI[2,`i'-6]=r(table)[6,1]
}
coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13) ///
 ytitle("Charge kWh") xtitle("Month") yline(0) ylabel(-0.5(0.5)0.6) xlabel ( 1 "July" 2 "August" 3 "September" 4 "October" 5 "November" 6 "December") graphregion(color(white)) ///
			 note("", size(7pt))
			 
** Export graph
  graph export "$results/FigureB2c.pdf", replace   	   	
 	

** Managed marginal effect - Off-PEAK 

xlincom  1.Managed_group#7.month + 1.off_peak#7.month#1.Managed_group

xlincom  1.Managed_group#8.month + 1.off_peak#8.month#1.Managed_group

xlincom  1.Managed_group#9.month + 1.off_peak#9.month#1.Managed_group

xlincom  1.Managed_group#10.month + 1.off_peak#10.month#1.Managed_group

xlincom  1.Managed_group#11.month + 1.off_peak#11.month#1.Managed_group

xlincom  1.Managed_group#12.month + 1.off_peak#12.month#1.Managed_group
 
* Graph
matrix Coefficients = J(1, 6, .)
matrix CI = J(2,6,.)

forvalues i=7(1)12{
	xlincom  1.Managed_group#`i'.month + 1.off_peak#`i'.month#1.Managed_group

	matrix Coefficients[1,`i'-6]=r(table)[1,1]
	matrix CI[1,`i'-6]=r(table)[5,1]
	matrix CI[2,`i'-6]=r(table)[6,1]
}
coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13) ///
 ytitle("Constraint Violation kWh") xtitle("Month") yline(0) ylabel(-0.5(0.5)0.6) xlabel ( 1 "July" 2 "August" 3 "September" 4 "October" 5 "November" 6 "December") graphregion(color(white)) ///
			 note("", size(7pt))

** Export graph
graph export "$results/FigureB2d.pdf", replace	 	


********************************************************************************
********************************************************************************
** Cluster Robustness
********************************************************************************
********************************************************************************
 
** Cluster at the EV-level for all groups 

** TOU marginal effect 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster vehicle_id)
		
xlincom  1.TOU_group#1.Post_Treat, post
est store kwh_tou_post_clEV 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster vehicle_id)
xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak, post
est store kwh_tou_post_offp_clEV 
	
** Managed marginal effect 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster vehicle_id)
xlincom  1.Managed_group#1.Post_Treat, post
est store kwh_man_post_clEV 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster vehicle_id)
xlincom  1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak, post
est store kwh_man_post_offp_clEV 
					
** Test for differences across TOU and Managed 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster vehicle_id)
xlincom 1.TOU_group#1.Post_Treat - 1.Managed_group#1.Post_Treat, post
est store kwh_tou_man_post_clEV

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster vehicle_id)
test 1.TOU_group#1.Post_Treat = 1.Managed_group#1.Post_Treat	

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster vehicle_id)
xlincom 	 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak   - (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak), post
est store kwh_tou_man_post_offp_clEV
		
quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster vehicle_id)
test 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak   = (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )	
	
	
	
** Cluster at the EV-level for TOU and Control, Transformer for Managed

** TOU marginal effect 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
xlincom  1.TOU_group#1.Post_Treat, post
est store kwh_tou_post_clG 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak, post
est store kwh_tou_post_offp_clG  
	
** Managed marginal effect 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
xlincom  1.Managed_group#1.Post_Treat, post
est store kwh_man_post_clG  

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
xlincom  1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak, post
est store kwh_man_post_offp_clG  
					
** Test for differences across TOU and Managed 

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
xlincom 1.TOU_group#1.Post_Treat - 1.Managed_group#1.Post_Treat, post
est store kwh_tou_man_post_clG

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
test 1.TOU_group#1.Post_Treat = 1.Managed_group#1.Post_Treat	

quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
xlincom 	 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak   - (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak), post
est store kwh_tou_man_post_offp_clG
		
quietly reghdfe kWh_added_hour_home  ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						     ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(vehicle_id date hour_start) vce(cluster group_cluster)
test 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak   = (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )	
	

* Create results output

esttab kwh_tou_post_clEV kwh_tou_post_clG using "$results/Table C3.csv", noobs rename(lc_1 "TOU Peak") ///
cells(b(fmt(3)) se(par fmt(3))) title("Table C3. Estimated Treatment Effects by Group - Charge kWh with Alternative Clustering") ///
collabels(,none) mtitles("Charge kWh" "Charge kWh") replace

esttab kwh_tou_post_offp_clEV kwh_tou_post_offp_clG using "$results/Table C3.csv", noobs rename(lc_1 "TOU Off-Peak") ///
cells(b(fmt(3)) se(par fmt(3))) collabels(,none) mlabels(,none) nonumbers append

esttab kwh_man_post_clEV kwh_man_post_clG using "$results/Table C3.csv", noobs rename(lc_1 "Managed Peak") ///
cells(b(fmt(3)) se(par fmt(3))) collabels(,none) mlabels(,none) nonumbers append

esttab kwh_man_post_offp_clEV kwh_man_post_offp_clG using "$results/Table C3.csv", noobs rename(lc_1 "Managed Off-Peak") ///
cells(b(fmt(3)) se(par fmt(3))) collabels(,none) mlabels(,none) nonumbers addnotes("") append

esttab kwh_tou_man_post_clEV kwh_tou_man_post_clG using "$results/Table C3.csv", cells(b(fmt(3)) p(par fmt(3))) ///
noobs title("Treatment Effect Comparison") rename(lc_1 "TOU-Managed Peak (p-value)") collabels(,none) mlabels(,none) nonumbers append

esttab kwh_tou_man_post_offp_clEV kwh_tou_man_post_offp_clG using "$results/Table C3.csv", cells(b(fmt(3)) p(par fmt(3))) ///
rename(lc_1 "TOU-Managed Off-Peak (p-value)") collabels(,none) mlabels(,none) nonumbers ///
addnotes("" "") append



********************************************************************************
********************************************************************************
************* Regression Analysis: Transformer Violations  *********************
************* Construct a panel data set to do regression analysis *************
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
** Remove days with "DR Events"
*******

drop if date == td(11aug2023)
drop if date == td(12aug2023)
drop if date == td(28aug2023)
drop if date == td(22nov2023)


********************************************************************************
********************************************************************************
** Transformer-Level: Regression Analysis 
********************************************************************************
********************************************************************************

** Collapse to the transformer-day-hour level, summing up the amount charged at home 

collapse (max) transformer evloadlimit  evloadlimit_adj EV_Count_on constraint (firstnm) group (sum) kWh_added_hour_home kWh_added_hour, by(treatment date hour_start)

** Regressions below categorize days as being a low, medium, or high constraint day 

tab constraint

gen Constraint_Category = . 
replace Constraint_Category = 1 if  constraint >19  
replace Constraint_Category = 2 if  constraint > 15 & constraint <= 19  
replace Constraint_Category = 3 if  constraint <= 15

** Create time-based controls 

gen year = year(date)

gen month = month(date)

gen day = day(date)

egen year_month = group(year month)

gen dow = dow( mdy( month, day, year) )

gen week = week(date)

egen Transformer_Week = group(treatment year week)

egen hour_sample = group(date hour_start)

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

gen Transformer_Space = evloadlimit - kWh_added_hour_home

gen Transformer_Space_adj = evloadlimit_adj - kWh_added_hour_home

gen Violation_KWhs = 0 
replace Violation_KWhs = -1*Transformer_Space if Transformer_Space < 0 

gen Violation_KWhs_adj = 0 
replace Violation_KWhs_adj = -1*Transformer_Space_adj if Transformer_Space_adj < 0 

********
** Group by Post-Treatment Interactions - Off-Peak Interaction 
********

** Adjusted Measure - with additional fixed effects 

** TOU marginal effect 

quietly reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
						
xlincom  1.TOU_group#1.Post_Treat, post
matrix b = e(b)
scalar viol_tou_post_coeff = b[1,1]
est store viol_tou_post 

quietly reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak, post
matrix b = e(b)
scalar viol_tou_post_offp_coeff = b[1,1]
est store viol_tou_post_offp 

	
** Managed marginal effect 

quietly reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
xlincom  1.Managed_group#1.Post_Treat, post
matrix b = e(b)
scalar viol_man_post_coeff = b[1,1]
est store viol_man_post 


quietly reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
xlincom  1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak, post
matrix b = e(b)
scalar viol_man_post_offp_coeff = b[1,1]
est store viol_man_post_offp 

eststo sum_viol_kwh_adj_T: estpost sum Violation_KWhs_adj if group == "T" & Post_Treat == 0 & off_peak == 0 
eststo sum_viol_kwh_adj_M: estpost sum Violation_KWhs_adj if group == "M" & Post_Treat == 0 & off_peak == 0 
eststo sum_viol_kwh_adj_Cpost: estpost sum Violation_KWhs_adj if treat!= "C7" &  group == "C" & Post_Treat == 1 & off_peak == 0 

eststo sum_viol_kwh_adj_T_offp: estpost sum Violation_KWhs_adj if group == "T" & Post_Treat == 0 & off_peak == 1 
eststo sum_viol_kwh_adj_M_offp: estpost sum Violation_KWhs_adj if group == "M" & Post_Treat == 0 & off_peak == 1 
eststo sum_viol_kwh_adj_Cpost_offp: estpost sum Violation_KWhs_adj if treat!= "C7" & group == "C" & Post_Treat == 1 & off_peak == 1 

** Test for differences across TOU and Managed 

quietly reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
xlincom 1.TOU_group#1.Post_Treat - 1.Managed_group#1.Post_Treat, post
matrix b = e(b)
scalar viol_tou_man_post_coeff = b[1,1]
est store viol_tou_man_post 

quietly reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
test 1.TOU_group#1.Post_Treat = 1.Managed_group#1.Post_Treat	

quietly reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
xlincom 	 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak - (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak ), post
matrix b = e(b)
scalar viol_tou_man_post_offp_coeff = b[1,1]
est store viol_tou_man_post_offp 
		
quietly reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
test 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak = (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )	


esttab kwh_tou_post viol_tou_post using "$results/Table 2.csv", noobs rename(lc_1 "TOU Peak") ///
cells(b(fmt(3)) se(par fmt(3))) title("Table 2. Estimated Transformer-Level Treatment Effects by Group") ///
collabels(,none) mtitles("Charge kWh" "Constraint Violations") replace

esttab kwh_tou_post_offp viol_tou_post_offp using "$results/Table 2.csv", noobs rename(lc_1 "TOU Off-Peak") ///
cells(b(fmt(3)) se(par fmt(3))) collabels(,none) mlabels(,none) nonumbers append

esttab kwh_man_post viol_man_post using "$results/Table 2.csv", noobs rename(lc_1 "Managed Peak") ///
cells(b(fmt(3)) se(par fmt(3))) collabels(,none) mlabels(,none) nonumbers append

esttab kwh_man_post_offp viol_man_post_offp using "$results/Table 2.csv", noobs rename(lc_1 "Managed Off-Peak") ///
cells(b(fmt(3)) se(par fmt(3))) collabels(,none) mlabels(,none) nonumbers addnotes("") append

esttab kwh_tou_man_post viol_tou_man_post using "$results/Table 2.csv", cells(b(fmt(3)) p(par fmt(3))) ///
noobs title("Treatment Effect Comparison") rename(lc_1 "TOU-Managed Peak (p-value)") collabels(,none) mlabels(,none) nonumbers append

esttab kwh_tou_man_post_offp viol_tou_man_post_offp using "$results/Table 2.csv", cells(b(fmt(3)) p(par fmt(3))) ///
rename(lc_1 "TOU-Managed Off-Peak (p-value)") noobs collabels(,none) mlabels(,none) nonumbers append

esttab sum_kwh_home_C_post sum_viol_kwh_adj_Cpost using "$results/Table 2.csv", cells(mean(fmt(3))) ///
noobs title("Mean Dep. Var. (Post-Treatment)") ///
rename("kWh_added_hour_home" "Control Peak" "Violation_KWhs_adj" "Control Peak") ///
collabels(,none) mlabels(,none) nonumbers append

esttab sum_kwh_home_C_post_offp sum_viol_kwh_adj_Cpost_offp using "$results/Table 2.csv", cells(mean(fmt(3))) ///
noobs rename("kWh_added_hour_home" "Control Off-Peak" "Violation_KWhs_adj" "Control Off-Peak") ///
collabels(,none) mlabels(,none) nonumbers addnotes("") append

esttab kwh_tou_man_post_offp viol_tou_man_post_offp using "$results/Table 2.csv", ///
drop(*) cells(b(fmt(0)) p(par fmt(0))) stats(N, labels("Observations")) nogaps ///
nolegend collabels(,none) mlabels(,none) nonumbers append
		
********
** Group by Post-Treatment Interactions - Allow Effects to differ by hour  				
********

** Adjusted measure - with additional fixed effects 

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib21.hour_start  ///
								ib0.Managed_group##ib0.Post_Treat##ib21.hour_start /// 
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)

** TOU Effects	

forvalues i = 0(1)23{ 
	
xlincom 1.TOU_group#1.Post_Treat  +  1.TOU_group#1.Post_Treat#`i'.hour_start 
 
}

* Graph
matrix Coefficients = J(1, 24, .)
matrix CI = J(2,24,.)

forvalues i=0(1)23{
	
xlincom 1.TOU_group#1.Post_Treat  +  1.TOU_group#1.Post_Treat#`i'.hour_start 
 
	matrix Coefficients[1,`i'+1]=r(table)[1,1]
	matrix CI[1,`i'+1]=r(table)[5,1]
	matrix CI[2,`i'+1]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13)  ///
 ytitle("kWh") xtitle("Hour") yline(0) ylabel(-4(1)5) yscale(range(-4 5)) xlabel ( 1 "0" 2 "1" 3 "2" 4 "3" 5 "4" 6 "5" 7 "6" 8 "7" 9 "8" 10 "9" 11 "10" 12 "11" 13 "12" 14 "13" 15 "14" 16 "15" 17 "16" 18 "17" 19 "18" 20 "19" 21 "20" 22 "21" 23 "22" 24 "23") graphregion(color(white)) ///
			 note("", size(7pt)) name(TOU_Violations_Hourly ,replace)  title("TOU")
			 
	
sum Violation_KWhs_adj if Post_Treat == 0  & group == "T"
	 
** Managed Effects  
	 

forvalues i = 0(1)23{ 
lincom 1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#`i'.hour_start 

}
	
* Graph
matrix Coefficients = J(1, 24, .)
matrix CI = J(2,24,.)

forvalues i=0(1)23{
	
xlincom 1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#`i'.hour_start 
 
	matrix Coefficients[1,`i'+1]=r(table)[1,1]
	matrix CI[1,`i'+1]=r(table)[5,1]
	matrix CI[2,`i'+1]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13)  ///
 ytitle("kWh") xtitle("Hour") yline(0) ylabel(-4(1)5) yscale(range(-4 5)) xlabel ( 1 "0" 2 "1" 3 "2" 4 "3" 5 "4" 6 "5" 7 "6" 8 "7" 9 "8" 10 "9" 11 "10" 12 "11" 13 "12" 14 "13" 15 "14" 16 "15" 17 "16" 18 "17" 19 "18" 20 "19" 21 "20" 22 "21" 23 "22" 24 "23") graphregion(color(white)) ///
			 note("", size(7pt)) name(Managed_Violations_Hourly ,replace) title("Managed")
			 
sum Violation_KWhs_adj if Post_Treat == 0 & group == "M"

sleep 2000

grc1leg2 TOU_Violations_Hourly Managed_Violations_Hourly  , cols(1) loff graphregion(color(white) )   name(grc1leggraph ,replace)
gr draw grc1leggraph,  ysize(3.5) xsize(2.5)

graph export "$results/Figure3b.pdf", replace


********************************************************************************
********************************************************************************
** Heterogeneous Effects by Peak/Off-Peak and Month 
********************************************************************************
********************************************************************************

** Create post-group-off-peak to facilitate month effects 
gen TOU_Post_Off = TOU_Post*off_peak

gen Managed_Post_Off = Managed_Post*off_peak

** Deal with the fact that the first 4 days of July were pre-treatment - Place with June
replace month = 6 if month == 7 & date <= td(04july2023)

*************************
** Specification with peak/off-peak differential - Violation kWhs AdjustedMeasure - Additional FEs
*************************		

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.off_peak##ib6.month ///
						   ib0.Managed_group##ib0.off_peak##ib6.month ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
				
** TOU marginal effect - PEAK 

xlincom  1.TOU_group#7.month

xlincom  1.TOU_group#8.month

xlincom  1.TOU_group#9.month

xlincom  1.TOU_group#10.month

xlincom  1.TOU_group#11.month

xlincom  1.TOU_group#12.month


* Graph
matrix Coefficients = J(1, 6, .)
matrix CI = J(2,6,.)

forvalues i=7(1)12{
	xlincom  1.TOU_group#`i'.month

	matrix Coefficients[1,`i'-6]=r(table)[1,1]
	matrix CI[1,`i'-6]=r(table)[5,1]
	matrix CI[2,`i'-6]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13)  ///
 ytitle("Constraint Violation kWh") xtitle("Month") yline(0) ylabel(-2(1)2) xlabel ( 1 "July" 2 "August" 3 "September" 4 "October" 5 "November" 6 "December") graphregion(color(white)) ///
			 note("", size(7pt))

** Export graph
  graph export "$results/FigureB1a.pdf", replace  	

	
** TOU marginal effect - Off-PEAK 

xlincom  1.TOU_group#7.month + 1.off_peak#7.month#1.TOU_group

xlincom  1.TOU_group#8.month + 1.off_peak#8.month#1.TOU_group

xlincom  1.TOU_group#9.month + 1.off_peak#9.month#1.TOU_group

xlincom  1.TOU_group#10.month + 1.off_peak#10.month#1.TOU_group

xlincom  1.TOU_group#11.month + 1.off_peak#11.month#1.TOU_group

xlincom  1.TOU_group#12.month + 1.off_peak#12.month#1.TOU_group


* Graph
matrix Coefficients = J(1, 6, .)
matrix CI = J(2,6,.)

forvalues i=7(1)12{
	xlincom  1.TOU_group#`i'.month + 1.off_peak#`i'.month#1.TOU_group

	matrix Coefficients[1,`i'-6]=r(table)[1,1]
	matrix CI[1,`i'-6]=r(table)[5,1]
	matrix CI[2,`i'-6]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13)  ///
 ytitle("Constraint Violation kWh") xtitle("Month") yline(0) ylabel(-2(1)2) xlabel ( 1 "July" 2 "August" 3 "September" 4 "October" 5 "November" 6 "December") graphregion(color(white)) ///
			 note("", size(7pt))

** Export graph
  graph export "$results/FigureB1b.pdf", replace 


** Managed marginal effect - PEAK 

xlincom  1.Managed_group#7.month

xlincom  1.Managed_group#8.month

xlincom  1.Managed_group#9.month

xlincom  1.Managed_group#10.month

xlincom  1.Managed_group#11.month

xlincom  1.Managed_group#12.month


* Graph
matrix Coefficients = J(1, 6, .)
matrix CI = J(2,6,.)

forvalues i=7(1)12{
	xlincom  1.Managed_group#`i'.month

	
	matrix Coefficients[1,`i'-6]=r(table)[1,1]
	matrix CI[1,`i'-6]=r(table)[5,1]
	matrix CI[2,`i'-6]=r(table)[6,1]
}
coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13)  ///
 ytitle("Constraint Violation kWh") xtitle("Month") yline(0) ylabel(-2(1)2) xlabel ( 1 "July" 2 "August" 3 "September" 4 "October" 5 "November" 6 "December") graphregion(color(white)) ///
			 note("", size(7pt))

** Export graph
graph export "$results/FigureB1c.pdf", replace   	

** Managed marginal effect - Off-PEAK 

xlincom  1.Managed_group#7.month + 1.off_peak#7.month#1.Managed_group

xlincom  1.Managed_group#8.month + 1.off_peak#8.month#1.Managed_group

xlincom  1.Managed_group#9.month + 1.off_peak#9.month#1.Managed_group

xlincom  1.Managed_group#10.month + 1.off_peak#10.month#1.Managed_group

xlincom  1.Managed_group#11.month + 1.off_peak#11.month#1.Managed_group

xlincom  1.Managed_group#12.month + 1.off_peak#12.month#1.Managed_group
 

* Graph
matrix Coefficients = J(1, 6, .)
matrix CI = J(2,6,.)

forvalues i=7(1)12{
	xlincom  1.Managed_group#`i'.month + 1.off_peak#`i'.month#1.Managed_group

	matrix Coefficients[1,`i'-6]=r(table)[1,1]
	matrix CI[1,`i'-6]=r(table)[5,1]
	matrix CI[2,`i'-6]=r(table)[6,1]
}
coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13)  ///
 ytitle("Constraint Violation kWh") xtitle("Month") yline(0) ylabel(-2(1)2) xlabel ( 1 "July" 2 "August" 3 "September" 4 "October" 5 "November" 6 "December") graphregion(color(white)) ///
			 note("", size(7pt))

** Export graph
  graph export "$results/FigureB1d.pdf", replace   	
	

********************************************************************************
********************************************************************************
** Cluster Robustness 
********************************************************************************
********************************************************************************
	
*********
** Clustering: Transformer level with wild bootstrap 
** Works after reghdfe only if there is a single FE in absorb
** Manually do the FEs in the regression with factor variables 
** Note. Marginal effects are consistent to the main specification with these FEs in absorb 
** Reference (boottest): https://www.econ.queensu.ca/sites/econ.queensu.ca/files/qed_wp_1406.pdf 
*********		

** ssc install boottest

********************************************************************************
** Dependent Variable: Violation KWhs  
********************************************************************************

** First, store the baseline model with clustered SEs 

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
						
** TOU marginal effect 

xlincom  1.TOU_group#1.Post_Treat 

xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak 
	
** Managed marginal effect 

xlincom  1.Managed_group#1.Post_Treat 

xlincom  1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak 

** Test for differences across TOU and Managed 

lincom 1.TOU_group#1.Post_Treat - 1.Managed_group#1.Post_Treat

test 1.TOU_group#1.Post_Treat = 1.Managed_group#1.Post_Treat	

lincom 	 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak - (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )
		
test 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak = (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )	


** Now use boottest to carry out wild bootstrap 

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak ///
								i.transformer_group i.hour_start ///
        , absorb(date) vce(robust)
						
** TOU marginal effect 

xlincom  1.TOU_group#1.Post_Treat 

boottest 1.TOU_group#1.Post_Treat = 0 , reps (9999) seed(12345) nograph cluster(transformer_group)
matrix ci_tou_post = r(CI)
scalar ll_tou_post = ci_tou_post[1,1]
scalar ul_tou_post = ci_tou_post[1,2]
scalar pval_tou_post = r(p)
	
xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak 
		
boottest 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak  = 0 , reps (9999) seed(12345) nograph cluster(transformer_group)
matrix ci_tou_post_offp = r(CI)
scalar ll_tou_post_offp = ci_tou_post_offp[1,1]
scalar ul_tou_post_offp = ci_tou_post_offp[1,2]
scalar pval_tou_post_offp = r(p)
	
** Managed marginal effect 

xlincom  1.Managed_group#1.Post_Treat 

boottest 1.Managed_group#1.Post_Treat  = 0 , reps (9999) seed(12345) nograph cluster(transformer_group)
matrix ci_man_post = r(CI)
scalar ll_man_post = ci_man_post[1,1]
scalar ul_man_post = ci_man_post[1,2]
scalar pval_man_post = r(p)

xlincom  1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak 

boottest  1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak = 0 , reps (9999) seed(12345) nograph cluster(transformer_group)
matrix ci_man_post_offp = r(CI)
scalar ll_man_post_offp = ci_man_post_offp[1,1]
scalar ul_man_post_offp = ci_man_post_offp[1,2]
scalar pval_man_post_offp = r(p)


** Test for differences across TOU and Managed 

lincom 1.TOU_group#1.Post_Treat - 1.Managed_group#1.Post_Treat

boottest  1.TOU_group#1.Post_Treat - 1.Managed_group#1.Post_Treat = 0 , reps (9999) seed(12345) nograph cluster(transformer_group)
matrix ci_tou_man_post = r(CI)
scalar ll_tou_man_post = ci_tou_man_post[1,1]
scalar ul_tou_man_post = ci_tou_man_post[1,2]
scalar pval_tou_man_post = r(p)

lincom 	 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak   - (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak)
		
boottest  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak - 1.Managed_group#1.Post_Treat  -  1.Managed_group#1.Post_Treat#1.off_peak = 0 , reps (9999) seed(12345) nograph cluster(transformer_group)
matrix ci_tou_man_post_offp = r(CI)
scalar ll_tou_man_post_offp = ci_tou_man_post_offp[1,1]
scalar ul_tou_man_post_offp = ci_tou_man_post_offp[1,2]
scalar pval_tou_man_post_offp = r(p)

scalar obs_C4 = e(N)


****
** Removing Managed - to be used in the Alternative Transformer Constration Comparison
****

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak /// 
								i.transformer_group i.hour_start if group != "M" ///
        , absorb(date) vce(robust)	
	
** TOU marginal effect 

xlincom  1.TOU_group#1.Post_Treat, post
matrix b = e(b)
scalar viol_tou_alt_coeff = b[1,1]  

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak /// 
								i.transformer_group i.hour_start if group != "M" ///
        , absorb(date) vce(robust)	
boottest 1.TOU_group#1.Post_Treat = 0 , reps (9999) seed(12345) nograph cluster(transformer_group)
matrix ci_viol_tou_alt = r(CI)
scalar ll_viol_tou_alt = ci_viol_tou_alt[1,1]
scalar ul_viol_tou_alt = ci_viol_tou_alt[1,2]
scalar pval_viol_tou_alt = r(p)
	
reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak /// 
								i.transformer_group i.hour_start if group != "M" ///
        , absorb(date) vce(robust)	
xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak, post
matrix b = e(b)
scalar viol_tou_offp_alt_coeff = b[1,1] 
		
reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak /// 
								i.transformer_group i.hour_start if group != "M" ///
        , absorb(date) vce(robust)	
boottest 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak  = 0 , reps (9999) seed(12345) nograph cluster(transformer_group)
matrix ci_viol_tou_offp_alt = r(CI)
scalar ll_viol_tou_offp_alt = ci_viol_tou_offp_alt[1,1]
scalar ul_viol_tou_offp_alt = ci_viol_tou_offp_alt[1,2]
scalar pval_viol_tou_offp_alt = r(p)

scalar obs = e(N)


********************************************************************************
********************************************************************************
** Breaking down the numbers by constraint bands 
********************************************************************************
********************************************************************************


** Main Specification - full sample 

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak  ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
						
** TOU marginal effect 

xlincom  1.TOU_group#1.Post_Treat 

xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak 
	
** Managed marginal effect 

xlincom  1.Managed_group#1.Post_Treat 

xlincom  1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak 

** Test for differences across TOU and Managed 

lincom 1.TOU_group#1.Post_Treat - 1.Managed_group#1.Post_Treat

test 1.TOU_group#1.Post_Treat = 1.Managed_group#1.Post_Treat	

lincom 	 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak - (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )
		
test 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak = (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )	



** Constraint Category 1 (Most lax constraint)

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak if Constraint_Category == 1 	 ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
						
** TOU marginal effect 

xlincom  1.TOU_group#1.Post_Treat 

xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak 
	
** Managed marginal effect 

xlincom  1.Managed_group#1.Post_Treat 

xlincom  1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak 

** Test for differences across TOU and Managed 

lincom 1.TOU_group#1.Post_Treat - 1.Managed_group#1.Post_Treat

test 1.TOU_group#1.Post_Treat = 1.Managed_group#1.Post_Treat	

lincom 	 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak - (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )
		
test 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak = (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )	


** Constraint Category 2 (Middle constraint)

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak if Constraint_Category == 2 	 ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
						
** TOU marginal effect 

xlincom  1.TOU_group#1.Post_Treat 

xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak 
	
** Managed marginal effect 

xlincom  1.Managed_group#1.Post_Treat 

xlincom  1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak 

** Test for differences across TOU and Managed 

lincom 1.TOU_group#1.Post_Treat - 1.Managed_group#1.Post_Treat

test 1.TOU_group#1.Post_Treat = 1.Managed_group#1.Post_Treat	

lincom 	 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak - (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )
		
test 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak = (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )	


** Constraint Category 3 (Tightest constraint)

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib0.off_peak ///
						   ib0.Managed_group##ib0.Post_Treat##ib0.off_peak if Constraint_Category == 3 	 ///
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)
						
** TOU marginal effect 

xlincom  1.TOU_group#1.Post_Treat 

xlincom  1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak 
	
** Managed marginal effect 

xlincom  1.Managed_group#1.Post_Treat 

xlincom  1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak 

** Test for differences across TOU and Managed 

lincom 1.TOU_group#1.Post_Treat - 1.Managed_group#1.Post_Treat

test 1.TOU_group#1.Post_Treat = 1.Managed_group#1.Post_Treat	

lincom 	 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak - (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )
		
test 1.TOU_group#1.Post_Treat + 1.TOU_group#1.Post_Treat#1.off_peak = (1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#1.off_peak )	


*******************************************************
** Allowing the effects to vary by hour and Constraint 
******************************************************* 

** Adjusted measure - with additional fixed effects 

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib21.hour_start  ///
								ib0.Managed_group##ib0.Post_Treat##ib21.hour_start if Constraint_Category == 1 /// 
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)

** TOU Effects	

forvalues i = 0(1)23{ 
	
xlincom 1.TOU_group#1.Post_Treat  +  1.TOU_group#1.Post_Treat#`i'.hour_start 
 
}

* Graph
matrix Coefficients = J(1, 24, .)
matrix CI = J(2,24,.)

forvalues i=0(1)23{
	
xlincom 1.TOU_group#1.Post_Treat  +  1.TOU_group#1.Post_Treat#`i'.hour_start 
 
	matrix Coefficients[1,`i'+1]=r(table)[1,1]
	matrix CI[1,`i'+1]=r(table)[5,1]
	matrix CI[2,`i'+1]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13)  ///
 ytitle("kWh") xtitle("Hour") yline(0) ylabel(-3(1)6) yscale(range(-3 6.5)) xlabel ( 1 "0" 2 "1" 3 "2" 4 "3" 5 "4" 6 "5" 7 "6" 8 "7" 9 "8" 10 "9" 11 "10" 12 "11" 13 "12" 14 "13" 15 "14" 16 "15" 17 "16" 18 "17" 19 "18" 20 "19" 21 "20" 22 "21" 23 "22" 24 "23") graphregion(color(white)) ///
			 note("", size(7pt)) name(TOU_Violations_Hourly ,replace)  
		
graph export "$results/FigureC2a.pdf", replace 
		
** Managed Effects  
	 

forvalues i = 0(1)23{ 
lincom 1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#`i'.hour_start 

}
	
* Graph
matrix Coefficients = J(1, 24, .)
matrix CI = J(2,24,.)

forvalues i=0(1)23{
	
xlincom 1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#`i'.hour_start 
 
	matrix Coefficients[1,`i'+1]=r(table)[1,1]
	matrix CI[1,`i'+1]=r(table)[5,1]
	matrix CI[2,`i'+1]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13)  ///
 ytitle("kWh") xtitle("Hour") yline(0) ylabel(-3(1)6) yscale(range(-3 6.5)) xlabel ( 1 "0" 2 "1" 3 "2" 4 "3" 5 "4" 6 "5" 7 "6" 8 "7" 9 "8" 10 "9" 11 "10" 12 "11" 13 "12" 14 "13" 15 "14" 16 "15" 17 "16" 18 "17" 19 "18" 20 "19" 21 "20" 22 "21" 23 "22" 24 "23") graphregion(color(white)) ///
			 note("", size(7pt)) name(Managed_Violations_Hourly ,replace) 
			
graph export "$results/FigureC3a.pdf", replace 
			
** Adjusted measure - with additional fixed effects 

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib21.hour_start  ///
								ib0.Managed_group##ib0.Post_Treat##ib21.hour_start if Constraint_Category == 2 /// 
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)

** TOU Effects	

forvalues i = 0(1)23{ 
	
xlincom 1.TOU_group#1.Post_Treat  +  1.TOU_group#1.Post_Treat#`i'.hour_start 
 
}

* Graph
matrix Coefficients = J(1, 24, .)
matrix CI = J(2,24,.)

forvalues i=0(1)23{
	
xlincom 1.TOU_group#1.Post_Treat  +  1.TOU_group#1.Post_Treat#`i'.hour_start 
 
	matrix Coefficients[1,`i'+1]=r(table)[1,1]
	matrix CI[1,`i'+1]=r(table)[5,1]
	matrix CI[2,`i'+1]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13)  ///
 ytitle("kWh") xtitle("Hour") yline(0) ylabel(-3(1)6) yscale(range(-3 6.5)) xlabel ( 1 "0" 2 "1" 3 "2" 4 "3" 5 "4" 6 "5" 7 "6" 8 "7" 9 "8" 10 "9" 11 "10" 12 "11" 13 "12" 14 "13" 15 "14" 16 "15" 17 "16" 18 "17" 19 "18" 20 "19" 21 "20" 22 "21" 23 "22" 24 "23") graphregion(color(white)) ///
			 note("", size(7pt)) name(TOU_Violations_Hourly ,replace)  
	
graph export "$results/FigureC2b.pdf", replace 
		
** Managed Effects  
	 

forvalues i = 0(1)23{ 
lincom 1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#`i'.hour_start 

}
	
* Graph
matrix Coefficients = J(1, 24, .)
matrix CI = J(2,24,.)

forvalues i=0(1)23{
	
xlincom 1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#`i'.hour_start 
 
	matrix Coefficients[1,`i'+1]=r(table)[1,1]
	matrix CI[1,`i'+1]=r(table)[5,1]
	matrix CI[2,`i'+1]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13)  ///
 ytitle("kWh") xtitle("Hour") yline(0) ylabel(-3(1)6) yscale(range(-3 6.5)) xlabel ( 1 "0" 2 "1" 3 "2" 4 "3" 5 "4" 6 "5" 7 "6" 8 "7" 9 "8" 10 "9" 11 "10" 12 "11" 13 "12" 14 "13" 15 "14" 16 "15" 17 "16" 18 "17" 19 "18" 20 "19" 21 "20" 22 "21" 23 "22" 24 "23") graphregion(color(white)) ///
			 note("", size(7pt)) name(Managed_Violations_Hourly ,replace) 
			 
graph export "$results/FigureC3b.pdf", replace 
		
sleep 1500 
grc1leg2 TOU_Violations_Hourly Managed_Violations_Hourly  , cols(1) loff graphregion(color(white) )   name(grc1leggraph ,replace)
gr draw grc1leggraph,  ysize(3.5) xsize(2.5)


 

** Adjusted measure - with additional fixed effects 

reghdfe Violation_KWhs_adj ib0.TOU_group##ib0.Post_Treat##ib21.hour_start  ///
								ib0.Managed_group##ib0.Post_Treat##ib21.hour_start if Constraint_Category == 3 /// 
        , absorb(transformer_group date hour_start) vce(cluster transformer_group)

** TOU Effects	

forvalues i = 0(1)23{ 
	
xlincom 1.TOU_group#1.Post_Treat  +  1.TOU_group#1.Post_Treat#`i'.hour_start 
 
}

* Graph
matrix Coefficients = J(1, 24, .)
matrix CI = J(2,24,.)

forvalues i=0(1)23{
	
xlincom 1.TOU_group#1.Post_Treat  +  1.TOU_group#1.Post_Treat#`i'.hour_start 
 
	matrix Coefficients[1,`i'+1]=r(table)[1,1]
	matrix CI[1,`i'+1]=r(table)[5,1]
	matrix CI[2,`i'+1]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13)  ///
 ytitle("kWh") xtitle("Hour") yline(0) ylabel(-3(1)6) yscale(range(-3 6.5)) xlabel ( 1 "0" 2 "1" 3 "2" 4 "3" 5 "4" 6 "5" 7 "6" 8 "7" 9 "8" 10 "9" 11 "10" 12 "11" 13 "12" 14 "13" 15 "14" 16 "15" 17 "16" 18 "17" 19 "18" 20 "19" 21 "20" 22 "21" 23 "22" 24 "23") graphregion(color(white)) ///
			 note("", size(7pt)) name(TOU_Violations_Hourly ,replace) 
			 
graph export "$results/FigureC2c.pdf", replace 
	
	
** Managed Effects  
	 

forvalues i = 0(1)23{ 
lincom 1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#`i'.hour_start 

}
	
* Graph
matrix Coefficients = J(1, 24, .)
matrix CI = J(2,24,.)

forvalues i=0(1)23{
	
xlincom 1.Managed_group#1.Post_Treat  +  1.Managed_group#1.Post_Treat#`i'.hour_start 
 
	matrix Coefficients[1,`i'+1]=r(table)[1,1]
	matrix CI[1,`i'+1]=r(table)[5,1]
	matrix CI[2,`i'+1]=r(table)[6,1]
}

coefplot matrix(Coefficients), ci(CI) ciopts(recast(rcap)) vertical pstyle(p13)  ///
 ytitle("kWh") xtitle("Hour") yline(0) ylabel(-3(1)6) yscale(range(-3 6.5)) xlabel ( 1 "0" 2 "1" 3 "2" 4 "3" 5 "4" 6 "5" 7 "6" 8 "7" 9 "8" 10 "9" 11 "10" 12 "11" 13 "12" 14 "13" 15 "14" 16 "15" 17 "16" 18 "17" 19 "18" 20 "19" 21 "20" 22 "21" 23 "22" 24 "23") graphregion(color(white)) ///
			 note("", size(7pt)) name(Managed_Violations_Hourly ,replace) 
			
graph export "$results/FigureC3c.pdf", replace 
			
sleep 1500 			 
grc1leg2 TOU_Violations_Hourly Managed_Violations_Hourly  , cols(1) loff graphregion(color(white) )   name(grc1leggraph ,replace)
gr draw grc1leggraph,  ysize(3.5) xsize(2.5)

****
* export results for Table C4, with Wild Bootstrap Cluster Robust s.e.
****

esttab viol_tou_post using "$results/Table C4.temp.csv", noobs rename(lc_1 "TOU Peak") ///
cells(b(fmt(3)) p(par fmt(3)) ci(par fmt(3))) title("Table C4. Estimated Treatment Effects by Group - Constraint Violation with Wild Bootstrap Cluster Robust Standard Errors") ///
collabels(,none) mtitles("Constraint Violations") plain replace

esttab viol_tou_post_offp using "$results/Table C4.temp.csv", noobs rename(lc_1 "TOU Off-Peak") ///
cells(b(fmt(3)) p(par fmt(3)) ci(par fmt(3))) collabels(,none) mlabels(,none) nonumbers plain append

esttab viol_man_post using "$results/Table C4.temp.csv", noobs rename(lc_1 "Managed Peak") ///
cells(b(fmt(3)) p(par fmt(3)) ci(par fmt(3))) collabels(,none) mlabels(,none) nonumbers plain append

esttab viol_man_post_offp using "$results/Table C4.temp.csv", noobs rename(lc_1 "Managed Off-Peak") ///
cells(b(fmt(3)) p(par fmt(3)) ci(par fmt(3))) collabels(,none) mlabels(,none) nonumbers addnotes("") plain append

esttab viol_tou_man_post using "$results/Table C4.temp.csv", cells(b(fmt(3)) p(par fmt(3)) ci(par fmt(3))) ///
noobs title("Treatment Effect Comparison") rename(lc_1 "TOU-Managed Peak") collabels(,none) mlabels(,none) ///
nonumbers plain append

esttab viol_tou_man_post_offp using "$results/Table C4.temp.csv", cells(b(fmt(3)) p(par fmt(3)) ci(par fmt(3))) ///
rename(lc_1 "TOU-Managed Off-Peak") collabels(,none) mlabels(,none) nonumbers plain ///
addnotes("This table provides the estimated treatment effects for the transformer-level Constraint Violations (in kWh), using at-home charging only" ///
"Column (1) presents the results from our main analysis with clustered standard errors at the transformer level." ///
"Column (2) clusters standard errors at the transformer level, but implements the wild cluster bootstrap." /// 
"p-values are reported in parentheses, below each coefficient." ///
"Confidence intervals are provided below p-values in brackets." ///
"All specifications include fixed effects at the transformer, day-of-sample, and hour-of-day level.")  append


* export results from boottest - column 2 in Table C4. 

scalar viol_tou_post_coeff = round(viol_tou_post_coeff, 0.001)
scalar viol_tou_post_offp_coeff = round(viol_tou_post_offp_coeff, 0.001)
scalar viol_man_post_coeff = round(viol_man_post_coeff, 0.001)
scalar viol_man_post_offp_coeff = round(viol_man_post_offp_coeff, 0.001)
scalar viol_tou_man_post_coeff = round(viol_tou_man_post_coeff, 0.001)
scalar viol_tou_man_post_offp_coeff = round(viol_tou_man_post_offp_coeff, 0.001)

scalar pval_tou_post = round(pval_tou_post, 0.001)
scalar pval_tou_post = "(" + string(pval_tou_post, "%9.3f") + ")"
scalar pval_tou_post_offp = round(pval_tou_post_offp, 0.001)
scalar pval_tou_post_offp = "(" + string(pval_tou_post_offp, "%9.3f") + ")"
scalar pval_man_post = round(pval_man_post, 0.001)
scalar pval_man_post = "(" + string(pval_man_post, "%9.3f") + ")"
scalar pval_man_post_offp = round(pval_man_post_offp, 0.001)
scalar pval_man_post_offp = "(" + string(pval_man_post_offp, "%9.3f") + ")"
scalar pval_tou_man_post = round(pval_tou_man_post,0.001)
scalar pval_tou_man_post = "(" + string(pval_tou_man_post, "%9.3f") + ")"
scalar pval_tou_man_post_offp = round(pval_tou_man_post_offp,0.001)
scalar pval_tou_man_post_offp = "(" + string(pval_tou_man_post_offp, "%9.3f") + ")"



scalar ci_tou_post = "[" + string(matrix(ll_tou_post), "%9.3f") + "," + string(matrix(ul_tou_post), "%9.3f") + "]"
scalar ci_tou_post_offp = "[" + string(matrix(ll_tou_post_offp), "%9.3f") + "," + string(matrix(ul_tou_post_offp), "%9.3f") + "]"
scalar ci_man_post = "[" + string(matrix(ll_man_post), "%9.3f") + "," + string(matrix(ul_man_post), "%9.3f") + "]"
scalar ci_man_post_offp = "[" + string(matrix(ll_man_post_offp), "%9.3f") + "," + string(matrix(ul_man_post_offp), "%9.3f") + "]"
scalar ci_tou_man_post = "[" + string(matrix(ll_tou_man_post), "%9.3f") + "," + string(matrix(ul_tou_man_post), "%9.3f") + "]"
scalar ci_tou_man_post_offp = "[" + string(matrix(ll_tou_man_post_offp), "%9.3f") + "," + string(matrix(ul_tou_man_post_offp), "%9.3f") + "]"

import delimited "$results/Table C4.temp.csv", clear
export excel using "$results/Table C4.xlsx", firstrow(variables) replace
putexcel set "$results/Table C4.xlsx", modify
putexcel C3 = "Constraint Violations" 
putexcel C4 = viol_tou_post_coeff
putexcel C5 = pval_tou_post
putexcel C6 = ci_tou_post

putexcel C7 = viol_tou_post_offp_coeff
putexcel C8 = pval_tou_post_offp 
putexcel C9 = ci_tou_post_offp

putexcel C10 = viol_man_post_coeff
putexcel C11 = pval_man_post 
putexcel C12 = ci_man_post

putexcel C13 = viol_man_post_offp_coeff
putexcel C14 = pval_man_post_offp 
putexcel C15 = ci_man_post_offp

putexcel C18 = viol_tou_man_post_coeff
putexcel C19 = pval_tou_man_post
putexcel C20 = ci_tou_man_post

putexcel C21 = viol_tou_man_post_offp_coeff
putexcel C22 = pval_tou_man_post_offp
putexcel C23 = ci_tou_man_post_offp

putexcel C24 = obs_C4

scalar viol_tou_alt_coeff = round(viol_tou_alt_coeff, 0.001)
scalar viol_tou_offp_alt_coeff = round(viol_tou_offp_alt_coeff, 0.001)
scalar ci_viol_tou_alt = "[" + string(matrix(ll_viol_tou_alt), "%9.3f") + "," + string(matrix(ul_viol_tou_alt), "%9.3f") + "]"
scalar ci_viol_tou_offp_alt = "[" + string(matrix(ll_viol_tou_offp_alt), "%9.3f") + "," + string(matrix(ul_viol_tou_offp_alt), "%9.3f") + "]"
scalar pval_viol_tou_alt = round(pval_viol_tou_alt, 0.001)
scalar pval_viol_tou_offp_alt = round(pval_viol_tou_offp_alt, 0.001)
scalar pval_viol_tou_alt = "(" + string(pval_viol_tou_alt, "%9.3f") + ")"
scalar pval_viol_tou_offp_alt = "(" + string(pval_viol_tou_offp_alt, "%9.3f") + ")"

putexcel set "$results/Table C5.xlsx", replace
putexcel A1 = "Group" 
putexcel B1 = "Hours"
putexcel C1 = "Baseline Transformers"
putexcel D1 = "Alt. Transformers 1"
putexcel E1 = "Alt. Transformers 2"
putexcel A8 = "Observations"

putexcel A2 = "TOU"
putexcel B2 = "Peak"
putexcel B5 = "Off-Peak"


putexcel C2 = viol_tou_alt_coeff
putexcel C3 = pval_viol_tou_alt	
putexcel C4 = ci_viol_tou_alt

putexcel C5 = viol_tou_offp_alt_coeff
putexcel C6 = pval_viol_tou_offp_alt	
putexcel C7 = ci_viol_tou_offp_alt

putexcel C8 = obs

 


