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
add_stl_trend <- function(df) {
  df <- dplyr::arrange(df, date)
  df$trend <- stl_trend_vec(df$index, df$date)
  df$trend_yoy <- (df$trend / dplyr::lag(df$trend, 12) - 1) * 100
  df
}

# Dataset preps ---------------------------------------------------------------

# Generic prep: validate required columns, leave data untouched.
# Dataset-specific transforms replace these as tabs get built.
make_prep <- function(name, required) {
  force(name)
  force(required)
  function(df) {
    missing <- setdiff(required, names(df))
    if (length(missing) > 0) {
      cli::cli_abort(c(
        "Dataset {.val {name}} has an unexpected schema.",
        "x" = "Missing: {.field {missing}}.",
        "i" = "Available: {.field {names(df)}}."
      ))
    }
    df
  }
}
