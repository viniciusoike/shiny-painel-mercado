# Ekio palette (mockup-brief.md): ordered so get_color_palette() picks
# blue/orange first, then teal, light blue, green.
pal <- c("#1E3A5F", "#2B4C7E", "#4A90C2", "#7EB6D8", "#DD6B20",
         "#D69E2E", "#38A169", "#805AD5", "#2C7A7B")

get_color_palette <- function(n) {
  if (n == 1) return(pal[1])
  if (n == 2) return(pal[c(1, 5)])
  if (n == 3) return(pal[c(1, 5, 9)])
  if (n == 4) return(pal[c(1, 3, 5, 9)])
  if (n == 5) return(pal[c(1, 3, 5, 7, 9)])
  pal
}

# Formatting ------------------------------------------------------------------

# Fraction -> signed pt-BR percentage ("0.072" -> "+7,2%").
fmt_pct_br <- function(x, digits = 1) {
  out <- sprintf(paste0("%+.", digits, "f%%"), x * 100)
  out <- sub("\\.", ",", out)
  out[is.na(x)] <- "—"
  out
}

# pt-BR number with comma decimal ("14.75" -> "14,75").
fmt_num_br <- function(x, digits = 2) {
  out <- formatC(x, format = "f", digits = digits, big.mark = ".",
                 decimal.mark = ",")
  out[is.na(x)] <- "—"
  out
}

# Trailing 12-month accumulated % from a vector of monthly % changes.
acum12m_pct <- function(monthly_pct) {
  logr <- log1p(monthly_pct / 100)
  acc  <- stats::filter(logr, rep(1, 12), sides = 1)
  as.numeric(expm1(acc) * 100)
}

# KPI deltas -------------------------------------------------------------------

# Direction of a delta for coloring a KPI card. Guards against the length-0
# diff() of a degraded series with < 2 points.
pp_dir <- function(d) {
  if (length(d) == 0 || is.na(d)) "neutral" else if (d >= 0) "up" else "down"
}

# Signed "pp" delta label ("+1,23 pp"); "—" when there is no valid delta.
pp_lbl <- function(d) {
  if (length(d) == 0 || is.na(d)) return("—")
  sub("\\.", ",", sprintf("%+.2f pp", d))
}

# KPI cards (Panorama) ---------------------------------------------------------

# Normalize the last `n` values of a series to bar heights (3%..100%) and
# render the mockup's CSS bar sparkline.
kpi_sparkline <- function(values, n = 12) {
  v <- utils::tail(values[!is.na(values)], n)
  if (length(v) < 2) return(NULL)
  rng <- range(v)
  span <- if (diff(rng) == 0) 1 else diff(rng)
  heights <- 3 + (v - rng[1]) / span * 97
  shiny::div(
    class = "kpi-sparkline",
    lapply(heights, function(h) {
      shiny::div(class = "bar", style = sprintf("height:%.0f%%", h))
    })
  )
}

# One KPI card. `value`/`delta` are preformatted strings; `dir` in
# up/down/neutral colors the delta; `color` is a mockup accent class.
kpi_card <- function(label, value, delta, period, spark_values,
                     color = "blue", dir = "neutral") {
  shiny::div(
    class = paste("kpi-card", color),
    shiny::div(class = "kpi-label", label),
    shiny::div(class = "kpi-value", value),
    shiny::div(
      class = "kpi-meta",
      shiny::span(class = paste("kpi-delta", dir), delta),
      shiny::span(class = "kpi-period", paste("·", period))
    ),
    kpi_sparkline(spark_values)
  )
}

# Yearly accumulated table -----------------------------------------------------

# Scrollable year × index table (Ano | INCC | IPCA | IGMI-R | IVAR), most recent
# year first. `df` is the wide frame from yearly_accum_data(); NA cells show "—".
yearly_accum_table <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(shiny::p("Sem dados."))
  d <- df[order(df$year, decreasing = TRUE), , drop = FALSE]

  num_cell <- function(x) {
    if (is.na(x)) return(shiny::tags$td(class = "num", "—"))
    cls <- if (x >= 0) "num positive" else "num negative"
    shiny::tags$td(class = cls, sub("\\.", ",", sprintf("%+.1f%%", x)))
  }

  shiny::div(
    class = "table-scroll",
    shiny::tags$table(
      class = "mini-table",
      shiny::tags$thead(
        shiny::tags$tr(
          shiny::tags$th("Ano"),
          shiny::tags$th(class = "num", "INCC"),
          shiny::tags$th(class = "num", "IPCA"),
          shiny::tags$th(class = "num", "IGMI-R"),
          shiny::tags$th(class = "num", "IVAR")
        )
      ),
      shiny::tags$tbody(
        lapply(seq_len(nrow(d)), function(i) {
          shiny::tags$tr(
            shiny::tags$td(d$year[i]),
            num_cell(d$incc[i]),
            num_cell(d$ipca[i]),
            num_cell(d$igmi[i]),
            num_cell(d$ivar[i])
          )
        })
      )
    )
  )
}

# Summary table ----------------------------------------------------------------

# Last-month summary per city (mockup "Resumo por Cidade"). sale/rent are
# long RPPI tibbles already filtered to a single source.
city_summary_table <- function(sale, rent, cities) {

  last_obs <- function(df) {
    df |>
      dplyr::filter(name_muni %in% cities, !is.na(acum12m)) |>
      dplyr::group_by(name_muni) |>
      dplyr::filter(date == max(date)) |>
      dplyr::ungroup()
  }

  s <- last_obs(sale) |>
    dplyr::select(name_muni, sale_12m = acum12m, sale_chg = chg)
  r <- last_obs(rent) |>
    dplyr::select(name_muni, rent_12m = acum12m)

  # Rank cities by the headline metric (12m sale variation), highest first.
  tbl <- dplyr::left_join(s, r, by = "name_muni") |>
    dplyr::arrange(dplyr::desc(sale_12m))

  if (nrow(tbl) == 0) return(shiny::p("Sem dados."))

  num_cell <- function(x, digits = 1) {
    cls <- if (is.na(x) || x >= 0) "num positive" else "num negative"
    shiny::tags$td(class = cls, fmt_pct_br(x, digits))
  }

  shiny::tags$table(
    class = "mini-table",
    shiny::tags$thead(
      shiny::tags$tr(
        shiny::tags$th("Cidade"),
        shiny::tags$th("Venda 12m"),
        shiny::tags$th("Aluguel 12m"),
        shiny::tags$th("Var. Mensal")
      )
    ),
    shiny::tags$tbody(
      lapply(seq_len(nrow(tbl)), function(i) {
        shiny::tags$tr(
          shiny::tags$td(tbl$name_muni[i]),
          num_cell(tbl$sale_12m[i]),
          num_cell(tbl$rent_12m[i]),
          num_cell(tbl$sale_chg[i], digits = 2)
        )
      })
    )
  )
}
