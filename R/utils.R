pal <- c("#264653", "#287271", "#2A9D8F", "#8AB17D", "#E9C46A", "#EFB366",
         "#F4A261", "#EE8959", "#E76F51")

get_color_palette <- function(n) {
  
  if (n == 1) {
    colors <- pal[1]
  }
  
  if (n == 2) {
    colors <- pal[c(1, 5)]
  }
  
  if (n == 3) {
    colors <- pal[c(1, 5, 9)]
  }
  
  if (n == 4) {
    colors <- pal[c(1, 3, 5, 9)]
  }
  
  if (n == 5) {
    colors <- pal[c(1, 3, 5, 7, 9)]
  }
  
  return(colors)
  
}


#' Convert data.frame to xts
#' 
#' This function converts a `data.frame` type object into a `xts`. It assumes the
#' `data.frame` is already in wide format, that there exists a single `Date` column,
#' and that all of the remaining columns are numeric time series.
#' 
#' This function also assumes for simplicity that the series are monthly.
#'
#' @param df A `data.frame` type object with a single `Date` column and numeric
#' columns containing a time series.
#' @param date_column String indicating the name of the date column. Defaults to
#' `'date'`.
#' @param .name_repair Logical indicating if column names be repaired with
#' `janitor::make_clean_names`. Defaults to FALSE.
#'
#' @return A `xts` with named columns
to_xts <- function(df, date_column = "date", .name_repair = FALSE) {
  
  stopifnot(date_column %in% names(df))
  
  df <- dplyr::arrange(df, .data[[date_column]])
  
  index <- seq(
    min(df[[date_column]], na.rm = TRUE),
    max(df[[date_column]], na.rm = TRUE),
    by = "month"
  )
  
  series <- xts::xts(
    x = dplyr::select(df, -dplyr::all_of(date_column)),
    order.by = index
  )
  
  if (isTRUE(.name_repair)) {
    names(series) <- janitor::make_clean_names(names(series))
  }
  
  return(series)
  
}