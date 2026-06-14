# Painel do Mercado Imobiliário

Interactive R Shiny dashboard for Brazilian residential real estate market indices.

## Features

- **Ekio sidebar shell** — six dashboard sections (Panorama, Preços, Crédito, Mercado, Macro, São Paulo) behind a branded sidebar; design template in `mockup.html`
- **Índices de Preços (RPPI)** — monthly rent and sale price indices across Brazilian cities, sourced via [`realestatebr`](https://github.com/viniciusoike/realestatebr)
- **STL trend overlay** — decomposed trend component shown as a dashed line on the index chart
- **Disk cache** — RPPI data is cached locally on first load; use the "Atualizar dados" button to force a refresh
- **brand.yml theming** — Bootstrap 5 UI themed from `_brand.yml` (Ekio colors and typography)

## Running Locally

```r
# Dependencies are pinned with renv; restore them on first clone
renv::restore()

# Launch the app
shiny::runApp()
```

`renv::restore()` installs the exact versions in `renv.lock`, including
`realestatebr` from GitHub. To set up manually instead:

```r
install.packages(c("shiny", "bslib", "brand.yml", "echarts4r", "dplyr",
                   "tidyr", "lubridate", "here", "jsonlite", "curl"))
remotes::install_github("viniciusoike/realestatebr")
```

Network access is required on first run to fetch RPPI data. Subsequent runs use the local cache at `.cache/rppi.rds`.

## Project Structure

```
├── app.R                   # Shiny entry point (UI + server)
├── renv.lock               # Pinned dependency versions (renv)
├── _brand.yml              # Ekio brand (colors, typography)
├── styles.css              # Mockup-derived CSS (sidebar, page chrome)
├── mockup.html             # Static design template for the dashboard
├── mockup-brief.md         # Concept brief / design principles
├── R/
│   ├── _setup.R            # Data loading, caching, STL decomposition
│   ├── echarts_helpers.R   # echarts4r chart wrappers
│   └── utils.R             # Color palette utilities
└── analysis/               # Exploratory / WIP scripts (not loaded by app)
    ├── plot_secovi.R       # Secovi-SP ggplot2 charts
    └── prep_secovi.R       # Secovi-SP data preparation (draft)
```

## Data Sources

All data comes from [`realestatebr`](https://github.com/viniciusoike/realestatebr) via a small dataset registry in `R/_setup.R` (`load_dataset(name)`, cached per dataset under `.cache/`):

| Registry name | realestatebr call | Used by |
|---|---|---|
| `rppi` | `get_dataset("rppi", table = "all")` | Preços (all index sources stacked) |
| `abecip_sbpe`, `abecip_units` | `get_dataset("abecip", ...)` | Crédito (planned) |
| `abrainc` | `get_dataset("abrainc", table = "indicator")` | Mercado (planned) |
| `bcb_series` | `get_dataset("bcb_series", table = "core")` | Macro / Panorama (planned) |
| `secovi` | `get_dataset("secovi", table = "all")` | São Paulo (planned), Panorama VSO |
| `bcb_selic` | BCB SGS API (`fetch_bcb_sgs(432)`) | Panorama (Selic — not in `realestatebr`) |

## Roadmap

- [x] Ekio sidebar shell with six sections (mockup.html)
- [x] Preços tab: index + variation pairs, city comparison, summary table, real vs. nominal (IPCA)
- [x] Panorama tab: 8 KPI cards with sparklines + trend / real-rate / SBPE-volume charts
- [x] Crédito tab (Abecip / BCB): volume, units, rate, delinquency
- [x] Mercado tab (Abrainc): launches/sales/supply/distratos/deliveries/VGV by segment
- [x] Macro tab (BCB): Selic, inflation, real rate, financing rate, debt burden, delinquency
- [x] São Paulo tab (Secovi-SP): launches vs. sales, VSO, supply, VGV, condo defaults by typology
- [x] Polish: `trend_card` Shiny module to DRY the dense-tab charts
- [x] `renv` lockfile for reproducible deployment
