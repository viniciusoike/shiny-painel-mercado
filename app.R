# Packages and data ----------------------------------------------------------

library(shiny)
library(bslib)
library(echarts4r)
library(dplyr)
library(here)

source(here::here("R", "utils.R"))
source(here::here("R", "_setup.R"))
source(here::here("R", "echarts_helpers.R"))

# Theme -----------------------------------------------------------------------

# brand.yml is loaded implicitly by bs_theme(brand = TRUE) — referenced here
# so dependency tools (renv) track it.
if (!requireNamespace("brand.yml", quietly = TRUE)) {
  stop("Package 'brand.yml' is required for the Ekio theme (_brand.yml).")
}

theme <- bslib::bs_theme(version = 5, brand = TRUE) |>
  bslib::bs_add_rules(readLines(here::here("styles.css")))

# UI helpers ------------------------------------------------------------------

page_header <- function(title, subtitle) {
  shiny::div(
    class = "page-header",
    shiny::h2(title),
    shiny::p(subtitle)
  )
}

ekio_nav_item <- function(value, label, icon, active = FALSE) {
  shiny::tags$a(
    class = paste0("ekio-nav-item", if (active) " active" else ""),
    `data-value` = value,
    role = "link",
    tabindex = "0",
    `aria-current` = if (active) "page" else NULL,
    shiny::tags$span(class = "nav-icon", `aria-hidden` = "true", icon),
    shiny::tags$span(label)
  )
}

ekio_nav_section <- function(label, ...) {
  shiny::div(
    class = "ekio-nav-section",
    if (!is.null(label)) shiny::div(class = "ekio-nav-label", label),
    ...
  )
}


about_card <- function(title, text) {
  shiny::div(
    class = "about-card",
    shiny::h4(title),
    shiny::p(text)
  )
}

chart_card <- function(title, tag, ..., height = "300px", output_id = NULL) {
  bslib::card(
    full_screen = TRUE,
    bslib::card_header(
      class = "chart-card-header",
      shiny::span(title),
      shiny::span(class = "chart-tag", tag)
    ),
    ...,
    if (!is.null(output_id)) {
      echarts4r::echarts4rOutput(output_id, height = height)
    }
  )
}

filter_group <- function(label, ..., class = NULL, style = NULL) {
  shiny::div(
    class = paste(c("filter-group", class), collapse = " "),
    style = style,
    shiny::tags$label(label),
    ...
  )
}

# Trend-chart card module. Renders the faint-raw + bold-STL trend chart used
# across every dense tab. `title = NULL` in the UI draws a reactive title that
# the server fills via the `title` reactive; pass a string for a static one.
trend_card_ui <- function(id, title, tag, height = "260px") {
  ns <- shiny::NS(id)
  ttl <- if (is.null(title)) {
    shiny::textOutput(ns("title"), inline = TRUE)
  } else {
    title
  }
  chart_card(ttl, tag, output_id = ns("chart"), height = height)
}

trend_card_server <- function(
  id,
  data,
  y_name,
  raw_name = "Mensal",
  window = shiny::reactive(NULL),
  title = NULL
) {
  shiny::moduleServer(id, function(input, output, session) {
    output$chart <- echarts4r::renderEcharts4r({
      echart_trend_single(data(), y_name, raw_name, window())
    })
    if (!is.null(title)) {
      output$title <- shiny::renderText(title())
    }
  })
}

# Titles for the metric selected in the Preços filter bar
METRIC_TITLES <- c(
  acum12m = "Variação 12 Meses",
  chg = "Variação Mensal",
  trend_yoy = "Tendência YoY (STL)"
)

# Pages -----------------------------------------------------------------------

page_panorama <- shiny::tagList(
  page_header("Panorama", "Visão geral do mercado imobiliário brasileiro"),
  shiny::uiOutput("kpi_grid"),
  bslib::layout_columns(
    col_widths = c(7, 5),
    chart_card(
      "Preço de Venda — Tendência (RPPI)",
      "STL trend",
      output_id = "pan_trend",
      height = "300px"
    ),
    chart_card(
      "Selic × IPCA — Juros Reais",
      "% a.a.",
      output_id = "pan_rate",
      height = "300px"
    )
  ),
  bslib::layout_columns(
    col_widths = c(12),
    chart_card(
      "Volume de Crédito Imobiliário — SBPE",
      "R$ bilhões",
      output_id = "pan_credit",
      height = "280px"
    )
  )
)

