library(realestatebr)
library(dplyr)
library(tidyr)
library(lubridate)
library(here)

RPPI_CACHE <- here::here(".cache", "rppi.rds")

vlvar <- c(
  "Acumulado 12 Meses (%)" = "acum12m",
  "Variação Mensal (%)"    = "chg",
  "Índice"                 = "index",
  "YoY do Trend (STL, %)"  = "trend_yoy"
)

# STL on monthly index, then 12-month % change of the trend component.
# Skips panels too short or too sparse for stl() to handle.
add_stl_trend <- function(df) {

  df <- dplyr::arrange(df, date)
  v  <- df$index

  if (length(v) < 36 || sum(!is.na(v)) < 36) {
    df$trend     <- NA_real_
    df$trend_yoy <- NA_real_
    return(df)
  }

  trend <- tryCatch({
    s  <- min(df$date, na.rm = TRUE)
    ts_obj <- stats::ts(
      v,
      start     = c(lubridate::year(s), lubridate::month(s)),
      frequency = 12
    )
    fit <- stats::stl(
      ts_obj,
      s.window  = "periodic",
      robust    = TRUE,
      na.action = stats::na.exclude
    )
    as.numeric(fit$time.series[, "trend"])
  }, error = function(e) rep(NA_real_, length(v)))

  df$trend     <- trend
  df$trend_yoy <- (df$trend / dplyr::lag(df$trend, 12) - 1) * 100
  df
}

prep_rppi <- function(df) {
  required <- c("date", "name_muni", "source", "category", "index")
  missing  <- setdiff(required, names(df))
  if (length(missing) > 0) {
    stop(
      "get_dataset('rppi') returned unexpected columns. Missing: ",
      paste(missing, collapse = ", "),
      ". Got: ", paste(names(df), collapse = ", ")
    )
  }

  df |>
    dplyr::group_by(source, name_muni, category) |>
    dplyr::group_modify(~ add_stl_trend(.x)) |>
    dplyr::ungroup()
}

load_rppi <- function(force = FALSE) {
  if (!force && file.exists(RPPI_CACHE)) {
    return(readRDS(RPPI_CACHE))
  }

  raw <- realestatebr::get_dataset("rppi", source = "github")
  out <- prep_rppi(raw)
  attr(out, "fetched_at") <- Sys.time()

  dir.create(dirname(RPPI_CACHE), showWarnings = FALSE, recursive = TRUE)
  saveRDS(out, RPPI_CACHE)
  out
}

split_rppi <- function(df) {
  list(
    rent = dplyr::filter(df, category == "rent"),
    sale = dplyr::filter(df, category == "sale")
  )
}

city_choices <- function(df) {
  cities <- sort(unique(df$name_muni))
  preferred <- c("Brasil", "Brazil", "São Paulo", "Rio de Janeiro")
  c(intersect(preferred, cities), setdiff(cities, preferred))
}
