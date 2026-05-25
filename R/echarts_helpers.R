library(echarts4r)

source(here::here("R", "utils.R"))

# Long tibble -> echarts line chart, one series per source.
# When variable == "index", overlays the STL trend per source (dashed)
# on top of the raw index, sharing the same color.
echart_series <- function(df, city, variable_label, height = "320px") {

  stopifnot(variable_label %in% names(vlvar))
  sel_var <- unname(vlvar[variable_label])

  d <- df |>
    dplyr::filter(name_muni == city, !is.na(.data[[sel_var]])) |>
    dplyr::arrange(date)

  if (nrow(d) == 0) {
    return(
      echarts4r::e_charts() |>
        echarts4r::e_title("Sem dados para a seleção")
    )
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

  e <- wide |>
    echarts4r::e_charts(date, height = height)

  for (i in seq_along(sources)) {
    src   <- sources[i]
    color <- colors[i]
    e <- echarts4r::e_line_(
      e,
      serie        = src,
      name         = src,
      lineStyle    = list(width = 2, color = color),
      itemStyle    = list(color = color),
      symbol       = "none",
      connectNulls = TRUE
    )
  }

  if (show_trend_overlay) {
    for (i in seq_along(sources)) {
      src        <- sources[i]
      trend_name <- paste0(src, " (tendência)")
      if (!trend_name %in% names(wide)) next
      color <- colors[i]
      e <- echarts4r::e_line_(
        e,
        serie        = trend_name,
        name         = trend_name,
        lineStyle    = list(width = 1.5, color = color, type = "dashed"),
        itemStyle    = list(color = color),
        symbol       = "none",
        connectNulls = TRUE
      )
    }
  }

  e |>
    echarts4r::e_tooltip(trigger = "axis") |>
    echarts4r::e_legend(top = 0, type = "scroll") |>
    echarts4r::e_grid(top = 50, bottom = 60) |>
    echarts4r::e_datazoom(type = "slider", start = 70, end = 100) |>
    echarts4r::e_x_axis(type = "time") |>
    echarts4r::e_y_axis(
      name         = variable_label,
      nameLocation = "middle",
      nameGap      = 45
    ) |>
    echarts4r::e_mark_line(
      data      = list(yAxis = 0),
      lineStyle = list(color = "#333", type = "solid", width = 1),
      symbol    = "none",
      silent    = TRUE
    ) |>
    echarts4r::e_toolbox_feature(feature = "saveAsImage")
}

echart_palette <- function(n) {
  if (n <= 5) return(get_color_palette(n))
  base <- c("#264653", "#2A9D8F", "#8AB17D", "#E9C46A",
            "#F4A261", "#E76F51", "#287271", "#EFB366", "#EE8959")
  rep_len(base, n)
}
