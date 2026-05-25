# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Brazilian real estate market dashboard built with R Shiny — "Painel do Mercado Imobiliário". It visualizes real property price indices (RPPI) for rent and sale across Brazilian cities, with an in-progress Secovi-SP panel.

## Running the App

```r
# From R console, in the project root
shiny::runApp()

# Or source the main file
source("app.R")
```

There is no build step, linter, or test suite configured. The app is deployed via RStudio Connect (the `rsconnect/` directory is gitignored).

## Architecture

### Entry Point and Data Flow

`app.R` is the single Shiny entry point, but it depends on objects that must be sourced before the app runs. The `R/_setup.R` file loads all required data:

- Calls `realestatebr::get_rppi()` to fetch live RPPI data from the web (no local cache — network required at startup)
- Produces `rent_index` and `sale_index` — long-format data frames used throughout the app
- Defines `vlvar`, a named character vector mapping Portuguese display labels to column names (`acum12m`, `chg`, `index`)

`app.R` references `vlvar`, `rent_index`, `sale_index`, and `dyplot_series()` without explicit `source()` calls — these are expected to be available in the global environment (sourced by the RStudio session or a global.R pattern).

### Key Functions

**`R/dyplot_series.R`** — Core interactive chart function. Takes a long-format data frame (`rent_index` or `sale_index`), filters by `name_muni` (city) and the selected variable column, pivots wide by `source`, converts to `xts`, then renders a `dygraph` with a 2-year default range selector. Currently only handles `length(city) == 1`; the multi-city branch is an empty `else {}`.

**`R/utils.R`** — Two utilities:
- `pal` — 9-color earthy palette used consistently across all plots
- `get_color_palette(n)` — returns `n` spread-apart colors from `pal` (supports 1–5 series)
- `to_xts(df, date_column, .name_repair)` — converts a wide data frame with a `Date` column to a monthly `xts` object; required by `dyplot_series`

**`R/plot_secovi.R`** — Standalone exploratory script (not sourced by the app). Reads `data/secovi-sp.csv` (gitignored) and produces ggplot2 charts for launches, sales, VSO (vendas sobre oferta), and condominium default rates.

**`R/prep_secovi.R`** — Entirely commented out. In-progress data preparation for Secovi integration.

### UI Structure

The app uses `navbarPage` with two tabs:
- **Panorama** — empty placeholder
- **Preços** — sidebar with city (`Rio De Janeiro`, `São Paulo`) and variable selectors; main panel renders two `dygraphOutput` charts (rent and sale indices)

`styles.css` applies Bootstrap overrides: green navbar (`#4CAF50`), light grey body (`#F5F5F5`), orange accent (`#FF5722`).

## Key Packages

| Package | Role |
|---|---|
| `shiny` | App framework |
| `dygraphs` | Interactive time series charts |
| `realestatebr` | Source of RPPI data (`get_rppi()`) |
| `xts` | Time series format required by dygraphs |
| `dplyr` / `tidyr` | Data wrangling |
| `lubridate` | Date arithmetic in plot windowing |
| `ggplot2` / `tidyverse` | Static charts in Secovi scripts only |
| `here` | Path resolution in Secovi scripts |

## Conventions

- 2-space indentation, UTF-8 encoding (set in `.Rproj`)
- Portuguese UI labels throughout; internal column names and variable identifiers are in English
- The `data/` directory is gitignored — all local data files must be obtained externally or via `realestatebr`
- Color usage always goes through `get_color_palette()` or directly references `pal` from `R/utils.R`
