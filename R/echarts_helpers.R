library(echarts4r)

source(here::here("R", "utils.R"))

# Variables stored as fractions that should display as percentages.
PCT_VARS <- c("chg", "acum12m")

# Shared options ---------------------------------------------------------------

# Tooltip, legend, grid, time axis, zero markline, datazoom and toolbox.
# window_start (Date or NULL) sets the initial zoom; NULL shows everything.
# zero_line is for variables centered on zero (% changes); index levels skip it.
echart_finish <- function(e, y_name, window_start = NULL, zero_line = TRUE) {

  e <- e |>
    echarts4r::e_tooltip(trigger = "axis") |>
    echarts4r::e_legend(top = 0, type = "scroll") |>
    echarts4r::e_grid(top = 50, bottom = 60) |>
    echarts4r::e_x_axis(type = "time") |>
    echarts4r::e_y_axis(
      name         = y_name,
      nameLocation = "middle",
      nameGap      = 45,
      scale        = TRUE
    ) |>
    echarts4r::e_toolbox_feature(feature = "saveAsImage")

  if (zero_line) {
    e <- echarts4r::e_mark_line(
      e,
      data      = list(yAxis = 0),
      lineStyle = list(color = "#333", type = "solid", width = 1),
      symbol    = "none",
      silent    = TRUE
    )
  }

  if (is.null(window_start)) {
    echarts4r::e_datazoom(e, type = "slider", start = 0)
  } else {
    echarts4r::e_datazoom(
      e,
      type       = "slider",
      startValue = format(window_start, "%Y-%m-%d")
    )
  }
}

echart_empty <- function() {
  echarts4r::e_charts() |>
    echarts4r::e_title("Sem dados para a seleção")
}

add_lines <- function(e, series, colors, dashed = FALSE, width = 2) {
  for (i in seq_along(series)) {
    e <- echarts4r::e_line_(
      e,
      serie        = series[i],
      name         = series[i],
      lineStyle    = list(
        width = width,
        color = colors[i],
        type  = if (dashed) "dashed" else "solid"
      ),
      itemStyle    = list(color = colors[i]),
      symbol       = "none",
      connectNulls = TRUE
    )
  }
  e
}

# Multi-source series ----------------------------------------------------------

# Long tibble -> line chart, one series per index source for one city.
# When variable == "index", overlays the STL trend per source (dashed).
echart_series <- function(df, city, variable_label, window_start = NULL) {

  stopifnot(variable_label %in% names(vlvar))
  sel_var <- unname(vlvar[variable_label])

  d <- df |>
    dplyr::filter(name_muni == city, !is.na(.data[[sel_var]])) |>
    dplyr::arrange(date)

  if (nrow(d) == 0) return(echart_empty())

  if (sel_var %in% PCT_VARS) {
    d[[sel_var]] <- round(d[[sel_var]] * 100, 2)
  } else {
    d[[sel_var]] <- round(d[[sel_var]], 2)
  }

  sources <- sort(unique(d$source))
  colors  <- echart_palette(length(sources))
  show_trend_overlay <- identical(sel_var, "index")

  wide <- d |>
    tidyr::pivot_wider(
      id_cols     = "date",
      names_from  = "source",
      values_from = dplyr::all_of(sel_var)
    )

  if (show_trend_overlay) {
    trend_wide <- d |>
      tidyr::pivot_wider(
        id_cols     = "date",
        names_from  = "source",
        values_from = "trend"
      )
    trend_present <- intersect(sources, names(trend_wide))
    trend_wide <- trend_wide[, c("date", trend_present), drop = FALSE]
    names(trend_wide) <- c("date", paste0(trend_present, " (tendência)"))
    wide <- dplyr::full_join(wide, trend_wide, by = "date") |>
      dplyr::arrange(date)
  }

  e <- echarts4r::e_charts(wide, date) |>
    add_lines(sources, colors)

  if (show_trend_overlay) {
    trend_names <- intersect(paste0(sources, " (tendência)"), names(wide))
    trend_cols  <- colors[match(sub(" \\(tendência\\)$", "", trend_names), sources)]
    e <- add_lines(e, trend_names, trend_cols, dashed = TRUE, width = 1.5)
  }

  echart_finish(e, variable_label, window_start,
                zero_line = !show_trend_overlay)
}

