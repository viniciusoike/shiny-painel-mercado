# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# Labels ----------------------------------------------------------------------

vlvar <- c(
  "Acumulado 12 Meses (%)" = "acum12m",
  "Variação Mensal (%)" = "chg",
  "Índice" = "index",
  "YoY do Trend (STL, %)" = "trend_yoy"
)

# Activity helpers ------------------------------------------------------------

# One activity series as date + value, with `metric` picking the column:
# "sa" (seasonally adjusted level), "raw" (as published), "trend" (STL trend of
# the adjusted series) or "yoy".
activity_pick <- function(act, series, metric = "sa") {
  col <- switch(
    metric,
    sa = "sa",
    raw = "value",
    trend = "trend",
    yoy = "yoy",
    "sa"
  )
  d <- dplyr::filter(act, series == !!series)
  if (nrow(d) == 0) {
    return(tibble::tibble(date = as.Date(character()), value = numeric()))
  }
  d |>
    dplyr::arrange(date) |>
    dplyr::mutate(
      value = .data[[col]],
      trend = if (identical(metric, "yoy")) .data$yoy_trend else .data$trend
    ) |>
    dplyr::select("date", "value", "trend")
}

# Metadata row for one activity series (label, unit, kind).
activity_meta <- function(series) {
  as.list(SGS_ATIVIDADE[match(series, SGS_ATIVIDADE$series), ])
}

# Y-axis label for a series under the selected metric. The 12-month view is a %
# change for levels and a pp difference for rates.
activity_unit <- function(series, metric = "sa") {
  m <- activity_meta(series)
  if (identical(metric, "yoy")) {
    if (identical(m$kind, "rate")) "p.p. (12m)" else "% (12m)"
  } else {
    m$unit
  }
}

# Wide date x series frame of one metric, for the multi-series comparisons.
activity_wide <- function(act, series, labels = series, metric = "sa") {
  cols <- lapply(seq_along(series), function(i) {
    dplyr::rename(activity_pick(act, series[i], metric), !!labels[i] := value)
  })
  Reduce(function(a, b) dplyr::full_join(a, b, by = "date"), cols) |>
    dplyr::arrange(date)
}

# Rebase a wide frame to 100 at the first date where every column is observed.
rebase_100 <- function(df, cols) {
  present <- intersect(cols, names(df))
  d <- dplyr::arrange(df, date)
  complete <- which(stats::complete.cases(d[present]))
  if (length(complete) == 0) {
    return(d)
  }
  base <- complete[1]
  for (cl in present) {
    d[[cl]] <- d[[cl]] / d[[cl]][base] * 100
  }
  d
}

# RPPI helpers ----------------------------------------------------------------

split_rppi <- function(df) {
  list(
    rent = dplyr::filter(df, category == "rent"),
    sale = dplyr::filter(df, category == "sale")
  )
}

# IVG-R (BCB) is a national index — sale-only, available solely for "Brazil".
# To show it alongside the per-city sources on the Venda variation chart, relabel
# its Brazil rows to the selected city (a no-op when the city already is Brazil).
sale_with_ivgr <- function(sale, city) {
  base <- dplyr::filter(sale, name_muni == city)
  if (identical(city, "Brazil")) {
    return(base)
  }
  ivgr <- dplyr::filter(sale, source == "IVG-R", name_muni == "Brazil")
  if (nrow(ivgr) == 0) {
    return(base)
  }
  ivgr$name_muni <- city
  dplyr::bind_rows(base, ivgr)
}

# IVAR (FGV) national rent index is stored with name_muni = NA. To show it
# alongside the per-city rent sources, relabel it to the requested city (a no-op
# unless that city is "Brazil", since IVAR has no per-city series here).
rent_with_ivar <- function(rent, city) {
  base <- dplyr::filter(rent, name_muni == city)
  if (!identical(city, "Brazil")) {
    return(base)
  }
  ivar <- dplyr::filter(rent, source == "IVAR", is.na(name_muni))
  if (nrow(ivar) == 0) {
    return(base)
  }
  ivar$name_muni <- city
  dplyr::bind_rows(base, ivar)
}