page_precos <- shiny::tagList(
  page_header("Preços", "Índices de preços residenciais — venda e aluguel"),

  shiny::uiOutput("precos_kpi_grid"),

  shiny::div(
    class = "filter-bar",
    filter_group(
      "Métrica",
      class = "filter-chips",
      shiny::radioButtons(
        "metric",
        NULL,
        inline = TRUE,
        choices = c(
          "Var. 12m" = "acum12m",
          "Var. mensal" = "chg"
        ),
        selected = "acum12m"
      )
    ),
    filter_group(
      "Período",
      style = "margin-left:auto;",
      shiny::selectInput(
        "period",
        NULL,
        choices = c(
          "3 anos" = "3",
          "5 anos" = "5",
          "10 anos" = "10",
          "Máximo" = "0"
        ),
        selected = "5",
        width = "110px"
      )
    )
  ),

  bslib::layout_columns(
    col_widths = c(6, 6),
    chart_card(
      "Preços vs. Inflação — Brasil (12m)",
      "% · IGMI-R / INCC / IPCA",
      output_id = "plot_precos_infl"
    ),
    chart_card(
      "Venda vs. Aluguel — Brasil (12m)",
      "% · IGMI-R / IVAR",
      output_id = "plot_precos_venda_aluguel"
    )
  ),

  bslib::layout_columns(
    col_widths = c(6, 6),
    chart_card(
      shiny::textOutput("t_sale_var", inline = TRUE),
      "%",
      output_id = "plot_sale_var",
      height = "260px"
    ),
    chart_card(
      shiny::textOutput("t_rent_var", inline = TRUE),
      "%",
      output_id = "plot_rent_var",
      height = "260px"
    )
  ),

  bslib::layout_columns(
    col_widths = c(7, 5),
    chart_card(
      "Acumulado Anual por Índice — Brasil",
      "% no ano",
      output_id = "plot_yearly_bars",
      height = "300px"
    ),
    bslib::card(
      full_screen = TRUE,
      bslib::card_header(
        class = "chart-card-header",
        shiny::span("Variação Anual — Histórico"),
        shiny::span(class = "chart-tag", "% no ano")
      ),
      bslib::card_body(class = "p-0", shiny::uiOutput("yearly_table"))
    )
  ),

  bslib::layout_columns(
    col_widths = c(7, 5),
    chart_card(
      "Comparativo de Cidades — Venda 12m",
      "% a.a. · FipeZap",
      shiny::selectizeInput(
        "cmp_cities",
        NULL,
        choices = NULL,
        multiple = TRUE,
        options = list(maxItems = 5, placeholder = "Escolha até 5 cidades"),
        width = "100%"
      ),
      output_id = "plot_compare",
      height = "280px"
    ),
    bslib::card(
      full_screen = TRUE,
      bslib::card_header(
        class = "chart-card-header",
        shiny::span("Resumo por Cidade — Último Mês"),
        shiny::span(class = "chart-tag", "FipeZap")
      ),
      bslib::card_body(class = "p-0", shiny::uiOutput("city_table"))
    )
  )
)

period_filter <- function(id, selected = "10") {
  filter_group(
    "Período",
    style = "margin-left:auto;",
    shiny::selectInput(
      id,
      NULL,
      choices = c("5 anos" = "5", "10 anos" = "10", "Máximo" = "0"),
      selected = selected,
      width = "110px"
    )
  )
}

page_credito <- shiny::tagList(
  page_header(
    "Crédito",
    "Financiamento imobiliário, taxas e inadimplência — Abecip / BCB"
  ),
  shiny::div(class = "filter-bar", period_filter("cred_period")),
  bslib::layout_columns(
    col_widths = c(6, 6),
    trend_card_ui(
      "cred_volume",
      "Volume de Financiamento Imobiliário",
      "R$ milhões/mês"
    ),
    trend_card_ui("cred_units", "Unidades Financiadas", "unidades/mês")
  ),
  bslib::layout_columns(
    col_widths = c(6, 6),
    trend_card_ui(
      "cred_rate",
      "Taxa Média de Juros — Crédito Imobiliário PF",
      "% a.a."
    ),
    trend_card_ui(
      "cred_default",
      "Inadimplência — Crédito Imobiliário PF",
      "% atraso"
    )
  )
)

page_mercado <- shiny::tagList(
  page_header("Mercado", "Lançamentos, vendas e oferta — Abrainc / FIPE"),
  shiny::div(
    class = "filter-bar",
    filter_group(
      "Segmento",
      class = "filter-chips",
      shiny::radioButtons(
        "mkt_segmento",
        NULL,
        inline = TRUE,
        choices = names(ABRAINC_SEGMENTO),
        selected = "Total"
      )
    ),
    period_filter("mkt_period")
  ),
  bslib::layout_columns(
    col_widths = c(6, 6),
    trend_card_ui("mkt_launch", NULL, "unidades/mês"),
    trend_card_ui("mkt_sold", NULL, "unidades/mês")
  ),
  bslib::layout_columns(
    col_widths = c(6, 6),
    trend_card_ui("mkt_supply", NULL, "estoque"),
    trend_card_ui("mkt_distrato", NULL, "unidades/mês")
  ),
  bslib::layout_columns(
    col_widths = c(6, 6),
    trend_card_ui("mkt_delivered", "Entregas de Unidades", "unidades/mês"),
    chart_card(
      "VGV — Lançamentos vs. Vendas",
      "R$ milhões",
      output_id = "mkt_vgv",
      height = "260px"
    )
  )
)

