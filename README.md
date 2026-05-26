# Painel do Mercado Imobiliário

Interactive R Shiny dashboard for Brazilian residential real estate market indices.

## Features

- **Índices de Preços (RPPI)** — monthly rent and sale price indices across Brazilian cities, sourced via [`realestatebr`](https://github.com/viniciusoike/realestatebr)
- **STL trend overlay** — decomposed trend component shown as a dashed line on the index chart
- **Disk cache** — RPPI data is cached locally on first load; use the "Atualizar dados" button to force a refresh
- **bslib theming** — Bootstrap 5 UI with Google Inter font and an earthy color palette

## Running Locally

```r
# Install dependencies (first time)
install.packages(c("shiny", "bslib", "echarts4r", "dplyr", "tidyr",
                   "lubridate", "here", "realestatebr"))

# Launch the app
shiny::runApp()
```

Network access is required on first run to fetch RPPI data. Subsequent runs use the local cache at `.cache/rppi.rds`.

## Project Structure

```
├── app.R                   # Shiny entry point (UI + server)
├── styles.css              # Bootstrap CSS overrides
├── R/
│   ├── _setup.R            # Data loading, caching, STL decomposition
│   ├── echarts_helpers.R   # echarts4r chart wrappers
│   └── utils.R             # Color palette utilities
└── analysis/               # Exploratory / WIP scripts (not loaded by app)
    ├── plot_secovi.R        # Secovi-SP ggplot2 charts
    └── prep_secovi.R       # Secovi-SP data preparation (draft)
```

## Data Sources

| Dataset | Source | Notes |
|---|---|---|
| RPPI (rent & sale) | `realestatebr::get_dataset("rppi")` | Fetched from GitHub releases |
| Secovi-SP | `data/secovi-sp.csv` (gitignored) | Manual download required |

## Roadmap

- [ ] Secovi-SP tab (lançamentos, vendas, VSO)
- [ ] Panorama tab with aggregate macro indicators (IBGE, BCB)
- [ ] Multi-city comparison in price charts
