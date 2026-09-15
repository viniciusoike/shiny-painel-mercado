# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

library(echarts4r)

source(here::here("R", "utils.R"))

# Variables stored as fractions that should display as percentages.
PCT_VARS <- c("chg", "acum12m")

# Shared options ---------------------------------------------------------------

# Brazilian-formatted tooltip value formatter. `digits` decimal places,
# `suffix` appended (e.g. "%"), `round_to` rounds the value to the nearest
# multiple before formatting (100 -> hundreds, 12321 -> 12.300). Returns a JS
# function for the `valueFormatter` slot of e_tooltip(); echarts keeps its
# default axis layout (date header + colored markers) and only the numbers are
# reformatted. decimal.mark "," and big.mark "." come from the pt-BR locale.
tooltip_value_formatter <- function(digits = 0, suffix = "", round_to = 1) {
  htmlwidgets::JS(sprintf(
    "function(value){
       var v = Array.isArray(value) ? value[value.length - 1] : value;
       if (v === null || v === undefined || isNaN(v)) return '–';
       v = Number(v);
       if (%d > 1) v = Math.round(v / %d) * %d;
       return v.toLocaleString('pt-BR', {minimumFractionDigits: %d, maximumFractionDigits: %d}) + '%s';
     }",
    round_to,
    round_to,
    round_to,
    digits,
    digits,
    suffix
  ))
}

# Pick a tooltip formatter from the y-axis name. Percentage charts (y_name
# contains "%") show one decimal and a "%" suffix; unit counts ("Unidades")
# round to the nearest hundred; everything else shows whole numbers.
tooltip_for <- function(y_name) {
  if (grepl("%", y_name, fixed = TRUE)) {
    tooltip_value_formatter(digits = 1, suffix = "%")
  } else if (grepl("Unidades", y_name, fixed = TRUE)) {
    tooltip_value_formatter(digits = 0, round_to = 100)
  } else {
    tooltip_value_formatter(digits = 0)
  }
}

# Tooltip formatter for the Atividade cards. Index levels and percentage-point
# differences read better with one decimal; head counts and R$ values stay whole.
activity_tooltip <- function(unit) {
  if (grepl("%", unit, fixed = TRUE)) {
    tooltip_value_formatter(digits = 1, suffix = "%")
  } else if (grepl("índice|p\\.p\\.", unit)) {
    tooltip_value_formatter(digits = 1)
  } else {
    tooltip_value_formatter(digits = 0)
  }
}

# Tooltip, legend, grid, time axis, zero markline, datazoom and toolbox.
# window_start (Date or NULL) sets the initial zoom; NULL shows everything.
# zero_line is for variables centered on zero (% changes); index levels skip it.
# `tooltip_fmt` overrides the y_name-derived number format (see tooltip_for()).
echart_finish <- function(
  e,
  y_name,
  window_start = NULL,
  zero_line = TRUE,
  tooltip_fmt = tooltip_for(y_name),
  y_min = NULL
) {
  e <- e |>
    echarts4r::e_tooltip(trigger = "axis", valueFormatter = tooltip_fmt) |>
    echarts4r::e_legend(top = 0, type = "scroll") |>
    echarts4r::e_grid(top = 50, bottom = 60) |>
    echarts4r::e_x_axis(type = "time") |>
    echarts4r::e_y_axis(
      name = y_name,
      nameLocation = "middle",
      nameGap = 45,
      min = y_min,
      scale = is.null(y_min)
    ) |>
    echarts4r::e_toolbox_feature(feature = "saveAsImage")

  if (zero_line) {
    e <- echarts4r::e_mark_line(
      e,
      data = list(yAxis = 0),
      lineStyle = list(color = "#333", type = "solid", width = 1),
      symbol = "none",
      silent = TRUE
    )
  }

  if (is.null(window_start)) {
    echarts4r::e_datazoom(e, type = "slider", start = 0)
  } else {
    echarts4r::e_datazoom(
      e,
      type = "slider",
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
      serie = series[i],
      name = series[i],
      lineStyle = list(
        width = width,
        color = colors[i],
        type = if (dashed) "dashed" else "solid"
      ),
      itemStyle = list(color = colors[i]),
      symbol = "none",
      connectNulls = TRUE
    )
  }
  e
}

# Multi-source series ----------------------------------------------------------

