#install.packages(") if not installed. 

# Load Library
library(tidyverse)
library(haven)
library(dplyr)
library(lubridate)
library(timeDate)
library(ggplot2)
library(ggExtra)

setwd("Insert Directory")
charge <- read_dta("Data/Optiwatt US/charge_sessions_hourly_panel.dta")

# filter data on time period and home sessions

charge.df <- charge %>%
  select(-c(total_est_battery_range_miles,group_name,start_battery_range_miles,
            end_battery_range_miles, date_joined,utility_id,highway08,comb08,
            citye,highwaye, range, rangecity, rangehwy,combe, 
            car_scheduled_departure_time, controlled_by_optiwatt, deleted_vehicle_reason,
            model_year, city08,start_battery_percent, end_battery_percent, is_fast_charge, 
            latitude, longitude, place_id, power_used_by_battery, power_used_by_charger, 
            profile_id, zip_lat,zip_long, start_time_utc, end_time_utc,timezonez)) %>% # remove these columns
  relocate(c(start_time, end_time, from, to, kwh_added, minutes_charged), .after = charge_id) %>%
  filter(start_time>=ymd_hms("2023-04-01 00:00:00") & 
           end_time<ymd_hms("2023-07-05 00:00:00")) %>% # keep only pre-treatment Fortis time period
  filter(charger_type!="supercharger") %>% # remove DC Fast charging
  filter(!is.na(home_id)) # remove sessions that are not charged at home


#------------------------------------------------
#             set up data
#------------------------------------------------

charge.df.temp <- charge.df %>%
  mutate(start.time=floor_date(from,"hour")) %>%
  group_by(vehicle_id,charge_id,start.time) %>%
  summarise(vehicle_id=first(vehicle_id),
            charger=first(charger_type),
            mins=sum(minutes_charged),
            kwh=sum(kwh_added),
            plan_type=first(plan_type),
            primary_city=first(primary_city),
            county=first(county),
            state=first(state)) %>%
  mutate(charge_dummy=1)

vehicle.id <- charge.df %>%
  select(vehicle_id) %>%
  distinct()


# Make vehicle datetime template to include 0's when not charging

start_time=seq(ymd_hms("2023-04-01 00:00:00"),
             ymd_hms("2023-07-04 23:00:00"),by="hour")

df <- data.table::CJ(start_time,unique(charge.df$vehicle_id)) %>%
  rename(vehicle_id = V2) %>%
  left_join(vehicle.id,by="vehicle_id") %>%
  left_join(charge.df.temp,by=c("start_time"="start.time","vehicle_id"))

df[is.na(df)] <- 0

df <- df %>%
  mutate(hour = as.integer(hour(start_time)),
         date = as.Date(format(start_time, format = "%Y-%m-%d")),
         day = weekdays(start_time),
         weekday = isWeekday(start_time),
         weekday = ifelse(weekday == FALSE, "Weekend","Weekday"))

unique <- df %>%
  filter(charge_id!=0) %>%
  select(vehicle_id, plan_type,primary_city,county,state) %>%
  distinct()

df.charge <- left_join(df, unique, by = "vehicle_id") %>%
  select(!c(plan_type.x,primary_city.x,county.x,state.x)) %>%
  rename(plan=plan_type.y,
         primary_city=primary_city.y,
         county=county.y,
         state=state.y)

rm(charge.df.temp, unique)

# define electricity day as 9am to 8:59am and identify charging days

df.charge <- df.charge %>%
  mutate(elec_day = floor_date(start_time-hours(9),unit="days")) %>%
  group_by(elec_day,vehicle_id) %>%
  mutate(charging_day=ifelse(sum(charge_dummy)>0,1,0)) 

df.charge <- df.charge %>% ungroup()

## Mean hourly kwh TOU only

df.hour.tou <- df.charge %>%
  filter(charging_day==1 & 
           plan=="tou") %>%
  group_by(hour) %>%
  summarise(kwh=mean(kwh))

hour.tou <- ggplot(df.hour.tou, aes(hour,kwh))+
  geom_line()+
  scale_x_continuous(limits=c(0,23),expand=c(0,0),labels=c(0,6,12,18,23),breaks=c(0,6,12,18,23))+
  scale_y_continuous(breaks=seq(0,2.75,0.5),limits=c(0,2.75))+
  theme_bw()+
  theme(axis.text.x=element_text(size=14,colour = "black"),
        axis.text.y=element_text(size=14,colour = "black"),
        axis.title=element_text(size=15,colour = "black"),
        aspect.ratio=0.9)+
  labs(x="Hour",
       y="kWhs")+ 
  removeGrid(y=FALSE) 

ggsave("Results/FigureC1.pdf",hour.tou,width = 8,height = 6)

