library(shiny)

# Define UI for application that draws a histogram
ui <- navbarPage(title = "Painel do Mercado Imobiliario",
                 theme = "styles.css",
  
  tabPanel("Panorama"),
  
  tabPanel("Preços",
    sidebarLayout(
      sidebarPanel(
        h4("Opções"),
        selectInput("city",
          "Cidade",
          c("Rio De Janeiro", "São Paulo"),
          selected = "São Paulo"),
        selectInput("variable", "Selecione a variável",
          choices = names(vlvar),
          selected = names(vlvar)[1])
      ),
      mainPanel(
        dygraphOutput("plot_rent"),
        dygraphOutput("plot_sale")
        )
      )
    )
)

# Define server logic required to draw a histogram
server <- function(input, output) {

  city <- reactive({input$city})
  variable <- reactive({input$variable})
  
  output$plot_rent <- renderDygraph({
    
    dyplot_series(rent_index, city(), variable())
    
  })
  
  output$plot_sale <- renderDygraph({
    
    dyplot_series(sale_index, city(), variable())
    
  })
  
  
  
}

# Run the application 
shinyApp(ui = ui, server = server)
