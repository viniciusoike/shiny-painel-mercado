# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# RPPI preparation ------------------------------------------------------------

prep_rppi <- function(dat) {
  dat <- make_prep(
    "rppi",
    c("date", "name_muni", "source", "category", "index")
  )(dat)

  dat |>
    dplyr::group_by(source, name_muni, category) |>
    dplyr::group_modify(~ add_stl_trend(.x)) |>
    dplyr::ungroup() |>
    dplyr::left_join(RPPI_SERIES_REGISTRY, by = "source") |>
    dplyr::mutate(
      chg_pct = .data$chg * 100,
      acum12m_pct = .data$acum12m * 100
    ) |>
    dplyr::arrange(.data$source, .data$name_muni, .data$category, .data$date)
}
