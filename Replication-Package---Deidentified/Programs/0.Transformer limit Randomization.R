#Setting working directory
setwd("Insert Directory") 

##(1) Creates a probability distribution of the constraints we want for our EV + non-EV load, per transformer group

##(2) Computes mean, hourly non-EV load from our file of representative HHs in Fortis territory, July 1 2022 to March 1 2023. 
## It then substracts this non-EV load from the constraints for each hour, so the remaining final constraint 
## is the difference between the two. 

gc()

#Packages
library(plyr)
library(tidyverse)

#*****************************
# (1) Creating constraints and applying to transformer group-day ----
#****************************

#Time series for constraints. 

#Hourly sequence
hour.series = data.frame(hour.series = seq(as.POSIXct("2023-01-01 00:00"), as.POSIXct("2024-07-01 00:00"), by="1 hour"))

#Daily sequence: Extracting from hourly sequence to avoid issues with daylight savings.
day.series = hour.series %>% mutate(date = floor_date(hour.series, unit = "days"))

#Removing duplicate days
day.series = day.series[!duplicated(day.series$date), ]

#Removing hour.series variable
day.series = subset(day.series, select = -hour.series)


#Bringing in vehicle-group assignment to merge with dates----


#Loading data of cars randomized into transformer groups and treatment groups
vehicles = read_csv("Data/treatment group assignment_merged.csv", show_col_types = FALSE)

#List of groups
group.list = data.frame(Group = unique(vehicles$treatment))

#Merging groups to days to create complete day-group df
df.group.time = merge(day.series, group.list)

rm(group.list)
rm(day.series)
rm(vehicles)
gc()


#Probability distribution of constraints----

#Data frame with constraints, probabilities of constraints, and partial sums (based on desired probabilities)
ps.df = data.frame(constraint = c(12:24), prob_constraint = c(0.06, 0.08, 0.2, 0.2, 0.1, 0.08, 0.07, 0.06, 0.05, 0.04, 0.03, 0.02, 0.01)) 

ps.df$partial_sum = ave(ps.df$prob_constraint, FUN=cumsum)


#Simulate draws from the uniform dist. for the number of dates in our time series
set.seed(12345)
n = length(df.group.time$date)
df = data.frame(x = runif(n))

#Assign ultimate constraint based on partial sum
df$constraint = case_when(                                 df$x <= ps.df[1, "partial_sum"] ~ ps.df[1, "constraint"],
                                                           ps.df[1, "partial_sum"] < df$x & df$x <= ps.df[2, "partial_sum"] ~ ps.df[2, "constraint"],
                                                           ps.df[2, "partial_sum"] < df$x & df$x <= ps.df[3, "partial_sum"] ~ ps.df[3, "constraint"],
                                                           ps.df[3, "partial_sum"] < df$x & df$x <= ps.df[4, "partial_sum"] ~ ps.df[4, "constraint"],
                                                           ps.df[4, "partial_sum"] < df$x & df$x <= ps.df[5, "partial_sum"] ~ ps.df[5, "constraint"],
                                                           ps.df[5, "partial_sum"] < df$x & df$x <= ps.df[6, "partial_sum"] ~ ps.df[6, "constraint"],
                                                           ps.df[6, "partial_sum"] < df$x & df$x <= ps.df[7, "partial_sum"] ~ ps.df[7, "constraint"],
                                                           ps.df[7, "partial_sum"] < df$x & df$x <= ps.df[8, "partial_sum"] ~ ps.df[8, "constraint"],
                                                           ps.df[8, "partial_sum"] < df$x & df$x <= ps.df[9, "partial_sum"] ~ ps.df[9, "constraint"],
                                                           ps.df[9, "partial_sum"] < df$x & df$x <= ps.df[10, "partial_sum"] ~ ps.df[10, "constraint"],
                                                           ps.df[10, "partial_sum"] < df$x & df$x <= ps.df[11, "partial_sum"] ~ ps.df[11, "constraint"],
                                                           ps.df[11, "partial_sum"] < df$x & df$x <= ps.df[12, "partial_sum"] ~ ps.df[12, "constraint"],
                                                           ps.df[12, "partial_sum"] < df$x & df$x <= ps.df[13, "partial_sum"] ~ ps.df[13, "constraint"])

#Merging randomized constraints to day-group df----

df.limit = df.group.time

df.limit$constraint = df$constraint


#****************************
#Calculating non-EV mean hourly load and subtracting from assigned constraints
#****************************

#These are 15-min load data from 31 HHs in Fortis territory

load = readr::read_csv("Data/Meter Data/AMI raw data extracts - July 1 2022 to March 1 2023.csv", show_col_types = FALSE)

#Transforms date variable to POSIXct object and creates hour of day indicator. There are four duplicates of each hour value per day b/c these are 15-min data.
df.load = load %>% mutate(date.hour = mdy_hm(`Time tag`),
                          date = floor_date(date.hour, unit="days"),
                          hour = hour(date.hour)) 

#Summing over HH and hour to create HH, hourly data from 15-min data
df.load.hr = ddply(df.load, .(hour, date, No), summarize,
                   HH.load = sum(`intervalValue - kWh`, na.rm= T))

#Making df of mean load by hr over all HHs
df.load.by.hr = ddply(df.load.hr, .(hour), summarize, mean.hr.load = mean(HH.load, na.rm= T))

#Creating "transformer group" non-EV load by taking mean hourly load value and multiplying it by 10
df.load.by.hr$load.trans.grp.10 = df.load.by.hr$mean.hr.load*10

#Creating df for final constraints and a date column that allows us to set a new constraint at 9am every day. 
##Mutate below: Subtracts 9 from each hour in hour series and IDs new day associated with new hour series. Each new day starts at 9am.
df.limit.hourly = hour.series %>% 
  mutate(date = floor_date(hour.series-hours(9), unit="days")) 

#Merging in randomized constraints by date and new date var created above that is 9 hours behind normal calendar
df.limit.hourly = merge(df.limit.hourly, df.limit, by = "date")

#Removing date var to avoid confusion 
df.limit.hourly = subset(df.limit.hourly, select = -date)

#Re-naming accurate date var
colnames(df.limit.hourly) = c("datetime", "Group", "constraint")

#Creating hour variable
df.limit.hourly = df.limit.hourly %>% mutate(hour = hour(datetime)) 

#Merging in non-EV load data for transformer group. Merging hourly transformer group load shape to hour 
df.limit.hourly = merge(df.limit.hourly, df.load.by.hr[,c("hour","load.trans.grp.10")], by = c("hour"), all.x = T) 

#Creating final constraint that is difference between total constraint and non-EV load
df.limit.hourly$ev.load.limit = df.limit.hourly$constraint - df.limit.hourly$load.trans.grp.10

#Saving all data 

df.limit.hourly = df.limit.hourly[,c("datetime", "hour", "Group", "constraint", "load.trans.grp.10", "ev.load.limit")]

colnames(df.limit.hourly) = c("datetime", "hour", "treatment", "constraint", "load.trans.grp.10", "ev.load.limit")

write.csv(df.limit.hourly,"Randomization/group limits all vars_test.csv", row.names=F)

#Keeping only necessary variables
df.limit.hourly = df.limit.hourly[,c("datetime", "hour", "treatment", "ev.load.limit" )]

#Saving output for our internal purposes
write.csv(df.limit.hourly,"Randomization/group limits_test.csv", row.names=F)

