# City comparison --------------------------------------------------------------

# One line per city for a single source/variable (defaults: FipeZap, acum12m).
echart_compare <- function(df, cities, sel_var = "acum12m",
                           y_name = "Acumulado 12 Meses (%)",
                           window_start = NULL) {

  d <- df |>
    dplyr::filter(name_muni %in% cities, !is.na(.data[[sel_var]])) |>
    dplyr::arrange(date)

  if (nrow(d) == 0 || length(cities) == 0) return(echart_empty())

  if (sel_var %in% PCT_VARS) {
    d[[sel_var]] <- round(d[[sel_var]] * 100, 2)
  }

  present <- intersect(cities, unique(d$name_muni))
  colors  <- echart_palette(length(present))

  wide <- d |>
    tidyr::pivot_wider(
      id_cols     = "date",
      names_from  = "name_muni",
      values_from = dplyr::all_of(sel_var)
    )

  echarts4r::e_charts(wide, date) |>
    add_lines(present, colors) |>
    echart_finish(y_name, window_start)
}

# Real vs. nominal --------------------------------------------------------------

# Nominal index vs. IPCA-deflated real index, both rebased to 100 at the
# first month where the price index and IPCA overlap.
echart_real_nominal <- function(df, ipca, window_start = NULL) {

  if (nrow(df) == 0 || nrow(ipca) == 0) return(echart_empty())

  ipca_index <- ipca |>
    dplyr::arrange(date) |>
    dplyr::mutate(ipca_index = cumprod(1 + value / 100)) |>
    dplyr::select(date, ipca_index)

  d <- df |>
    dplyr::filter(!is.na(index)) |>
    dplyr::select(date, index) |>
    dplyr::inner_join(ipca_index, by = "date") |>
    dplyr::arrange(date)

  if (nrow(d) < 2) return(echart_empty())

  d <- d |>
    dplyr::mutate(
      Nominal       = round(index / index[1] * 100, 1),
      `Real (IPCA)` = round(index / index[1] / (ipca_index / ipca_index[1]) * 100, 1)
    )

  colors <- get_color_palette(2)

  echarts4r::e_charts(d, date) |>
    add_lines(c("Nominal", "Real (IPCA)"), colors) |>
    echart_finish("Índice (base 100)", window_start, zero_line = FALSE)
}

echart_palette <- function(n) {
  if (n <= 5) return(get_color_palette(n))
  rep_len(pal, n)
}

# Panorama charts --------------------------------------------------------------

# STL trend (12m %) of the sale index for several cities, single source.
echart_trend_cities <- function(df, cities, source = "FipeZap",
                                window_start = NULL) {

  d <- df |>
    dplyr::filter(name_muni %in% cities, source == !!source,
                  !is.na(trend_yoy)) |>
    dplyr::arrange(date)

  if (nrow(d) == 0) return(echart_empty())

  present <- intersect(cities, unique(d$name_muni))
  colors  <- echart_palette(length(present))

  wide <- d |>
    dplyr::mutate(trend_yoy = round(trend_yoy, 2)) |>
    tidyr::pivot_wider(
      id_cols     = "date",
      names_from  = "name_muni",
      values_from = "trend_yoy"
    )

  echarts4r::e_charts(wide, date) |>
    add_lines(present, colors) |>
    echart_finish("Tendência 12m (%)", window_start)
}

