# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# Packages --------------------------------------------------------------------

library(realestatebr)
library(dplyr)
library(tidyr)
library(lubridate)
library(here)

# Data pipeline ---------------------------------------------------------------

source(here::here("R", "pipeline", "time-series.R"))
source(here::here("R", "pipeline", "inflation.R"))
source(here::here("R", "pipeline", "shared.R"))
source(here::here("R", "pipeline", "rppi.R"))
source(here::here("R", "pipeline", "bcb.R"))
source(here::here("R", "pipeline", "abecip.R"))
source(here::here("R", "pipeline", "abrainc.R"))
source(here::here("R", "pipeline", "secovi.R"))
source(here::here("R", "pipeline", "registries.R"))
source(here::here("R", "pipeline", "loader.R"))

# Dashboard data views --------------------------------------------------------

source(here::here("R", "dashboard", "data-helpers.R"))
