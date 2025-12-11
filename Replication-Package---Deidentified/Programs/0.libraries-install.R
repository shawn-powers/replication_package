####################################
# global libraries used everywhere #
####################################

ppm.date <- "2024-01-01"
options(repos=paste0("https://packagemanager.posit.co/cran/",ppm.date,"/"))

# Note: Using this with a specific version number may fail, since not all dependencies might be met.
# Debug interactively, then identify all installed packages that needed to be pinned.

pkgTest <- function(x,y="")
{
  if (!require(x,character.only = TRUE))
  {
    if ( y == "" ) 
    {
      install.packages(x,dep=TRUE)
    } else {
      remotes::install_version(x, y)
    }
    if(!require(x,character.only = TRUE)) stop("Package not found")
  }
  return("OK")
}

global.libraries <- c("plyr","tidyverse","haven","dplyr", "lubridate", "timeDate", "ggplot2", "ggExtra")

results <- sapply(as.list(global.libraries), pkgTest)



