# Painel do Mercado Imobiliário

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Built with R](https://img.shields.io/badge/Built%20with-R-276DC3?logo=r&logoColor=white)](https://www.r-project.org/)
[![Shiny](https://img.shields.io/badge/Shiny-bslib-447099?logo=rstudio&logoColor=white)](https://shiny.posit.co/)

Interactive R Shiny dashboard for Brazilian residential real estate market indices — prices, credit, primary market, macro, and São Paulo housing indicators.

<img src="static/images/print_prices.png" alt="Dashboard screenshot" width="700">

## Features

- **Ekio sidebar shell** — six dashboard sections (Panorama, Preços, Crédito, Mercado, Macro, São Paulo) behind a branded sidebar
- **Índices de Preços (RPPI)** — monthly rent and sale price indices across Brazilian cities, sourced via [`realestatebr`](https://github.com/viniciusoike/realestatebr)
- **STL trend overlay** — decomposed trend component shown as a dashed line on the index chart
- **Disk cache** — data is cached locally on first load; the deployed app is read-only over a pre-warmed cache (refreshed by redeploy, see [Deployment](#deployment))
- **brand.yml theming** — Bootstrap 5 UI themed from `_brand.yml` (Ekio colors and typography)
## Running Locally

```r
# Dependencies are pinned with renv; restore them on first clone
renv::restore()

# Launch the app
shiny::runApp()
```

`renv::restore()` installs the exact versions in `renv.lock`. To set up manually instead:

```r
install.packages(c("shiny", "bslib", "brand.yml", "echarts4r", "dplyr",
                   "tidyr", "lubridate", "here", "jsonlite", "curl",
                   "realestatebr"))
```

Network access is required on first run to fetch market data. Subsequent runs use the local cache under `.cache/`.

## Deployment

The app is **read-only over a pre-warmed cache** — it never refetches at runtime, so it deploys cleanly to Posit Connect and stays stateless. To publish (or to update the data shown):

```r
Rscript tools/prewarm.R   # force-fetch every dataset into .cache/*.rds (fresh stamps)
Rscript tools/deploy.R    # rsconnect::deployApp() bundling the .cache/*.rds seed
```

`tools/deploy.R` lists `appFiles` explicitly, so the cache ships in the bundle and dev-only files (analysis scripts, etc.) are excluded. Fresh data reaches the live app only via a redeploy.

## Project Structure

```
├── app.R                   # Shiny entry point (UI + server)
├── renv.lock               # Pinned dependency versions (renv)
├── _brand.yml              # Ekio brand (colors, typography)
├── styles.css              # Dashboard CSS (sidebar, page chrome)
├── static/                 # Static assets (screenshots)
├── R/
│   ├── _setup.R            # Data loading, caching, STL decomposition
│   ├── echarts_helpers.R   # echarts4r chart wrappers
│   └── utils.R             # Color palette, kpi cards, formatting
├── tools/
│   ├── prewarm.R           # Force-fetch all data into cache
│   └── deploy.R            # Deploy to Posit Connect
└── analysis/               # Exploratory / WIP scripts (not loaded by app)
    ├── plot_secovi.R       # Secovi-SP ggplot2 charts
    └── prep_secovi.R       # Secovi-SP data preparation (draft)
```

## Data Sources

All data comes from [`realestatebr`](https://github.com/viniciusoike/realestatebr) via a small dataset registry in `R/_setup.R` (`load_dataset(name)`, cached per dataset under `.cache/`):

## Dashboard Sections

| Tab | Contents |
|---|---|
| **Panorama** | Executive summary — Selic × IPCA real rate, SBPE credit volume, FipeZap city trends, 8 KPI cards with sparklines |
| **Preços** | Nation and city-level price indices (IGMI-R, INCC, IPCA, IGP-M, IVAR, FipeZap), STL trend overlay, real vs. nominal, yearly accumulation |
| **Crédito** | SBPE credit volume and units, financing rate, delinquency (Abecip / BCB) |
| **Mercado** | Primary market launches, sales, supply, distratos, deliveries, VGV by segment (Abrainc) |
| **Macro** | Selic, IPCA, IGP-M, INCC, real interest rate, debt burden, delinquency (BCB) |
| **São Paulo** | Secovi-SP: launches vs. sales, VSO, supply, VGV, months of inventory, dormitório composition |