# Calendar-year accumulated variation (%) per index, one row per year. Inflation
# series (INCC, IPCA — stored as monthly %) compound within the year; price
# indices (IGMI-R, IVAR — levels) use Dec/Dec-1 (last available month for the
# current, partial year). Years run 2010..latest; cells before a series starts
# are NA.
yearly_accum_data <- function(bcb, sp) {
  infl_year <- function(name) {
    bcb |>
      dplyr::filter(name_simplified == !!name, !is.na(value)) |>
      dplyr::arrange(date) |>
      dplyr::mutate(year = lubridate::year(date)) |>
      dplyr::group_by(year) |>
      dplyr::summarise(v = (prod(1 + value / 100) - 1) * 100, .groups = "drop")
  }
  idx_year <- function(df) {
    df |>
      dplyr::filter(!is.na(index)) |>
      dplyr::arrange(date) |>
      dplyr::mutate(year = lubridate::year(date)) |>
      dplyr::group_by(year) |>
      dplyr::slice_max(date, n = 1, with_ties = FALSE) |>
      dplyr::ungroup() |>
      dplyr::arrange(year) |>
      dplyr::mutate(v = (index / dplyr::lag(index) - 1) * 100) |>
      dplyr::select("year", "v")
  }

  incc <- infl_year("incc")
  ipca <- infl_year("ipca")
  igmi <- idx_year(dplyr::filter(
    sp$sale,
    source == "IGMI-R",
    name_muni == "Brazil"
  ))
  ivar <- idx_year(dplyr::filter(sp$rent, source == "IVAR", is.na(name_muni)))

  max_year <- suppressWarnings(max(c(
    incc$year,
    ipca$year,
    igmi$year,
    ivar$year
  )))
  if (!is.finite(max_year)) {
    return(tibble::tibble())
  }
  years <- 2010:max_year
  pick <- function(t) t$v[match(years, t$year)]
  tibble::tibble(
    year = years,
    incc = pick(incc),
    ipca = pick(ipca),
    igmi = pick(igmi),
    ivar = pick(ivar)
  )
}

city_choices <- function(df) {
  cities <- sort(unique(df$name_muni))
  # data uses "Brazil" and title-case "Rio De Janeiro"
  preferred <- c(
    "Brazil",
    "Brasil",
    "São Paulo",
    "Rio De Janeiro",
    "Rio de Janeiro"
  )
  c(intersect(preferred, cities), setdiff(cities, preferred))
}

# Main capitals for the comparison chart and summary table, in display order.
MAIN_CITIES <- c(
  "São Paulo",
  "Rio De Janeiro",
  "Belo Horizonte",
  "Curitiba",
  "Porto Alegre",
  "Brasília",
  "Salvador",
  "Fortaleza",
  "Recife",
  "Goiânia"
)

# Secovi helpers --------------------------------------------------------------

# Pull one Secovi series as date + value, sorted. `name` is optional.
secovi_pick <- function(
  sec,
  variable,
  name = NULL,
  value_col = "value",
  include_trend = identical(value_col, "value")
) {
  d <- dplyr::filter(sec, variable == !!variable)
  if (!is.null(name)) {
    d <- dplyr::filter(d, name == !!name)
  }
  output <- d |>
    dplyr::arrange(date) |>
    dplyr::mutate(value = .data[[value_col]]) |>
    dplyr::select("date", "value")

  if (include_trend && "trend" %in% names(d)) {
    output$trend <- d$trend
  }

  output
}


# Dormitório label -> Secovi sales variable (the 1/2/3/4-room sales split).
# Ordered small-to-large so stacked bands and table columns read consistently.
SECOVI_ROOMS <- c(
  "1 dorm" = "sales_1rooms",
  "2 dorm" = "sales_2rooms",
  "3 dorm" = "sales_3rooms",
  "4 dorm" = "sales_4rooms"
)

# Wide date x dormitório frame for one Secovi metric `name` (default the
# monthly unit count). One column per SECOVI_ROOMS label.
secovi_rooms_wide <- function(sec, name = "unidades", value_col = "value") {
  cols <- lapply(names(SECOVI_ROOMS), function(lab) {
    series <- secovi_pick(
      sec,
      SECOVI_ROOMS[[lab]],
      name,
      value_col = value_col,
      include_trend = FALSE
    )
    dplyr::rename(series, !!lab := value)
  })
  Reduce(function(a, b) dplyr::full_join(a, b, by = "date"), cols) |>
    dplyr::arrange(date)
}

# 12-month rolling sum of sales units per dormitório, wide (for the stacked
# area). Rolls each band on its own so partial leading windows stay NA.
secovi_rooms_units_12m <- function(sec) {
  cols <- lapply(names(SECOVI_ROOMS), function(lab) {
    rolled <- secovi_pick(
      sec,
      SECOVI_ROOMS[[lab]],
      "unidades",
      value_col = "roll_sum_12m",
      include_trend = FALSE
    )
    dplyr::rename(rolled, !!lab := value)
  })
  Reduce(function(a, b) dplyr::full_join(a, b, by = "date"), cols) |>
    dplyr::arrange(date)
}

