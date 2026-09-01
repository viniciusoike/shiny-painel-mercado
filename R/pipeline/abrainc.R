# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# ABRAINC preparation ---------------------------------------------------------

prep_abrainc <- function(data) {
  make_prep(
    "abrainc",
    c("date", "category", "variable", "value")
  )(data) |>
    tibble::as_tibble() |>
    dplyr::mutate(date = lubridate::floor_date(.data$date, "month")) |>
    dplyr::left_join(ABRAINC_SERIES_REGISTRY, by = "category") |>
    dplyr::group_by(.data$category, .data$variable) |>
    dplyr::group_modify(
      ~ add_standard_features(.x, kind = .x$kind[[1]])
    ) |>
    dplyr::ungroup() |>
    dplyr::arrange(.data$category, .data$variable, .data$date)
}
