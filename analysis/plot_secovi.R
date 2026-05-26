library(tidyverse)
library(here)

current_date <- Sys.Date()
current_year <- lubridate::year(current_date)



secovi <- read_csv(here("data/secovi-sp.csv"))

sub_launches <- secovi |> 
  filter(variable %in% c("launches", "sales"), name == "unidades") |> 
  select(ts_date, ts_year, variable, value, stl_decomp)

series_launches <- filter(sub_launches, variable == "launches")
series_sales <- filter(sub_launches, variable == "sales")

ggplot(series_launches, aes(x = ts_date)) +
  geom_line(aes(y = value), alpha = 0.8, color = pal[2]) +
  geom_line(aes(y = stl_decomp), color = pal[2], size = 1) +
  theme_minimal()

ggplot(series_sales, aes(x = ts_date)) +
  geom_line(aes(y = value), alpha = 0.8, color = pal[2]) +
  geom_line(aes(y = stl_decomp), color = pal[2], size = 1) +
  theme_minimal()

tab_year_sl <- secovi |> 
  filter(
    variable %in% c("launches", "sales"),
    name == "unidades",
    ts_year >= current_year - 5) |> 
  group_by(ts_year, variable) |> 
  summarise(total = sum(value, na.rm = TRUE))

ggplot(tab_year_sl, aes(x = ts_year, y = total, fill = variable)) +
  geom_col(position = position_dodge(width = 0.9)) +
  geom_text(
    aes(y = total + 5000, label = format(total, big.mark = ".")),
    position = position_dodge(width = 0.9),
    size = 3
  ) +
  geom_hline(yintercept = 0) +
  scale_fill_manual(
    name = "",
    values = c(pal[c(1, 3)]),
    labels = c("Lancamentos", "Vendas")) +
  scale_x_continuous(
    breaks = seq(min(tab_year_sl$ts_year), max(tab_year_sl$ts_year), 1)
    ) +
  scale_y_continuous(labels = scales::label_number(big.mark = ".")) +
  theme_minimal() +
  labs(
    title = "",
    subtitle = "",
    x = NULL,
    y = "Unidades",
    caption = "Fonte: Secovi-SP."
  ) +
  theme(
    legend.position = "top",
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_blank()
  )


secovi |> 
  filter(ts_year >= 2018, variable == "sales", name == "vso_vendas_sobre_oferta") |> 
  ggplot(aes(x = ts_date)) +
  geom_line(aes(y = value), alpha = 0.8, color = pal[2]) +
  geom_line(aes(y = stl_decomp), color = pal[2], size = 1) +
  theme_minimal()

secovi |> 
  filter(ts_year >= 2018, variable == "default_condominio") |> 
  ggplot(aes(x = ts_date, y = value)) +
  geom_line() +
  geom_point()














