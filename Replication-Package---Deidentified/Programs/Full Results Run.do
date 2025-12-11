********************************************************************************
********************************************************************************
************* Master Do-File (Run all of the necessary code to generate results)
********************************************************************************
********************************************************************************

** Define directory for replication 

cd "Insert Directory"


********************************************************************************
** Install packages used in analysis 
********************************************************************************

ssc install unique
ssc install reghdfe
ssc install ftools
ssc install xlincom
ssc install coefplot
ssc install egenmore
ssc install carryforward
net install grc1leg, from( http://www.stata.com/users/vwiggins/) 
ssc install estout
ssc install grc1leg2
ssc install boottest

********************************************************************************
** Run do-files necessary to build key data sets for analysis 
** Follow the order outlined below
********************************************************************************

** Initial Randomization 

do "0.panel_code_Randomization.do"
do "0.Hourly and Daily Template Randomization.do" 
do "0.Randomization.do"

** Construct core panel data set

do "0.panel_code_analysis.do"
do "0.Hourly and Daily Template Analysis.do"

** Run the R-Script "0.Transformer limit Randomization" to generate transformer capacity limits

** Transformer Limits 

do "1.Unenrollment Analysis and Constraint Adjustment.do" 

********************************************************************************
** Do-files used to generate Figures/Tables 
** Follow the order outlined below
********************************************************************************

************
** Figure 1:  
************

do "0. Distribution Transformer Illustrations.do"

************
** Tables 1, C2  
************

do "1.Balance Pre-Treatment - Daily.do"

************
** Figure 2
************

do "1.Descriptive Statistics.do"

************
** Table 2, C3, C4, C5 (column (1) only)
** Figures 3, B1, B2, C2, C3
************

do "2. Regression Analysis - EV and Transformer Level.do"

************
** Table C1
************

do "1.Extensive Margin Analysis.do"

************
** Table B1
************

do "1.Comparing Compliers and Non-Compliers - Daily.do" 

************
** Table B2
************

do "3.Attrition Reg Robustness.do"

************
** Figure C1 - Created in R file "4. Fig C.1 Hourly plot US data.R"
************


************
** Figure C4 and C5 
** Table C5 (Columns (2) and (3))
************

do "3.Cluster-Based Transformers Robustness.do"

************
** Figure C6
** Transformer Upgrades Needs Calculation - cited in Conclusion 
************

do "2.Transformer Upgrade Needs Calculation.do"

********************************************************************************
** Additional Results Cited in text 
********************************************************************************

** Proportion of EV-charge days with opt-outs - Summarized in Section 5.2 

do "2.Opt-Out Analysis.do" 

** Ex-Post Survey - Summarized in Section 5.2 

do "4.Phase3Survey_Analysis.do"