page_macro <- shiny::tagList(
  page_header("Macro", "Indicadores macroeconômicos — séries do Banco Central"),
  shiny::div(
    class = "filter-bar",
    period_filter("macro_period", selected = "5")
  ),
  bslib::layout_columns(
    col_widths = c(6, 6),
    trend_card_ui("macro_selic", "Selic — Meta", "% a.a."),
    chart_card(
      "Inflação — Acumulado 12 Meses",
      "%",
      output_id = "macro_infl",
      height = "260px"
    )
  ),
  bslib::layout_columns(
    col_widths = c(6, 6),
    chart_card(
      "Selic × IPCA — Juros Reais",
      "% a.a.",
      output_id = "macro_real",
      height = "260px"
    ),
    trend_card_ui(
      "macro_fimob",
      "Taxa de Financiamento Imobiliário PF",
      "% a.a."
    )
  ),
  bslib::layout_columns(
    col_widths = c(6, 6),
    chart_card(
      "Comprometimento de Renda vs. Endividamento",
      "% da renda",
      output_id = "macro_debt",
      height = "260px"
    ),
    trend_card_ui(
      "macro_default",
      "Inadimplência — Crédito Imobiliário PF",
      "% atraso"
    )
  )
)

page_saopaulo <- shiny::tagList(
  page_header(
    "São Paulo",
    "Dados detalhados do mercado paulistano — Secovi-SP"
  ),

  shiny::div(
    class = "filter-bar",
    filter_group(
      "Período",
      style = "margin-left:auto;",
      shiny::selectInput(
        "sp_period",
        NULL,
        choices = c("5 anos" = "5", "10 anos" = "10", "Máximo" = "0"),
        selected = "10",
        width = "110px"
      )
    )
  ),

  bslib::layout_columns(
    col_widths = c(6, 6),
    chart_card(
      "Lançamentos vs. Vendas",
      "unidades · soma 12m",
      output_id = "sp_launch_sales",
      height = "260px"
    ),
    chart_card(
      "VGV — Lançamentos vs. Vendas",
      "R$ milhões · soma 12m",
      output_id = "sp_vgv",
      height = "260px"
    )
  ),
  bslib::layout_columns(
    col_widths = c(6, 6),
    chart_card(
      "Vendas por Dormitório",
      "unidades · soma 12m",
      output_id = "sp_rooms_area",
      height = "260px"
    ),
    chart_card(
      "VSO por Dormitório",
      "% · tendência STL",
      output_id = "sp_rooms_vso",
      height = "260px"
    )
  ),
  bslib::layout_columns(
    col_widths = c(7, 5),
    chart_card(
      "Participação por Dormitório",
      "% · vendas/ano",
      output_id = "sp_rooms_share",
      height = "300px"
    ),
    bslib::card(
      full_screen = TRUE,
      bslib::card_header(
        class = "chart-card-header",
        shiny::span("Vendas Anuais por Dormitório"),
        shiny::span(class = "chart-tag", "unidades · soma anual")
      ),
      bslib::card_body(class = "p-0", shiny::uiOutput("sp_rooms_table"))
    )
  ),
  bslib::layout_columns(
    col_widths = c(12),
    trend_card_ui("sp_supply", "Oferta — Saldo de Unidades", "estoque")
  )
)

page_sobre <- shiny::tagList(
  page_header("Sobre", "Sobre este painel e a EKIO"),
  shiny::div(
    class = "about-content",
    shiny::h3("Painel do Mercado Imobiliário"),
    shiny::p(
      "Este painel reúne os principais indicadores do mercado imobiliário",
      " brasileiro em um único lugar. Diferente de fontes tradicionais que",
      " mostram dados brutos, aqui cada série é tratada estatisticamente:",
      " extraímos tendências, dessazonalizamos, e apresentamos a informação",
      " de forma que ela seja imediatamente útil para análise."
    ),
    shiny::h3("Fontes de Dados"),
    shiny::div(
      class = "about-grid",
      about_card(
        "RPPI — Índices de Preços",
        paste0(
          "Compilação de todos os índices de preços residenciais disponíveis: ",
          "FipeZAP, IVG-R (BCB), IVAR (FGV) e índices regionais."
        )
      ),
      about_card(
        "Abecip — Crédito Imobiliário",
        paste0(
          "Dados de financiamento do principal fornecedor de crédito ",
          "habitacional do Brasil (SBPE)."
        )
      ),
      about_card(
        "Abrainc — Mercado Primário",
        paste0(
          "Lançamentos, vendas e oferta do mercado de incorporação, ",
          "com segmentação econômico vs. alto padrão."
        )
      ),
      about_card(
        "Banco Central — Séries Macro",
        paste0(
          "Indicadores macroeconômicos (Selic, IPCA, IGP-M, PIB, emprego) ",
          "e métricas agregadas de crédito imobiliário."
        )
      ),
      about_card(
        "Secovi-SP — São Paulo",
        paste0(
          "Dados detalhados do mercado paulistano: lançamentos, vendas, ",
          "VSO, estoque e inadimplência condominial."
        )
      ),
      about_card(
        "realestatebr",
        paste0(
          "Pacote R open-source que agrega e padroniza todas as fontes ",
          "acima em uma API unificada."
        )
      )
    ),
    shiny::h3("Metodologia"),
    shiny::p(
      "Todas as séries temporais passam por decomposição STL (Seasonal and",
      " Trend decomposition using Loess) para extração de tendência.",
      " Variações são calculadas sobre dados dessazonalizados quando",
      " disponíveis. Comparações entre fontes respeitam diferenças",
      " metodológicas — não misturamos séries com bases distintas sem",
      " indicação explícita."
    ),
    shiny::h3("EKIO"),
    shiny::p(
      "A EKIO é uma consultoria especializada em análise do mercado",
      " imobiliário brasileiro. Combinamos rigor estatístico com",
      " conhecimento de domínio para produzir análises que informam",
      " decisões de investimento, desenvolvimento e política."
    ),
    shiny::p(
      shiny::tags$a(
        "Código no GitHub",
        href = "https://github.com/viniciusoike/shiny-painel-mercado",
        target = "_blank"
      )
    )
  )
)

