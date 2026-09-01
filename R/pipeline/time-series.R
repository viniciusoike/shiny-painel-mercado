# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# Time-series preparation -----------------------------------------------------

interpolate_series <- function(value, date) {
  order_id <- order(date)
  value_ordered <- value[order_id]
  date_ordered <- date[order_id]

  observed <- which(!is.na(value_ordered))
  if (length(observed) < 2) {
    return(value)
  }

  first <- observed[[1]]
  last <- observed[[length(observed)]]
  value_ordered[first:last] <- zoo::na.approx(
    value_ordered[first:last],
    x = date_ordered[first:last],
    na.rm = FALSE
  )

  value_ordered[order(order_id)]
}

trend_series <- function(value, date, method = "stl") {
  order_id <- order(date)
  value_ordered <- value[order_id]
  date_ordered <- date[order_id]
  output <- rep(NA_real_, length(value_ordered))

  observed <- which(!is.na(value_ordered))
  if (length(observed) < 36) {
    return(output[order(order_id)])
  }

  first <- observed[[1]]
  last <- observed[[length(observed)]]
  value_complete <- interpolate_series(
    value_ordered[first:last],
    date_ordered[first:last]
  )

  trend <- tryCatch(
    trendseries::augment_trends(
      tibble::tibble(
        date = date_ordered[first:last],
        value = value_complete
      ),
      methods = method,
      params = if (method == "stl") list(robust = TRUE) else list(),
      .quiet = TRUE
    )[[paste0("trend_", method)]],
    error = function(error) {
      cli::cli_warn(c(
        "Trend extraction failed.",
        "i" = "Method: {.val {method}}.",
        "i" = "Reason: {conditionMessage(error)}"
      ))
      rep(NA_real_, length(value_complete))
    }
  )

  output[first:last] <- trend
  output[order(order_id)]
}

deseason_series <- function(value, date, source_adjusted = FALSE) {
  if (source_adjusted) {
    return(value)
  }

  if (!requireNamespace("seasonal", quietly = TRUE)) {
    cli::cli_abort(
      "Package {.pkg seasonal} is required for SEATS seasonal adjustment."
    )
  }

  order_id <- order(date)
  value_ordered <- value[order_id]
  date_ordered <- date[order_id]
  output <- rep(NA_real_, length(value_ordered))
  observed <- which(!is.na(value_ordered))

  if (length(observed) < 36) {
    return(value)
  }

  first <- observed[[1]]
  last <- observed[[length(observed)]]
  value_complete <- interpolate_series(
    value_ordered[first:last],
    date_ordered[first:last]
  )

  adjusted <- tryCatch(
    trendseries::deseason_series(
      tibble::tibble(
        date = date_ordered[first:last],
        value = value_complete
      ),
      methods = "seats",
      .quiet = TRUE
    )$seasadj_seats,
    error = function(error) {
      cli::cli_warn(c(
        "Seasonal adjustment failed; using the interpolated series.",
        "i" = "Method: {.val seats}.",
        "i" = "Reason: {conditionMessage(error)}"
      ))
      value_complete
    }
  )

  output[first:last] <- adjusted
  output[order(order_id)]
}

# Rate transformations --------------------------------------------------------

standardize_rate <- function(value, unit = c("fraction", "percent", "bps")) {
  unit <- match.arg(unit)

  switch(
    unit,
    fraction = value,
    percent = value / 100,
    bps = value / 10000
  )
}

add_rate_features <- function(data, value = "value") {
  value_vector <- data[[value]]
  rates <- data |>
    dplyr::mutate("{value}" := value_vector) |>
    trendseries::augment_rolling(
      value_col = value,
      stats = "chain",
      window = 12,
      .quiet = TRUE
    ) |>
    trendseries::augment_rolling(
      value_col = value,
      stats = "chain",
      window = "ytd",
      .quiet = TRUE
    )

  rates |>
    dplyr::mutate(
      change_yoy = value_vector / dplyr::lag(value_vector, 12) - 1,
      change_12m = .data$roll_chain_12,
      change_ytd = .data$roll_chain_ytd
    ) |>
    dplyr::select(-"roll_chain_12", -"roll_chain_ytd")
}

add_level_features <- function(data, value = "value") {
  value_vector <- data[[value]]

  data |>
    dplyr::mutate(
      change_mom = value_vector / dplyr::lag(value_vector) - 1,
      change_yoy = value_vector / dplyr::lag(value_vector, 12) - 1,
      trend_stl = trend_series(value_vector, .data$date, method = "stl"),
      trend_hp = trend_series(value_vector, .data$date, method = "hp"),
      cycle_hp = value_vector - .data$trend_hp
    )
}

# Standard features -----------------------------------------------------------

regularize_monthly <- function(data) {
  data <- data |>
    dplyr::mutate(date = lubridate::floor_date(.data$date, "month")) |>
    dplyr::arrange(.data$date) |>
    tidyr::complete(
      date = seq(min(.data$date), max(.data$date), by = "month")
    )

  metadata <- setdiff(names(data), c("date", "value", "year"))
  for (column in metadata) {
    observed <- unique(stats::na.omit(data[[column]]))
    if (length(observed) == 1) {
      data[[column]] <- observed[[1]]
    }
  }

  if ("year" %in% names(data)) {
    data$year <- lubridate::year(data$date)
  }

  data
}

roll_sum_series <- function(value, n = 12) {
  RcppRoll::roll_sumr(value, n = n, fill = NA_real_)
}

roll_mean_series <- function(value, n = 12) {
  RcppRoll::roll_meanr(value, n = n, fill = NA_real_)
}

add_standard_features <- function(data, kind = "level") {
  data <- regularize_monthly(data)
  value <- data$value

  data |>
    dplyr::mutate(
      value_interp = interpolate_series(value, .data$date),
      trend = trend_series(.data$value_interp, .data$date),
      roll_sum_12m = roll_sum_series(value),
      roll_mean_12m = roll_mean_series(value),
      change_yoy = if (identical(kind, "rate")) {
        value - dplyr::lag(value, 12)
      } else {
        value / dplyr::lag(value, 12) - 1
      }
    )
}

add_wide_features <- function(data, columns) {
  output <- dplyr::arrange(data, .data$date)

  for (column in intersect(columns, names(output))) {
    value <- output[[column]]
    output[[paste0(column, "_trend")]] <- trend_series(value, output$date)
    output[[paste0(column, "_roll_sum_12m")]] <- roll_sum_series(value)
    output[[paste0(column, "_roll_mean_12m")]] <- roll_mean_series(value)
    output[[paste0(column, "_change_yoy")]] <-
      value / dplyr::lag(value, 12) - 1
  }

  output
}