# Annual sales units per dormitório (year x band, wide). Only complete years
# (12 monthly observations) are kept so partial years never skew comparisons.
secovi_rooms_yearly <- function(sec) {
  parts <- lapply(names(SECOVI_ROOMS), function(lab) {
    secovi_pick(sec, SECOVI_ROOMS[[lab]], "unidades") |>
      dplyr::mutate(year = lubridate::year(date)) |>
      dplyr::group_by(year) |>
      dplyr::summarise(
        n = sum(!is.na(value)),
        value = sum(value, na.rm = TRUE),
        .groups = "drop"
      ) |>
      dplyr::mutate(
        "{lab}" := dplyr::if_else(n == 12, value, NA_real_)
      ) |>
      dplyr::select("year", dplyr::all_of(lab))
  })
  Reduce(function(a, b) dplyr::full_join(a, b, by = "year"), parts) |>
    dplyr::arrange(year)
}

# Convert an annual wide frame (year + band cols) to within-year percentage
# shares (each year's bands sum to 100; all-NA years stay NA).
rooms_to_shares <- function(df, cols = names(SECOVI_ROOMS)) {
  present <- intersect(cols, names(df))
  m <- as.matrix(df[present])
  tot <- rowSums(m, na.rm = TRUE)
  tot[tot == 0] <- NA_real_
  out <- tibble::tibble(year = df$year)
  out[present] <- round(sweep(m, 1, tot, "/") * 100, 1)
  out
}

# BCB / ABRAINC helpers -------------------------------------------------------

# One bcb_series series as date + value, sorted.
bcb_pick <- function(bcb, name, value_col = "value", scale = 1) {
  output <- bcb |>
    dplyr::filter(name_simplified == !!name) |>
    dplyr::arrange(date) |>
    dplyr::mutate(value = .data[[value_col]] * .env$scale) |>
    dplyr::select("date", "value")

  if (identical(value_col, "value") && "trend" %in% names(bcb)) {
    trend <- bcb |>
      dplyr::filter(name_simplified == !!name) |>
      dplyr::arrange(date) |>
      dplyr::pull("trend")
    output$trend <- trend
  }

  output
}

inflation_wide <- function(bcb) {
  ipca <- bcb_pick(bcb, "ipca", "change_12m", scale = 100) |>
    dplyr::rename(IPCA = "value")
  igpm <- bcb_pick(bcb, "igpm", "change_12m", scale = 100) |>
    dplyr::rename(`IGP-M` = "value")
  incc <- bcb_pick(bcb, "incc", "change_12m", scale = 100) |>
    dplyr::rename(INCC = "value")

  ipca |>
    dplyr::full_join(igpm, by = "date") |>
    dplyr::full_join(incc, by = "date")
}

real_rate_wide <- function(selic, bcb) {
  inflation <- bcb_pick(bcb, "ipca", "change_12m") |>
    dplyr::rename(ipca_12m = "value")

  selic |>
    dplyr::select("date", selic = "value") |>
    dplyr::inner_join(inflation, by = "date") |>
    dplyr::mutate(
      `Selic Meta` = .data$selic,
      `IPCA 12m` = .data$ipca_12m * 100,
      `Juro Real` = ((1 + .data$selic / 100) / (1 + .data$ipca_12m) - 1) * 100
    ) |>
    dplyr::select("date", "Selic Meta", "IPCA 12m", "Juro Real")
}

credit_conditions_wide <- function(bcb) {
  commitment <- bcb_pick(bcb, "comprometimento_renda_servico_total") |>
    dplyr::rename(Comprometimento = "value")
  debt <- bcb_pick(bcb, "endividamento_total") |>
    dplyr::rename(Endividamento = "value")

  dplyr::full_join(commitment, debt, by = "date")
}

# One ABRAINC series (category + segment variable) as date + value, sorted.
abrainc_pick <- function(
  ab,
  category,
  variable = "total",
  value_col = "value"
) {
  output <- ab |>
    dplyr::filter(category == !!category, variable == !!variable) |>
    dplyr::arrange(date) |>
    dplyr::mutate(value = .data[[value_col]]) |>
    dplyr::select("date", "value")

  if (identical(value_col, "value") && "trend" %in% names(ab)) {
    trend <- ab |>
      dplyr::filter(category == !!category, variable == !!variable) |>
      dplyr::arrange(date) |>
      dplyr::pull("trend")
    output$trend <- trend
  }

  output
}

abecip_pick <- function(data, series, real = FALSE) {
  value_column <- paste0(series, if (real) "_real" else "")
  trend_column <- paste0(value_column, "_trend")

  tibble::tibble(
    date = data$date,
    value = data[[value_column]],
    trend = data[[trend_column]]
  )
}

# Segmento chip -> ABRAINC segment variable.
ABRAINC_SEGMENTO <- c(
  "Total" = "total",
  "Econômico" = "social_housing",
  "Alto Padrão" = "market_rate"
)
