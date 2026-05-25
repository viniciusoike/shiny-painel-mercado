library(shiny)
library(bslib)
library(echarts4r)
library(dplyr)
library(here)

source(here::here("R", "utils.R"))
source(here::here("R", "_setup.R"))
source(here::here("R", "echarts_helpers.R"))

theme <- bslib::bs_theme(
  version    = 5,
  bg         = "#F5F5F5",
  fg         = "#333333",
  primary    = "#2A9D8F",
  secondary  = "#264653",
  success    = "#8AB17D",
  warning    = "#E9C46A",
  danger     = "#E76F51",
  base_font  = bslib::font_google("Inter"),
  heading_font = bslib::font_google("Inter")
) |>
  bslib::bs_add_rules(readLines(here::here("styles.css")))

ui <- bslib::page_navbar(
  title = "Painel do Mercado Imobiliário",
  theme = theme,
  bg    = "#2A9D8F",
  inverse = TRUE,

  bslib::nav_panel(
    title = "Panorama",
    bslib::layout_columns(
      col_widths = c(12),
      bslib::card(
        bslib::card_header("Em construção"),
        bslib::card_body(
          "A aba de Panorama trará indicadores agregados (IBGE, BCB, ",
          "estoque/lançamentos) em breve. Use a aba ", tags$b("Preços"),
          " para explorar os índices residenciais."
        )
      )
    )
  ),

  bslib::nav_panel(
    title = "Preços",
    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        title = "Opções",
        width = 280,
        shiny::selectInput(
          "city", "Cidade",
          choices = NULL
        ),
        shiny::radioButtons(
          "variable", "Variável",
          choices  = names(vlvar),
          selected = names(vlvar)[1]
        ),
        shiny::actionButton(
          "refresh", "Atualizar dados",
          icon = shiny::icon("rotate"),
          class = "btn-secondary"
        ),
        shiny::uiOutput("fetched_at")
      ),
      bslib::layout_columns(
        col_widths = c(12),
        bslib::card(
          bslib::card_header("Aluguel"),
          echarts4r::echarts4rOutput("plot_rent", height = "340px")
        ),
        bslib::card(
          bslib::card_header("Venda"),
          echarts4r::echarts4rOutput("plot_sale", height = "340px")
        )
      )
    )
  ),

  bslib::nav_spacer(),
  bslib::nav_item(
    tags$a(
      "Código",
      href = "https://github.com/viniciusoike/shiny-painel-mercado",
      target = "_blank"
    )
  )
)

server <- function(input, output, session) {

  rppi_data <- shiny::reactiveVal(load_rppi(force = FALSE))

  shiny::observeEvent(input$refresh, {
    shiny::withProgress(message = "Atualizando dados...", value = 0.5, {
      rppi_data(load_rppi(force = TRUE))
    })
    shiny::showNotification("Dados atualizados.", type = "message")
  })

  shiny::observe({
    df <- rppi_data()
    choices  <- city_choices(df)
    selected <- if ("São Paulo" %in% choices) "São Paulo" else choices[1]
    shiny::updateSelectInput(session, "city", choices = choices, selected = selected)
  })

  splits <- shiny::reactive({
    split_rppi(rppi_data())
  })

  output$fetched_at <- shiny::renderUI({
    ts <- attr(rppi_data(), "fetched_at")
    if (is.null(ts)) {
      label <- "—"
    } else {
      label <- format(ts, "%d/%m/%Y %H:%M")
    }
    shiny::tags$small(
      shiny::tags$em(paste("Última atualização:", label)),
      style = "color: #666;"
    )
  })

  output$plot_rent <- echarts4r::renderEcharts4r({
    shiny::req(input$city, input$variable)
    echart_series(splits()$rent, input$city, input$variable)
  })

  output$plot_sale <- echarts4r::renderEcharts4r({
    shiny::req(input$city, input$variable)
    echart_series(splits()$sale, input$city, input$variable)
  })
}

shinyApp(ui = ui, server = server)
