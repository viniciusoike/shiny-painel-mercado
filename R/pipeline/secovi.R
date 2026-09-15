# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# Secovi preparation ----------------------------------------------------------

prep_secovi <- function(data) {
  prepared <- make_prep(
    "secovi",
    c("date", "category", "variable", "name", "value")
  )(data) |>
    tibble::as_tibble() |>
    dplyr::mutate(date = lubridate::floor_date(.data$date, "month")) |>
    dplyr::left_join(
      SECOVI_SERIES_REGISTRY,
      by = c("variable", "name")
    ) |>
    dplyr::group_by(.data$variable, .data$name) |>
    dplyr::group_modify(
      ~ add_standard_features(
        .x,
        kind = dplyr::coalesce(.x$kind[[1]], "level")
      )
    ) |>
    dplyr::ungroup()

  supply <- prepared |>
    dplyr::filter(
      .data$variable == "supply",
      .data$name == "saldo_unidades"
    ) |>
    dplyr::select("date", supply = "value")
  sales <- prepared |>
    dplyr::filter(
      .data$variable == "sales",
      .data$name == "unidades"
    ) |>
    dplyr::select("date", sales = "roll_mean_12m")
  inventory <- supply |>
    dplyr::inner_join(sales, by = "date") |>
    dplyr::mutate(
      category = "sale",
      variable = "derived",
      name = "months_inventory",
      value = .data$supply / .data$sales,
      kind = "level",
      unit = "months",
      scale = "level",
      seasonal = "none",
      deflator = NA_character_
    ) |>
    dplyr::select(-"supply", -"sales") |>
    add_standard_features(kind = "level")

  dplyr::bind_rows(prepared, inventory) |>
    dplyr::arrange(.data$variable, .data$name, .data$date)
}