# Sidebar ---------------------------------------------------------------------

ekio_sidebar <- bslib::sidebar(
  width = 240,
  bg = "#0D1B2A",
  class = "ekio-sidebar",
  shiny::div(
    class = "ekio-brand",
    shiny::h1("EKIO"),
    shiny::p("Mercado Imobiliário")
  ),
  shiny::tags$nav(
    class = "ekio-nav",
    ekio_nav_section(
      "Visão Geral",
      ekio_nav_item("panorama", "Panorama", "◉", active = TRUE)
    ),
    ekio_nav_section(
      "Indicadores",
      ekio_nav_item("precos", "Preços", "▤"),
      ekio_nav_item("credito", "Crédito", "◈"),
      ekio_nav_item("mercado", "Mercado", "▦"),
      ekio_nav_item("macro", "Macro", "◎")
    ),
    ekio_nav_section(
      "Regional",
      ekio_nav_item("saopaulo", "São Paulo", "◆")
    ),
    ekio_nav_section(
      NULL,
      ekio_nav_item("sobre", "Sobre", "ⓘ")
    )
  ),
  shiny::div(
    class = "ekio-sidebar-footer",
    shiny::uiOutput("sidebar_updated")
  )
)

# Sidebar links drive the hidden navset; active state toggles client-side.
# Activatable by mouse or keyboard (Enter/Space) since these are not real links.
nav_js <- "
function ekioActivateNav(el) {
  $('.ekio-nav-item').removeClass('active').removeAttr('aria-current');
  $(el).addClass('active').attr('aria-current', 'page');
  Shiny.setInputValue('sidebar_nav', $(el).data('value'));
}
$(document).on('click', '.ekio-nav-item', function() {
  ekioActivateNav(this);
});
$(document).on('keydown', '.ekio-nav-item', function(e) {
  if (e.key === 'Enter' || e.key === ' ') {
    e.preventDefault();
    ekioActivateNav(this);
  }
});
"

# UI --------------------------------------------------------------------------

ui <- bslib::page_sidebar(
  window_title = "Painel do Mercado Imobiliário — EKIO",
  theme = theme,
  fillable = FALSE,
  sidebar = ekio_sidebar,
  shiny::div(
    class = "ekio-pages",
    bslib::navset_hidden(
      id = "main_nav",
      bslib::nav_panel_hidden("panorama", page_panorama),
      bslib::nav_panel_hidden("precos", page_precos),
      bslib::nav_panel_hidden("credito", page_credito),
      bslib::nav_panel_hidden("mercado", page_mercado),
      bslib::nav_panel_hidden("macro", page_macro),
      bslib::nav_panel_hidden("saopaulo", page_saopaulo),
      bslib::nav_panel_hidden("sobre", page_sobre)
    )
  ),
  shiny::tags$script(shiny::HTML(nav_js))
)

# Initial data ----------------------------------------------------------------

# Loaded once at app startup and shared across sessions. The data is static for
# the life of the process: the app ships a pre-warmed cache (see tools/prewarm.R)
# and never refetches at runtime, so it stays stateless and deploy-friendly. To
# publish fresh data, re-run prewarm and redeploy. Each session reads these
# objects through trivial reactives.
initial_data <- list(
  rppi = load_rppi(force = FALSE),
  bcb = load_dataset("bcb_series", force = FALSE),
  selic = load_dataset("bcb_selic", force = FALSE),
  sbpe = load_dataset("abecip_units", force = FALSE),
  secovi = load_dataset("secovi", force = FALSE),
  abrainc = load_dataset("abrainc", force = FALSE)
)

# Server ----------------------------------------------------------------------

