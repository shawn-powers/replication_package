********************************************************************************
********************************************************************************
************** Distribution Transformer Illustration ***************************
********************************************************************************
********************************************************************************

// SET DIRECTORY

global statapath "Insert Directory"
global data "$statapath/Data"
global panel "$statapath/Data/Panel"
global results "$statapath/Results"
global fortisdata "$statapath/Data/Fortis Data"


********************************************************************************
** Simplifed Figure - Low and High constraint 
********************************************************************************

use "$data/group limits_Adjusted.dta", clear

collapse (mean) loadtransgrp10 , by(hour)
 
** Work on graph with constraints 

gen constraint1 = 12 
gen EV_Room1 = constraint1 - loadtransgrp10 

gen constraint2 = 24 
gen EV_Room2 = constraint2 - loadtransgrp10 

** With Numbers 

twoway (scatteri 0 0 0 6 25 6 25 0, recast(area) color(gs14) ylabel(0 5 10 15 20 25) yscale(range(0, 25))   ) ///
	   (scatteri 0 10 0 14 25 14 25 10 , recast(area) color(gs14) ylabel(0 5 10 15 20 25) yscale(range(0, 25))  ) ///
	   (scatteri 0 22 0 23 25 23 25 22, recast(area) color(gs14)  ylabel(0 5 10 15 20 25) yscale(range(0, 25)) ) ///
	   (pcarrowi 8 1 23.5 1 8 1 5 1,  lcolor(black) mcolor(black) color(black) ) /// 
	   (pcarrowi 8 3 11.5 3 8 3 5 3,  lcolor(black) mcolor(black) color(black) ) /// 
	   (line loadtransgrp10  hour, color(black) lpattern(dash)) ///
       (line constraint1 constraint2 hour, color(black black) ), ///
	   text(9.45 19 "Residential Consumption", size(0.22cm)) ///
	   text(12.8 18 "Low Constraint", size(0.22cm)) ///
	   text(24.6 18 "High Constraint", size(0.22cm)) ///
	   text(8 5.7 "Low Headroom", size(0.22cm)) ///
	   text(18 3.7 "High Headroom", size(0.22cm)) ///
	   xlabel(0 6 12 18 23) graphregion(color(white) ) ytitle("kWs") xtitle("Hour") /// ///
	   ylabel(0 5 10 15 20 25) yscale(range(0, 25))  legend(off) name(Dist_Constraint_graph, replace)  ///
	   note("Note. Shaded areas represent off-peak hours")

gr draw Dist_Constraint_graph,  ysize(4) xsize(5)

graph export "$results/Figure1.pdf", replace 
		   
	
	  
	  
	  
