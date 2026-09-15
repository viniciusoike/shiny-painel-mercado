# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# STL trend -------------------------------------------------------------------

# STL trend of a monthly vector, aligned to `dates`. trendseries cannot handle
# NAs, so interior gaps are linearly interpolated for the STL input; the
# leading/trailing-NA-trimmed segment is then mapped back. Returns all-NA when
# the series is too short (< 36) or interpolation fails.
stl_trend_vec <- function(v, dates, interpolate = TRUE) {
  if (!interpolate && anyNA(v)) {
    return(rep(NA_real_, length(v)))
  }

  trend_series(v, dates, method = "stl")
}

# STL on the monthly index, then 12-month % change of the trend component.
add_stl_trend <- function(dat) {
  dat <- dplyr::arrange(dat, date)
  dat$trend <- stl_trend_vec(dat$index, dat$date)
  dat$trend_yoy <- (dat$trend / dplyr::lag(dat$trend, 12) - 1) * 100
  dat
}

# Dataset preps ---------------------------------------------------------------

# Generic prep: validate required columns, leave data untouched.
# Dataset-specific transforms replace these as tabs get built.
make_prep <- function(name, required) {
  force(name)
  force(required)
  function(dat) {
    missing <- setdiff(required, names(dat))
    if (length(missing) > 0) {
      cli::cli_abort(c(
        "Dataset {.val {name}} has an unexpected schema.",
        "x" = "Missing: {.field {missing}}.",
        "i" = "Available: {.field {names(dat)}}."
      ))
    }
    tibble::as_tibble(dat)
  }
}
