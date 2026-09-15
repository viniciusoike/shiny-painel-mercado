# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# ABECIP preparation ----------------------------------------------------------

prep_abecip_sbpe <- function(data) {
  make_prep(
    "abecip_sbpe",
    c("date", "sbpe_netflow", "sbpe_stock")
  )(data) |>
    tibble::as_tibble() |>
    dplyr::mutate(date = lubridate::floor_date(.data$date, "month")) |>
    add_wide_features(
      c(
        "sbpe_inflow",
        "sbpe_outflow",
        "sbpe_netflow",
        "sbpe_stock",
        "total_stock",
        "total_netflow"
      )
    )
}

prep_abecip_units <- function(data) {
  make_prep(
    "abecip_units",
    c(
      "date",
      "units_construction",
      "units_acquisition",
      "units_total",
      "currency_construction",
      "currency_acquisition",
      "currency_total"
    )
  )(data) |>
    tibble::as_tibble() |>
    dplyr::mutate(date = lubridate::floor_date(.data$date, "month")) |>
    add_wide_features(
      c(
        "units_construction",
        "units_acquisition",
        "units_total",
        "currency_construction",
        "currency_acquisition",
        "currency_total"
      )
    )
}