# Selic meta, IPCA 12m, and the real interest rate (Fisher) on one axis.
echart_real_rate <- function(selic, ipca, window_start = NULL) {

  if (nrow(selic) == 0 || nrow(ipca) == 0) return(echart_empty())

  ipca12 <- ipca |>
    dplyr::arrange(date) |>
    dplyr::mutate(`IPCA 12m` = acum12m_pct(value)) |>
    dplyr::select(date, `IPCA 12m`)

  d <- selic |>
    dplyr::transmute(date, `Selic Meta` = value) |>
    dplyr::inner_join(ipca12, by = "date") |>
    dplyr::filter(!is.na(`IPCA 12m`)) |>
    dplyr::mutate(
      `Juro Real` = round(((1 + `Selic Meta` / 100) /
                             (1 + `IPCA 12m` / 100) - 1) * 100, 2),
      `Selic Meta` = round(`Selic Meta`, 2),
      `IPCA 12m`   = round(`IPCA 12m`, 2)
    )

  if (nrow(d) < 2) return(echart_empty())

  colors <- get_color_palette(3)

  echarts4r::e_charts(d, date) |>
    add_lines(c("Selic Meta", "IPCA 12m", "Juro Real"), colors) |>
    echart_finish("% a.a.", window_start)
}

# Monthly series (bar) with its STL trend overlaid (line).
echart_volume_trend <- function(df, value_col, y_name = "R$ bilhões",
                                window_start = NULL) {

  d <- df |>
    dplyr::filter(!is.na(.data[[value_col]])) |>
    dplyr::arrange(date) |>
    dplyr::transmute(date, Volume = .data[[value_col]])

  if (nrow(d) < 12) return(echart_empty())

  d$Tendência <- stl_trend_vec(d$Volume, d$date)
  colors <- get_color_palette(2)

  echarts4r::e_charts(d, date) |>
    echarts4r::e_bar(
      Volume, name = "Volume mensal",
      itemStyle = list(color = colors[1], opacity = 0.5)
    ) |>
    echarts4r::e_line(
      Tendência, name = "Tendência",
      lineStyle = list(width = 2, color = colors[2]),
      itemStyle = list(color = colors[2]), symbol = "none"
    ) |>
    echart_finish(y_name, window_start, zero_line = FALSE)
}

# Single monthly series: faint raw line + bold STL trend (the Secovi pattern).
# `df` has columns date + value.
echart_trend_single <- function(df, y_name, raw_name = "Mensal",
                                window_start = NULL, zero_line = FALSE) {

  d <- df |>
    dplyr::filter(!is.na(value)) |>
    dplyr::arrange(date) |>
    dplyr::rename(!!raw_name := value)

  if (nrow(d) < 2) return(echart_empty())

  color  <- get_color_palette(1)
  d$Tendência <- if (nrow(d) >= 36) stl_trend_vec(d[[raw_name]], d$date) else NA_real_

  out <- echarts4r::e_charts(d, date) |>
    echarts4r::e_line_(
      serie = raw_name, name = raw_name, symbol = "none",
      lineStyle = list(width = 1, color = color, opacity = 0.35),
      itemStyle = list(color = color)
    )

  if (any(!is.na(d$Tendência))) {
    out <- echarts4r::e_line(
      out, Tendência, name = "Tendência", symbol = "none",
      lineStyle = list(width = 2.5, color = color),
      itemStyle = list(color = color), connectNulls = TRUE
    )
  }

  echart_finish(out, y_name, window_start, zero_line = zero_line)
}

# Several named series from a wide df (date + one column per series).
echart_wide_lines <- function(df, cols, y_name, window_start = NULL,
                              zero_line = FALSE) {

  d <- dplyr::arrange(df, date)
  present <- intersect(cols, names(d))
  if (length(present) == 0 || nrow(d) == 0) return(echart_empty())

  echarts4r::e_charts(d, date) |>
    add_lines(present, get_color_palette(length(present))) |>
    echart_finish(y_name, window_start, zero_line = zero_line)
}