server <- function(input, output, session) {
  # Data ----

  # Read-only views of the startup data; the app never refetches at runtime.
  rppi_data <- shiny::reactive(initial_data$rppi)
  bcb_data <- shiny::reactive(initial_data$bcb)
  selic_data <- shiny::reactive(initial_data$selic)
  sbpe_units <- shiny::reactive(initial_data$sbpe)
  secovi_data <- shiny::reactive(initial_data$secovi)
  abrainc_data <- shiny::reactive(initial_data$abrainc)

  splits <- shiny::reactive({
    split_rppi(rppi_data())
  })

  fipezap <- shiny::reactive({
    sp <- splits()
    list(
      sale = dplyr::filter(sp$sale, source == "FipeZap"),
      rent = dplyr::filter(sp$rent, source == "FipeZap")
    )
  })

  ipca <- shiny::reactive({
    dplyr::filter(bcb_data(), name_simplified == "ipca")
  })

  # Initial datazoom window from the "Período" filter (NULL = everything)
  window_start <- shiny::reactive({
    yrs <- as.numeric(input$period %||% "5")
    if (is.na(yrs) || yrs == 0) {
      return(NULL)
    }
    max(rppi_data()$date, na.rm = TRUE) %m-% lubridate::years(yrs)
  })

  # Navigation ----

  shiny::observeEvent(input$sidebar_nav, {
    bslib::nav_select("main_nav", input$sidebar_nav)
  })

  output$sidebar_updated <- shiny::renderUI({
    ts <- attr(rppi_data(), "fetched_at")
    label <- if (is.null(ts)) "—" else format(ts, "%d/%m/%Y")
    shiny::tagList(
      shiny::div(class = "ekio-updated-label", "Dados atualizados em"),
      shiny::div(class = "ekio-updated-date", label)
    )
  })

  # Inputs ----

  shiny::observe({
    # Seed the comparison selectize once at startup with the main capitals.
    cmp_choices <- sort(unique(fipezap()$sale$name_muni))
    cmp_current <- shiny::isolate(input$cmp_cities)
    cmp_selected <- if (
      !is.null(cmp_current) && all(cmp_current %in% cmp_choices)
    ) {
      cmp_current
    } else {
      utils::head(intersect(MAIN_CITIES, cmp_choices), 5)
    }
    shiny::updateSelectizeInput(
      session,
      "cmp_cities",
      choices = cmp_choices,
      selected = cmp_selected
    )
  })

  # Card titles ----

  metric_title <- shiny::reactive({
    shiny::req(input$metric)
    unname(METRIC_TITLES[input$metric])
  })

  output$t_sale_var <- shiny::renderText({
    paste0(metric_title(), " — Venda (Brasil)")
  })
  output$t_rent_var <- shiny::renderText({
    paste0(metric_title(), " — Aluguel (Brasil)")
  })

  # Charts ----

  # Preços vs. inflação (Brasil, 12m): IGMI-R price index vs. INCC and IPCA.
  output$plot_precos_infl <- echarts4r::renderEcharts4r({
    igmi <- splits()$sale |>
      dplyr::filter(
        source == "IGMI-R",
        name_muni == "Brazil",
        !is.na(acum12m)
      ) |>
      dplyr::transmute(date, `IGMI-R` = round(acum12m * 100, 2))
    bcb <- bcb_data()
    infl <- function(name) {
      bcb_pick(bcb, name) |>
        dplyr::transmute(date, value = round(acum12m_pct(value), 2))
    }
    wide <- igmi |>
      dplyr::full_join(
        dplyr::rename(infl("incc"), INCC = value),
        by = "date"
      ) |>
      dplyr::full_join(dplyr::rename(infl("ipca"), IPCA = value), by = "date")
    echart_wide_lines(
      wide,
      c("IGMI-R", "INCC", "IPCA"),
      "Acum. 12m (%)",
      window_start(),
      zero_line = TRUE
    )
  })

  # Venda vs. aluguel (Brasil, 12m): IGMI-R sale index vs. national IVAR (rent,
  # stored with name_muni = NA).
  output$plot_precos_venda_aluguel <- echarts4r::renderEcharts4r({
    sp <- splits()
    igmi <- sp$sale |>
      dplyr::filter(
        source == "IGMI-R",
        name_muni == "Brazil",
        !is.na(acum12m)
      ) |>
      dplyr::transmute(date, `IGMI-R (venda)` = round(acum12m * 100, 2))
    ivar <- sp$rent |>
      dplyr::filter(source == "IVAR", is.na(name_muni), !is.na(acum12m)) |>
      dplyr::transmute(date, `IVAR (aluguel)` = round(acum12m * 100, 2))
    wide <- dplyr::full_join(igmi, ivar, by = "date")
    echart_wide_lines(
      wide,
      c("IGMI-R (venda)", "IVAR (aluguel)"),
      "Acum. 12m (%)",
      window_start(),
      zero_line = TRUE
    )
  })

  # Metric pair is national (Brasil). Venda overlays IVG-R (Brazil-only) and
  # Aluguel overlays the national IVAR (stored with name_muni = NA).
  output$plot_sale_var <- echarts4r::renderEcharts4r({
    shiny::req(input$metric)
    label <- names(vlvar)[match(input$metric, vlvar)]
    echart_series(
      sale_with_ivgr(splits()$sale, "Brazil"),
      "Brazil",
      label,
      window_start()
    )
  })

  output$plot_rent_var <- echarts4r::renderEcharts4r({
    shiny::req(input$metric)
    label <- names(vlvar)[match(input$metric, vlvar)]
    echart_series(
      rent_with_ivar(splits()$rent, "Brazil"),
      "Brazil",
      label,
      window_start()
    )
  })

  output$plot_compare <- echarts4r::renderEcharts4r({
    shiny::req(input$cmp_cities)
    echart_compare(
      fipezap()$sale,
      input$cmp_cities,
      window_start = window_start()
    )
  })

  output$city_table <- shiny::renderUI({
    fz <- fipezap()
    city_summary_table(fz$sale, fz$rent, MAIN_CITIES)
  })

  # Yearly accumulated variation by index (bar + scrollable history table).
  precos_yearly <- shiny::reactive(yearly_accum_data(bcb_data(), splits()))

  output$plot_yearly_bars <- echarts4r::renderEcharts4r({
    d <- precos_yearly()
    d <- d[d$year >= 2022, , drop = FALSE]
    echart_yearly_bars(
      d,
      cols = c("incc", "ipca", "igmi", "ivar"),
      labels = c("INCC", "IPCA", "IGMI-R", "IVAR")
    )
  })

  output$yearly_table <- shiny::renderUI({
    yearly_accum_table(precos_yearly())
  })

  # Preços KPIs: 12-month accumulated variation for the headline national
  # indices (Brasil) and inflation references.
  output$precos_kpi_grid <- shiny::renderUI({
    sp <- splits()
    bcb <- bcb_data()

    # RPPI 12m card from the acum12m fraction (muni = NA for national IVAR).
    rppi_kpi <- function(df, src, muni, label, color) {
      d <- dplyr::filter(df, source == src)
      d <- if (is.na(muni)) {
        dplyr::filter(d, is.na(name_muni))
      } else {
        dplyr::filter(d, name_muni == muni)
      }
      d <- d |> dplyr::filter(!is.na(acum12m)) |> dplyr::arrange(date)
      v <- utils::tail(d$acum12m, 2)
      kpi_card(
        label,
        fmt_pct_br(utils::tail(v, 1)),
        pp_lbl(diff(v) * 100),
        "12m acum.",
        d$acum12m * 100,
        color = color,
        dir = pp_dir(diff(v))
      )
    }

    # Inflation 12m card from monthly % changes.
    infl_kpi <- function(name, label, color) {
      acc <- acum12m_pct(bcb_pick(bcb, name)$value)
      acc <- acc[!is.na(acc)]
      v <- utils::tail(acc, 2)
      kpi_card(
        label,
        paste0(fmt_num_br(utils::tail(acc, 1)), "%"),
        pp_lbl(diff(v)),
        "12m acum.",
        acc,
        color = color,
        dir = pp_dir(diff(v))
      )
    }

    shiny::div(
      class = "kpi-grid",
      rppi_kpi(sp$sale, "IGMI-R", "Brazil", "IGMI-R", "blue"),
      infl_kpi("incc", "INCC", "orange"),
      infl_kpi("ipca", "IPCA", "teal"),
      infl_kpi("igpm", "IGP-M", "amber"),
      rppi_kpi(sp$rent, "IVAR", NA, "IVAR", "green"),
      rppi_kpi(sp$sale, "FipeZap", "Brazil", "FipeZap (venda)", "purple"),
      rppi_kpi(sp$rent, "FipeZap", "Brazil", "FipeZap (aluguel)", "red")
    )
  })

  # Panorama ----

  # Fixed 5-year window for the executive-summary charts.
  pan_window <- shiny::reactive({
    max(rppi_data()$date, na.rm = TRUE) %m-% lubridate::years(5)
  })

  output$kpi_grid <- shiny::renderUI({
    fz <- fipezap()
    bcb <- bcb_data()

    # last two non-NA obs of a series, sorted by date
    tail2 <- function(df, col) {
      d <- df[!is.na(df[[col]]), ]
      d <- d[order(d$date), ]
      utils::tail(d[[col]], 2)
    }

    bcb_series_vals <- function(name) {
      d <- dplyr::filter(bcb, name_simplified == name) |> dplyr::arrange(date)
      d$value
    }

    # 1. Selic
    sel <- selic_data()$value
    selic_card <- kpi_card(
      "Selic",
      paste0(fmt_num_br(utils::tail(sel, 1)), "%"),
      pp_lbl(diff(utils::tail(sel, 2))),
      "a.a.",
      sel,
      color = "blue",
      dir = pp_dir(diff(utils::tail(sel, 2)))
    )

    # 2. IPCA / 3. IGP-M (12-month accumulated)
    infl_card <- function(name, label, color) {
      acc <- acum12m_pct(bcb_series_vals(name))
      acc <- acc[!is.na(acc)]
      d <- diff(utils::tail(acc, 2))
      kpi_card(
        label,
        paste0(fmt_num_br(utils::tail(acc, 1)), "%"),
        pp_lbl(d),
        "12m acum.",
        acc,
        color = color,
        dir = pp_dir(d)
      )
    }

    # 4/5. RPPI venda/aluguel SP (acum12m fraction)
    rppi_card <- function(df, label, color) {
      d <- dplyr::filter(df, name_muni == "São Paulo")
      v <- tail2(d, "acum12m")
      kpi_card(
        label,
        fmt_pct_br(utils::tail(v, 1)),
        pp_lbl(diff(v) * 100),
        "12m acum.",
        dplyr::filter(d, !is.na(acum12m))$acum12m * 100,
        color = color,
        dir = pp_dir(diff(v))
      )
    }

    # 6. Crédito SBPE (R$ bi, currency_total is in R$ million)
    cred <- sbpe_units()
    cv <- tail2(cred, "currency_total")
    cred_card <- kpi_card(
      "Crédito SBPE",
      paste0("R$ ", fmt_num_br(utils::tail(cv, 1) / 1000, 1), " bi"),
      {
        d <- (cv[2] / cv[1] - 1) * 100
        if (length(cv) < 2 || is.na(d)) {
          "—"
        } else {
          sub("\\.", ",", sprintf("%+.1f%%", d))
        }
      },
      "mensal",
      dplyr::filter(cred, !is.na(currency_total))$currency_total / 1000,
      color = "purple",
      dir = if (length(cv) == 2 && cv[2] >= cv[1]) "up" else "down"
    )

    # 7. VSO São Paulo
    vso <- dplyr::filter(
      secovi_data(),
      name == "vso_vendas_sobre_oferta",
      variable == "sales"
    )
    vv <- tail2(vso, "value")
    vso_card <- kpi_card(
      "VSO São Paulo",
      paste0(fmt_num_br(utils::tail(vv, 1), 1), "%"),
      pp_lbl(diff(vv)),
      "mensal",
      dplyr::arrange(vso, date)$value,
      color = "amber",
      dir = pp_dir(diff(vv))
    )

    # 8. Inadimplência (crédito direcionado PF)
    inad <- dplyr::filter(
      bcb,
      name_simplified == "inad_credito_direcionado_pf"
    ) |>
      dplyr::arrange(date)
    iv <- utils::tail(inad$value, 2)
    inad_card <- kpi_card(
      "Inadimplência",
      paste0(fmt_num_br(utils::tail(iv, 1), 2), "%"),
      pp_lbl(diff(iv)),
      "crédito PF",
      inad$value,
      color = "red",
      dir = pp_dir(diff(iv))
    )

    shiny::div(
      class = "kpi-grid",
      selic_card,
      infl_card("ipca", "IPCA", "orange"),
      infl_card("igpm", "IGP-M", "teal"),
      rppi_card(fz$sale, "RPPI Venda SP", "blue"),
      rppi_card(fz$rent, "RPPI Aluguel SP", "green"),
      cred_card,
      vso_card,
      inad_card
    )
  })

  output$pan_trend <- echarts4r::renderEcharts4r({
    cities <- c("São Paulo", "Rio De Janeiro", "Belo Horizonte")
    echart_trend_cities(fipezap()$sale, cities, window_start = pan_window())
  })

  output$pan_rate <- echarts4r::renderEcharts4r({
    echart_real_rate(selic_data(), ipca(), pan_window())
  })

  output$pan_credit <- echarts4r::renderEcharts4r({
    echart_volume_trend(
      dplyr::mutate(sbpe_units(), currency_total = currency_total / 1000),
      "currency_total",
      window_start = pan_window()
    )
  })

  # São Paulo (Secovi) ----

  sp_window <- shiny::reactive({
    yrs <- as.numeric(input$sp_period %||% "10")
    if (is.na(yrs) || yrs == 0) {
      return(NULL)
    }
    max(secovi_data()$date, na.rm = TRUE) %m-% lubridate::years(yrs)
  })

  output$sp_launch_sales <- echarts4r::renderEcharts4r({
    sec <- secovi_data()
    wide <- dplyr::full_join(
      dplyr::rename(
        roll_sum(secovi_pick(sec, "launches", "unidades")),
        Lançamentos = value
      ),
      dplyr::rename(
        roll_sum(secovi_pick(sec, "sales", "unidades")),
        Vendas = value
      ),
      by = "date"
    )
    echart_wide_lines(wide, c("Lançamentos", "Vendas"), "Unidades", sp_window())
  })

  sp_rooms <- shiny::reactive(names(SECOVI_ROOMS))

  output$sp_rooms_area <- echarts4r::renderEcharts4r({
    echart_stacked_area(
      secovi_rooms_units_12m(secovi_data()),
      sp_rooms(),
      "Unidades",
      sp_window()
    )
  })
  output$sp_rooms_vso <- echarts4r::renderEcharts4r({
    echart_wide_trends(
      secovi_rooms_wide(secovi_data(), "vso_vendas_sobre_oferta"),
      sp_rooms(),
      "VSO (%) · tendência",
      sp_window()
    )
  })
  output$sp_rooms_share <- echarts4r::renderEcharts4r({
    yearly <- secovi_rooms_yearly(secovi_data())
    # Honor the Período handle: the bar chart has no datazoom, so filter years.
    w <- sp_window()
    if (!is.null(w)) {
      yearly <- dplyr::filter(yearly, year >= lubridate::year(w))
    }
    echart_share_bars(rooms_to_shares(yearly), sp_rooms())
  })
  output$sp_rooms_table <- shiny::renderUI({
    secovi_rooms_table(secovi_rooms_yearly(secovi_data()))
  })

  trend_card_server(
    "sp_supply",
    shiny::reactive(secovi_pick(secovi_data(), "supply", "saldo_unidades")),
    "Unidades",
    "Estoque",
    sp_window
  )
  output$sp_vgv <- echarts4r::renderEcharts4r({
    sec <- secovi_data()
    wide <- dplyr::full_join(
      dplyr::rename(
        roll_sum(secovi_pick(sec, "launches", "vgv_potencial_em_r_milhoes")),
        Lançamentos = value
      ),
      dplyr::rename(
        roll_sum(secovi_pick(sec, "sales", "vgv_em_milhoes_de_r")),
        Vendas = value
      ),
      by = "date"
    )
    echart_wide_lines(
      wide,
      c("Lançamentos", "Vendas"),
      "R$ milhões",
      sp_window()
    )
  })

  # Crédito (Abecip / BCB) ----

  win_from <- function(period, ref, default = "10") {
    yrs <- as.numeric(period %||% default)
    if (is.na(yrs) || yrs == 0) {
      return(NULL)
    }
    max(ref, na.rm = TRUE) %m-% lubridate::years(yrs)
  }

  cred_win <- shiny::reactive(win_from(input$cred_period, sbpe_units()$date))

  trend_card_server(
    "cred_volume",
    shiny::reactive(dplyr::transmute(
      sbpe_units(),
      date,
      value = currency_total
    )),
    "R$ milhões",
    "Volume/mês",
    cred_win
  )
  trend_card_server(
    "cred_units",
    shiny::reactive(dplyr::transmute(sbpe_units(), date, value = units_total)),
    "Unidades",
    "Unidades/mês",
    cred_win
  )
  trend_card_server(
    "cred_rate",
    shiny::reactive(bcb_pick(bcb_data(), "taxa_fimob_pf_total")),
    "% a.a.",
    "Taxa",
    cred_win
  )
  trend_card_server(
    "cred_default",
    shiny::reactive(bcb_pick(bcb_data(), "atraso_fimob_pf_total")),
    "% atraso",
    "Atraso",
    cred_win
  )

  # Mercado (Abrainc) ----

  mkt_seg <- shiny::reactive(unname(ABRAINC_SEGMENTO[
    input$mkt_segmento %||% "Total"
  ]))
  mkt_win <- shiny::reactive(win_from(input$mkt_period, abrainc_data()$date))
  mkt_seg_label <- function(prefix) {
    shiny::reactive(paste0(prefix, " — ", input$mkt_segmento %||% "Total"))
  }
  mkt_pick <- function(category) {
    shiny::reactive(abrainc_pick(abrainc_data(), category, mkt_seg()))
  }

  trend_card_server(
    "mkt_launch",
    mkt_pick("new_units"),
    "Unidades",
    title = mkt_seg_label("Lançamentos"),
    window = mkt_win
  )
  trend_card_server(
    "mkt_sold",
    mkt_pick("sold"),
    "Unidades",
    title = mkt_seg_label("Vendas"),
    window = mkt_win
  )
  trend_card_server(
    "mkt_supply",
    mkt_pick("supply"),
    "Unidades",
    title = mkt_seg_label("Oferta"),
    window = mkt_win
  )
  trend_card_server(
    "mkt_distrato",
    mkt_pick("distratado"),
    "Unidades",
    title = mkt_seg_label("Distratos"),
    window = mkt_win
  )
  trend_card_server(
    "mkt_delivered",
    shiny::reactive(abrainc_pick(abrainc_data(), "delivered", "total")),
    "Unidades",
    window = mkt_win
  )
  output$mkt_vgv <- echarts4r::renderEcharts4r({
    ab <- abrainc_data()
    wide <- dplyr::full_join(
      dplyr::rename(
        abrainc_pick(ab, "value", "new_units"),
        Lançamentos = value
      ),
      dplyr::rename(abrainc_pick(ab, "value", "sale"), Vendas = value),
      by = "date"
    )
    echart_wide_lines(wide, c("Lançamentos", "Vendas"), "R$ milhões", mkt_win())
  })

  # Macro (BCB) ----

  macro_win <- shiny::reactive(win_from(
    input$macro_period,
    bcb_data()$date,
    "5"
  ))

  trend_card_server(
    "macro_selic",
    shiny::reactive(selic_data()),
    "% a.a.",
    "Selic Meta",
    macro_win
  )
  output$macro_infl <- echarts4r::renderEcharts4r({
    bcb <- bcb_data()
    infl <- function(name) {
      dplyr::transmute(bcb_pick(bcb, name), date, value = acum12m_pct(value))
    }
    wide <- dplyr::rename(infl("ipca"), IPCA = value) |>
      dplyr::full_join(
        dplyr::rename(infl("igpm"), `IGP-M` = value),
        by = "date"
      ) |>
      dplyr::full_join(dplyr::rename(infl("incc"), INCC = value), by = "date")
    echart_wide_lines(
      wide,
      c("IPCA", "IGP-M", "INCC"),
      "% 12m",
      macro_win(),
      zero_line = TRUE
    )
  })
  output$macro_real <- echarts4r::renderEcharts4r({
    echart_real_rate(selic_data(), ipca(), macro_win())
  })
  trend_card_server(
    "macro_fimob",
    shiny::reactive(bcb_pick(bcb_data(), "taxa_fimob_pf_total")),
    "% a.a.",
    "Taxa",
    macro_win
  )
  output$macro_debt <- echarts4r::renderEcharts4r({
    bcb <- bcb_data()
    wide <- dplyr::rename(
      bcb_pick(bcb, "comprometimento_renda_servico_total"),
      Comprometimento = value
    ) |>
      dplyr::full_join(
        dplyr::rename(
          bcb_pick(bcb, "endividamento_total"),
          Endividamento = value
        ),
        by = "date"
      )
    echart_wide_lines(
      wide,
      c("Comprometimento", "Endividamento"),
      "% da renda",
      macro_win()
    )
  })
  trend_card_server(
    "macro_default",
    shiny::reactive(bcb_pick(bcb_data(), "atraso_fimob_pf_total")),
    "% atraso",
    "Atraso",
    macro_win
  )
}

shinyApp(ui = ui, server = server)