# Long tibble -> line chart, one series per index source for one city.
# When variable == "index", overlays the STL trend per source (dashed).
echart_series <- function(dat, city, variable_label, window_start = NULL) {
  stopifnot(variable_label %in% names(vlvar))
  sel_var <- unname(vlvar[variable_label])

  d <- dat |>
    dplyr::filter(name_muni == city, !is.na(.data[[sel_var]])) |>
    dplyr::arrange(date)

  if (nrow(d) == 0) {
    return(echart_empty())
  }

  if (sel_var %in% PCT_VARS) {
    d[[sel_var]] <- round(d[[sel_var]] * 100, 2)
  } else {
    d[[sel_var]] <- round(d[[sel_var]], 2)
  }

  sources <- sort(unique(d$source))
  colors <- echart_palette(length(sources))
  show_trend_overlay <- identical(sel_var, "index")

  wide <- d |>
    tidyr::pivot_wider(
      id_cols = "date",
      names_from = "source",
      values_from = dplyr::all_of(sel_var)
    )

  if (show_trend_overlay) {
    trend_wide <- d |>
      tidyr::pivot_wider(
        id_cols = "date",
        names_from = "source",
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
    trend_cols <- colors[match(
      sub(" \\(tendência\\)$", "", trend_names),
      sources
    )]
    e <- add_lines(e, trend_names, trend_cols, dashed = TRUE, width = 1.5)
  }

  echart_finish(
    e,
    variable_label,
    window_start,
    zero_line = !show_trend_overlay
  )
}

# City comparison --------------------------------------------------------------

# One line per city for a single source/variable (defaults: FipeZap, acum12m).
echart_compare <- function(
  dat,
  cities,
  sel_var = "acum12m",
  y_name = "Acumulado 12 Meses (%)",
  window_start = NULL
) {
  d <- dat |>
    dplyr::filter(name_muni %in% cities, !is.na(.data[[sel_var]])) |>
    dplyr::arrange(date)

  if (nrow(d) == 0 || length(cities) == 0) {
    return(echart_empty())
  }

  if (sel_var %in% PCT_VARS) {
    d[[sel_var]] <- round(d[[sel_var]] * 100, 2)
  }

  present <- intersect(cities, unique(d$name_muni))
  colors <- echart_palette(length(present))

  wide <- d |>
    tidyr::pivot_wider(
      id_cols = "date",
      names_from = "name_muni",
      values_from = dplyr::all_of(sel_var)
    )

  echarts4r::e_charts(wide, date) |>
    add_lines(present, colors) |>
    echart_finish(y_name, window_start)
}


echart_palette <- function(n) get_color_palette(n)


# Single monthly series: faint raw line + bold prepared trend.
# `dat` has columns date, value and trend. `tooltip_fmt = NULL` falls back to the
# y_name-derived formatter from tooltip_for(); pass an explicit formatter to
# override (e.g. for "Meses" which needs 1 decimal but no % suffix).
echart_trend_single <- function(
  dat,
  y_name,
  raw_name = "Mensal",
  window_start = NULL,
  zero_line = FALSE,
  tooltip_fmt = NULL
) {
  d <- dat |>
    dplyr::filter(!is.na(value)) |>
    dplyr::arrange(date) |>
    dplyr::rename(!!raw_name := value)

  if (nrow(d) < 2) {
    return(echart_empty())
  }

  color <- get_color_palette(1)
  d$Tendência <- if ("trend" %in% names(d)) d$trend else NA_real_

  out <- echarts4r::e_charts(d, date) |>
    echarts4r::e_line_(
      serie = raw_name,
      name = raw_name,
      symbol = "none",
      lineStyle = list(width = 1, color = color, opacity = 0.35),
      itemStyle = list(color = color)
    )

  if (any(!is.na(d$Tendência))) {
    out <- echarts4r::e_line(
      out,
      Tendência,
      name = "Tendência",
      symbol = "none",
      lineStyle = list(width = 2.5, color = color),
      itemStyle = list(color = color),
      connectNulls = TRUE
    )
  }

  fmt <- if (is.null(tooltip_fmt)) tooltip_for(y_name) else tooltip_fmt
  echart_finish(
    out,
    y_name,
    window_start,
    zero_line = zero_line,
    tooltip_fmt = fmt
  )
}

# Grouped (dodged) yearly bars: a category x-axis of years with one bar series
# per index. `dat` is wide (year + one numeric column per series in `cols`).
echart_yearly_bars <- function(
  dat,
  cols,
  labels = cols,
  y_name = "Acum. no ano (%)"
) {
  d <- dat[order(dat$year), , drop = FALSE]
  present <- intersect(cols, names(d))
  if (length(present) == 0 || nrow(d) == 0) {
    return(echart_empty())
  }
  d$year <- as.character(d$year)

  colors <- get_color_palette(length(cols))
  e <- echarts4r::e_charts_(d, "year")
  for (i in seq_along(cols)) {
    if (!cols[i] %in% names(d)) {
      next
    }
    e <- echarts4r::e_bar_(
      e,
      cols[i],
      name = labels[i],
      itemStyle = list(color = colors[i])
    )
  }

  e |>
    echarts4r::e_tooltip(
      trigger = "axis",
      valueFormatter = tooltip_value_formatter(digits = 1, suffix = "%")
    ) |>
    echarts4r::e_legend(top = 0, type = "scroll") |>
    echarts4r::e_grid(top = 45, bottom = 30) |>
    echarts4r::e_x_axis(type = "category") |>
    echarts4r::e_y_axis(
      name = y_name,
      nameLocation = "middle",
      nameGap = 40,
      scale = TRUE
    ) |>
    echarts4r::e_mark_line(
      data = list(yAxis = 0),
      lineStyle = list(color = "#333", type = "solid", width = 1),
      symbol = "none",
      silent = TRUE
    ) |>
    echarts4r::e_toolbox_feature(feature = "saveAsImage")
}

# Stacked area: one filled band per column of a wide date frame (the mix of a
# total over time). Bands are drawn in `cols` order, bottom to top.
echart_stacked_area <- function(dat, cols, y_name, window_start = NULL) {
  d <- dplyr::arrange(dat, date)
  present <- intersect(cols, names(d))
  if (length(present) == 0 || nrow(d) == 0) {
    return(echart_empty())
  }

  colors <- get_color_palette(length(present))
  e <- echarts4r::e_charts(d, date)
  for (i in seq_along(present)) {
    e <- echarts4r::e_area_(
      e,
      present[i],
      name = present[i],
      stack = "total",
      symbol = "none",
      connectNulls = TRUE,
      lineStyle = list(width = 1, color = colors[i]),
      areaStyle = list(color = colors[i], opacity = 0.75),
      itemStyle = list(color = colors[i])
    )
  }
  # Stacked areas must read from a zero baseline, else the band proportions lie.
  echart_finish(e, y_name, window_start, zero_line = FALSE, y_min = 0)
}


# 100% stacked bars: each row (year) normalized so its bands sum to 100. `dat`
# is a wide frame (year + one share column per band, already in percent).
echart_share_bars <- function(
  dat,
  cols,
  labels = cols,
  y_name = "Participação (%)"
) {
  d <- dat[order(dat$year), , drop = FALSE]
  present <- intersect(cols, names(d))
  if (length(present) == 0 || nrow(d) == 0) {
    return(echart_empty())
  }
  # Drop years with no data (e.g. an in-progress current year).
  d <- d[rowSums(!is.na(as.matrix(d[present]))) > 0, , drop = FALSE]
  if (nrow(d) == 0) {
    return(echart_empty())
  }
  d$year <- as.character(d$year)

  colors <- get_color_palette(length(present))
  e <- echarts4r::e_charts_(d, "year")
  for (i in seq_along(present)) {
    e <- echarts4r::e_bar_(
      e,
      present[i],
      name = labels[match(present[i], cols)],
      stack = "total",
      itemStyle = list(color = colors[i])
    )
  }

  e |>
    echarts4r::e_tooltip(
      trigger = "axis",
      valueFormatter = tooltip_value_formatter(digits = 1, suffix = "%")
    ) |>
    echarts4r::e_legend(top = 0, type = "scroll") |>
    echarts4r::e_grid(top = 45, bottom = 30) |>
    echarts4r::e_x_axis(type = "category") |>
    echarts4r::e_y_axis(
      name = y_name,
      nameLocation = "middle",
      nameGap = 40,
      min = 0,
      max = 100
    ) |>
    echarts4r::e_toolbox_feature(feature = "saveAsImage")
}

# Several named series from a wide dat (date + one column per series).
echart_wide_lines <- function(
  dat,
  cols,
  y_name,
  window_start = NULL,
  zero_line = FALSE,
  tooltip_fmt = NULL
) {
  d <- dplyr::arrange(dat, date)
  present <- intersect(cols, names(d))
  if (length(present) == 0 || nrow(d) == 0) {
    return(echart_empty())
  }

  fmt <- if (is.null(tooltip_fmt)) tooltip_for(y_name) else tooltip_fmt
  echarts4r::e_charts(d, date) |>
    add_lines(present, get_color_palette(length(present))) |>
    echart_finish(
      y_name,
      window_start,
      zero_line = zero_line,
      tooltip_fmt = fmt
    )
}
