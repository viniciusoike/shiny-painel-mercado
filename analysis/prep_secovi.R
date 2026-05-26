# library(dplyr)
# library(readr)
# library(tidyr)
# library(stringr)
# library(here)
# library(RcppRoll)
# library(benviplot)
# 
# secovi <- readr::read_csv(here::here("data/secovi-sp.csv"))
# 
# caption_label <- function(data, source = NULL) {
#   date_max <- max(data$ts_date)
#   
#   s <- str_glue("Most recent observation in {year_max}: {month_max} ({month_num_max})",
#                 year_max = lubridate::year(date_max),
#                 month_max = lubridate::month(date_max, label = TRUE, abbr = TRUE),
#                 month_num_max = lubridate::month(date_max))
#   
#   if (!is.null(source)) {
#     paste0("Source: ", source, ". ", s)
#   }
#   
# }
# 
# sec <- secovi |> 
#   filter(ts_year >= 2017) |> 
#   mutate(variable_label = str_to_title(variable))
# 
# # dfyear <- sec |> 
# #   filter(variable %in% c("launches", "sales"), name == "unidades") |> 
# #   group_by(ts_year, variable_label) |> 
# #   summarise(total_year = sum(value, na.rm = TRUE))
# 
# dfacum <- secovi |> 
#   filter(ts_year >= 2016, variable %in% c("launches", "sales"), name == "unidades") |> 
#   group_by(variable) |> 
#   mutate(acum12m = roll_sumr(value, n = 12)) |> 
#   ungroup() |>
#   filter(ts_year >= 2017) |> 
#   mutate(variable_label = str_to_title(variable))
# 
# dfsalesupply <- sec |> 
#   filter(variable %in% c("supply", "sales"),
#          name %in% c("saldo_unidades", "unidades"))
# 
# dfvso <- sec |> 
#   filter(variable == "sales", name == "vso_vendas_sobre_oferta")
# 
# plot_secovi_1 <- function(data) {
#   
#   df <- data |> 
#     filter(variable %in% c("launches", "sales"), name == "unidades")
#   
#   dfyear <- df |> 
#     group_by(ts_year, variable_label) |> 
#     summarise(total_year = sum(value, na.rm = TRUE))
#   
#   plot_column(data = dfyear, x = ts_year, y = total_year, variable = variable_label,
#               position.col = position_dodge(0.9), text = TRUE, position.text = "dodge") +
#     scale_x_continuous(breaks = 2010:2022) +
#     scale_y_continuous(labels = scales::label_number(big.mark = ".", decimal.mark = ",")) +
#     ggtitle(label = "New Launches and Sales") +
#     ylab(label = "Units") +
#     labs(caption = caption_label(df, source = "Secovi/SP")) +
#     theme(legend.key.width = unit(0.75, "cm"),
#           legend.key.height = unit(0.15, "cm"))
#   
# }
# 
# plot_secovi_line <- function(data, metric) {
#   
#   df <- data |> 
#     select(ts_date, variable_label, where(is.numeric)) |> 
#     pivot_longer(cols = -c(ts_date, variable_label)) |> 
#     filter(name == metric)
#   
#   plot_line(df, x = ts_date, y = value, variable = variable_label, zero = TRUE) +
#     scale_x_date(date_breaks = "6 months", date_labels = "%Y-%m") +
#     scale_y_continuous(labels = scales::label_number(big.mark = ".", decimal.mark = ",")) +
#     labs(caption = caption_label(df, source = "Secovi"))
#   
# }