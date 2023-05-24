dyplot_series <- function(df, city = NULL, variable = NULL, name_series = NULL) {
  
  if (missing(df)) {
    stop("A data.frame object must be supplied")
  }
  
  if (is.null(city)) {
    warning("No city has been selected. Choosing Brazil.")
    city <- "Brazil"
  }
  
  if (is.null(variable)) {
    warning("No variable has been selected. Choosing YoY change.")
    variable <- "Acumulado 12 Meses (%)"
  }
  
  if (length(city) > 5) {
    stop("Object city cannot have more than 5 elements.")
  }
  
  vlvar <- c(
    "Acumulado 12 Meses (%)" = "acum12m",
    "Variação Mensal (%)" = "chg",
    "Índice" = "index"
    )
  
  stopifnot(variable %in% names(vlvar))
  
  sel_var <- unname(vlvar[variable])
  
  # For a single city selection
  if (length(city) == 1) {
    
    df <- df %>%
      dplyr::filter(name_muni == city, !is.na(.data[[sel_var]])) %>%
      tidyr::pivot_wider(
        id_cols = "date",
        names_from = "source",
        values_from = dplyr::all_of(sel_var)
      )
    
    # Convert to xts
    series <- to_xts(df)
    
    current_date <- lubridate::floor_date(Sys.Date(), unit = "month")
    initial_date <- current_date - years(2)
    # Get the number of series
    nseries <- ncol(series)
    # Get a vector of colors from the palette
    color_series <- get_color_palette(nseries)
    
    if (is.null(name_series)) {
      name_series <- names(series)
    }
    
    # return(name_series)
    
    plot <- dygraph(series) %>%
      dyGroup(name_series, color = color_series, strokeWidth = 2) %>%
      dyLimit(0, color = "black", strokePattern = "solid") %>%
      dyAxis("y") %>%
      dyRangeSelector(dateWindow = c(initial_date, current_date))
    
    
  } else {
    
  }
  
  return(plot)
  
  
}