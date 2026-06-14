# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Overview

Brazilian real estate market dashboard built with R Shiny — "Painel do Mercado Imobiliário". It compiles economic and real estate indicators (price indices, credit, primary market, macro) into a single place, built as both a daily working tool and an Ekio portfolio piece.

The target design lives in `mockup.html` (static HTML, open in a browser) and `mockup-brief.md` (concept brief). All six sections plus the Sobre page are built and data-backed: Panorama (executive summary), Preços, Crédito, Mercado, Macro and São Paulo (Bloomberg-dense chart grids).

## Running the App

```r
# From R console, in the project root
shiny::runApp()
```

First run requires network access to fetch RPPI data; subsequent runs read the disk cache at `.cache/rppi.rds`. There is no build step, linter, or test suite. Deployed via RStudio Connect (`rsconnect/` is gitignored).

Dependencies are pinned with **renv** (`renv.lock`); `.Rprofile` auto-activates the project library. On a fresh clone run `renv::restore()` to install the recorded versions. `realestatebr` is recorded from GitHub (`viniciusoike/realestatebr`), and `brand.yml` — used implicitly by `bs_theme(brand = TRUE)` — is referenced via a `requireNamespace()` guard at the top of `app.R` so renv tracks it. After adding a package, run `renv::snapshot()`.

## Architecture

### Entry Point and Data Flow

`app.R` is the single entry point. It sources, in order: `R/utils.R`, `R/_setup.R`, `R/echarts_helpers.R`. The theme is `bs_theme(version = 5, brand = TRUE)` — Ekio colors and typography come from `_brand.yml` (requires the `brand.yml` package) — plus `styles.css` rules ported from the mockup.

### UI Shell

`bslib::page_sidebar(fillable = FALSE)` with a dark branded `sidebar(class = "ekio-sidebar")` containing custom nav links (`ekio_nav_item()`); the main area is a `navset_hidden(id = "main_nav")` with one `nav_panel_hidden()` per section. The nav links carry `role="link"` / `tabindex="0"` / `aria-current` and are activated by mouse click or Enter/Space (the `nav_js` snippet handles both, toggling `.active` + `aria-current` and setting `input$sidebar_nav`); the server calls `nav_select("main_nav", ...)`. Each page is a `tagList` starting with `page_header(title, subtitle)`. The sidebar footer shows the data `fetched_at` timestamp and holds the global "Atualizar dados" refresh button (`input$refresh`) — it lives here, not per-tab, so it is reachable from every section.

Dense pages follow the mockup pattern: a `.filter-bar` div of `filter_group()` inputs (the Métrica radio is styled into chips by `styles.css`), then 2-column `layout_columns()` rows of `chart_card()` (card with `.chart-card-header` title + `.chart-tag` badge + an echarts output). Preços implements this fully: index pair with STL overlay, metric pair (driven by the chip radio), 5-city comparison (`selectizeInput`, FipeZap sale), last-month summary table (`city_summary_table()` → `.mini-table`), and IPCA-deflated real vs. nominal. Card titles that mention the selected city are `textOutput(..., inline = TRUE)` in the header. The Período select maps to an initial datazoom window (`window_start` reactive).

Panorama is executive-summary style: an 8-card `.kpi-grid` (rendered server-side by `output$kpi_grid`, each card via `kpi_card()` with value, pp/`%` delta, and a CSS-bar sparkline) over three charts (RPPI trend by city, Selic×IPCA real rate, SBPE credit volume). KPI sources: Selic (`bcb_selic`), IPCA/IGP-M 12m (`bcb_series`), RPPI venda/aluguel SP (FipeZap `acum12m`), SBPE credit (`abecip_units$currency_total`, R$ million → R$ bi), VSO (`secovi` name `vso_vendas_sobre_oferta`/var `sales`), inadimplência (`bcb_series` `inad_credito_direcionado_pf`).

The four other dense tabs each have a `.filter-bar` (period select, plus a chip filter where one applies) over 2-column `chart_card()` rows. Single-series cards (the bulk) use the **`trend_card_ui()` / `trend_card_server()` Shiny module**, which wraps a `chart_card` + `echart_trend_single()` (faint monthly line + bold STL trend); pass `title = NULL` in the UI for a reactive title the server fills via a `title` reactive, or a string for a static one. The module's `data`/`window`/`title` reactives are built in the main server (so they can read `input$…`) and passed in. Tabs: **São Paulo** (`secovi`, Tipologia chips `SECOVI_TIPOLOGIA`, 6 charts), **Crédito** (`abecip_units` + `bcb_series` rate/atraso, 4 charts), **Mercado** (`abrainc`, Segmento chips `ABRAINC_SEGMENTO` → total/social_housing/market_rate, 6 charts), **Macro** (`bcb_series` + `bcb_selic`, 6 charts). Multi-line/special cards (VGV, inflation 12m, real-rate, launch-vs-sales) stay as plain `renderEcharts4r` outputs using `echart_wide_lines()` / `echart_real_rate()`. Extraction helpers: `secovi_pick()`, `bcb_pick()`, `abrainc_pick()`. `win_from(period, ref, default)` maps a period select to a datazoom window.

