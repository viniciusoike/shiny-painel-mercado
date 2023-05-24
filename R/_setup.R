library(dygraphs)
library(realestatebr)
library(dplyr)
library(tidyr)

rent_index <- get_rppi(category = "rent", stack = TRUE)
sale_index <- get_rppi(category = "sale", stack = TRUE)

vlvar <- c(
  "Acumulado 12 Meses (%)" = "acum12m",
  "Variação Mensal" = "chg",
  "Índice" = "index"
  )