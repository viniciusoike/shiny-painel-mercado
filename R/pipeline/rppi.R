# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# RPPI preparation ------------------------------------------------------------

RPPI_RAW_COLUMNS <- c(
  "date",
  "name_muni",
  "source",
  "transaction_type",
  "index",
  "chg",
  "acum12m"
)

prep_rppi <- function(dat) {
  dat <- make_prep("rppi", RPPI_RAW_COLUMNS)(dat) |>
    dplyr::rename(category = transaction_type)

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

# Existing caches contain the canonical `category` name rather than the raw
# `transaction_type` name. Convert only that known cache shape before rerunning
# the raw preparation contract.
migrate_rppi_cache <- function(dat) {
  if (
    "category" %in% names(dat) &&
      !"transaction_type" %in% names(dat)
  ) {
    return(dplyr::rename(dat, transaction_type = category))
  }
  dat
}