**`R/_setup.R`** — data layer:
- `DATASETS` — registry mapping app-level dataset names to a realestatebr `(dataset, table)` pair plus a prep function. Registered: `rppi` (table `"all"` — the stacked multi-source table; only the default FipeZAP table lives in the GitHub cache, so it falls back to a fresh download), `abecip_sbpe`, `abecip_units`, `abrainc` (indicator), `bcb_series` (core), `secovi` (all), and `bcb_selic` (a custom `fetch`, not a realestatebr table — Selic isn't in the package).
- `load_dataset(name, force = FALSE)` — fetch → prep → stamp `fetched_at` attribute → cache to `.cache/<name>.rds`. A registry entry may carry a `fetch` function that overrides the realestatebr path. `force = TRUE` (the "Atualizar dados" button) bypasses the cache. An empty fetch is never persisted: it falls back to a prior cache if one exists, otherwise warns and returns the empty frame uncached so the next load retries (prevents a first-run network failure from permanently caching emptiness). `load_rppi()` is a thin wrapper kept for the app.
- `fetch_bcb_sgs(code)` — pulls a BCB SGS daily series straight from the BCB API (needs a browser-like User-Agent or it 406s; daily series are capped at ~10 years per request) and resamples to monthly. Wrapped so failures yield an empty frame.
- `make_prep(name, required)` — generic prep that just validates required columns; replace with a real transform when a tab gets built.
- `prep_rppi()` renames `transaction_type` → `category` (realestatebr schema change), validates, and applies `add_stl_trend()` per source/city/category panel.
- `stl_trend_vec(v, dates)` / `add_stl_trend()` — STL trend on a monthly series, computed on the leading/trailing-trimmed segment (stl() can't take NAs); returns NA for series under 36 obs or with interior gaps. `add_stl_trend()` also adds the 12-month `trend_yoy`.
- `vlvar` — named vector mapping Portuguese variable labels to columns (`acum12m`, `chg`, `index`, `trend_yoy`).
- `split_rppi()` splits long data into `$rent` / `$sale`; `city_choices()` orders cities with Brazil/São Paulo/Rio first (note: the data spells it "Rio De Janeiro", capital D). `MAIN_CITIES` lists the capitals used by the comparison chart and summary table.

**`R/echarts_helpers.R`** — chart builders sharing `echart_finish()` (tooltip, legend, time axis, optional zero markline, datazoom honoring `window_start`) and `add_lines()`. `PCT_VARS` (`chg`, `acum12m`) are stored as fractions and scaled ×100 for display; `trend_yoy` is already in %. Preços: `echart_series()` (one line per source, dashed STL overlay for `index`), `echart_compare()` (one line per city), `echart_real_nominal()` (nominal vs. IPCA-deflated, rebased to 100). Panorama: `echart_trend_cities()`, `echart_real_rate()` (Selic, IPCA 12m, real rate), `echart_volume_trend()` (monthly bars + STL line). Dense tabs: `echart_trend_single()` (faint monthly + bold STL trend; the default for single series), `echart_wide_lines()` (several named series from a wide df).

**`R/utils.R`** — palette: `pal`, `get_color_palette(n)`. Formatting: `fmt_pct_br()` (fraction → "+7,2%"), `fmt_num_br()`, `acum12m_pct()` (monthly % → trailing-12m %). Panorama KPIs: `kpi_card()` + `kpi_sparkline()` (CSS-bar sparkline normalized from a series). Preços: `city_summary_table()` (last-month `.mini-table` HTML).

**`analysis/`** — exploratory scripts not loaded by the app: `plot_secovi.R` (ggplot2 charts off the gitignored `data/secovi-sp.csv`) and `prep_secovi.R` (draft data prep).

### Server Pattern

All six datasets are loaded once at app startup into a global `initial_data` list (shared across sessions, not re-read per session); each session's `reactiveVal`s (`rppi_data`, `bcb_data`, …) are seeded from it. The sidebar refresh button replaces them with forced fetches inside `withProgress`. City choices update via `observe` + `updateSelectInput`, preserving the current `input$city` / `input$cmp_cities` across a refresh when those values still exist in the new data. Charts `req()` their inputs before rendering.

## Data Sources

Most app data comes from the [`realestatebr`](https://github.com/viniciusoike/realestatebr) package via `get_dataset(name)`. Available datasets (see `list_datasets()`): `rppi`, `rppi_bis`, `abecip` (housing credit), `abrainc` (primary market), `bcb_realestate`, `bcb_series` (macro: IPCA, IGP-M, INCC… — note Selic is *not* here), `fgv_ibre`, `secovi` (São Paulo). The one exception is the Selic meta rate, fetched directly from the BCB SGS API (`fetch_bcb_sgs(432)`).

## Design Direction (mockup)

Six sections via a left sidebar: **Panorama** (executive summary: 8 KPI cards with sparklines + 2–3 large trend charts), **Preços**, **Crédito**, **Mercado**, **São Paulo**, **Macro** (all Bloomberg-dense 2-column chart grids). Key principles from `mockup-brief.md`:

- Never show raw data — every series gets trend extraction (STL), deseasonalization, or aggregation
- Ekio branding: blue `#1E3A5F` primary, orange `#DD6B20` accent, teal `#2C7A7B` secondary — defined in `_brand.yml` and as CSS variables in `styles.css`
- Build broadly first; iterate and cut back later — comprehensiveness over UI polish

## Conventions

- 2-space indentation, UTF-8 encoding (set in `.Rproj`)
- Portuguese UI labels; English internal column names and identifiers
- RStudio-style section headers in R code (`# Section ----`), never box-style comment banners
- `data/` and `.cache/` are gitignored — local data comes from `realestatebr` or manual download
- Chart colors always go through `get_color_palette()` / `pal` (or `echart_palette()` for >5 series)
- `CLAUDE.md` is the canonical version of this file — keep the two in sync when updating
