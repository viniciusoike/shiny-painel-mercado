# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# Inflation adjustment --------------------------------------------------------

build_price_index <- function(inflation, value = "value", base = 100) {
  inflation |>
    dplyr::arrange(.data$date) |>
    dplyr::mutate(
      price_index = base * cumprod(1 + .data[[value]])
    ) |>
    dplyr::select("date", "price_index")
}

deflate_values <- function(
  data,
  inflation,
  value = "value",
  output = "value_real",
  base_date = max(inflation$date, na.rm = TRUE)
) {
  base_month <- lubridate::floor_date(as.Date(base_date), "month")
  inflation_index <- build_price_index(inflation)
  base_index <- inflation_index |>
    dplyr::filter(.data$date == base_month) |>
    dplyr::pull(.data$price_index)

  if (length(base_index) != 1 || is.na(base_index)) {
    cli::cli_abort("No inflation observation exists for {.date {base_month}}.")
  }

  data |>
    dplyr::mutate(date = lubridate::floor_date(.data$date, "month")) |>
    dplyr::left_join(inflation_index, by = "date") |>
    dplyr::mutate(
      "{output}" := .data[[value]] * base_index / .data$price_index
    ) |>
    dplyr::select(-"price_index")
}

deflate_wide_columns <- function(data, inflation, columns) {
  price_index <- build_price_index(inflation)
  base_index <- utils::tail(stats::na.omit(price_index$price_index), 1)
  output <- dplyr::left_join(data, price_index, by = "date")

  for (column in intersect(columns, names(output))) {
    real_column <- paste0(column, "_real")
    output[[real_column]] <- output[[column]] * base_index / output$price_index
  }

  output |>
    dplyr::select(-"price_index") |>
    add_wide_features(paste0(intersect(columns, names(data)), "_real"))
}

deflate_long_values <- function(data, inflation, groups) {
  price_index <- build_price_index(inflation)
  base_index <- utils::tail(stats::na.omit(price_index$price_index), 1)

  data |>
    dplyr::left_join(price_index, by = "date") |>
    dplyr::mutate(
      value_real = dplyr::if_else(
        .data$deflator == "ipca",
        .data$value * base_index / .data$price_index,
        NA_real_
      )
    ) |>
    dplyr::group_by(dplyr::across(dplyr::all_of(groups))) |>
    dplyr::group_modify(
      ~ {
        .x <- dplyr::arrange(.x, .data$date)
        .x$real_trend <- trend_series(.x$value_real, .x$date)
        .x$real_roll_sum_12m <- roll_sum_series(.x$value_real)
        .x$real_roll_mean_12m <- roll_mean_series(.x$value_real)
        .x
      }
    ) |>
    dplyr::ungroup() |>
    dplyr::select(-"price_index")
}

apply_inflation_adjustment <- function(data) {
  inflation <- data$bcb |>
    dplyr::filter(.data$name_simplified == "ipca") |>
    dplyr::select("date", value = "value_std")

  data$sbpe <- deflate_wide_columns(
    data$sbpe,
    inflation,
    c("currency_construction", "currency_acquisition", "currency_total")
  )
  data$abrainc <- deflate_long_values(
    data$abrainc,
    inflation,
    c("category", "variable")
  )
  data$secovi <- deflate_long_values(
    data$secovi,
    inflation,
    c("variable", "name")
  )

  data
}
