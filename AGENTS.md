# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Overview

Brazilian real estate market dashboard built with R Shiny — "Painel do Mercado Imobiliário". It compiles economic and real estate indicators (price indices, credit, primary market, macro) into a single place, built as both a daily working tool and an Ekio portfolio piece.

The target design lives in `mockup.html` (static HTML, open in a browser) and `mockup-brief.md` (concept brief). All seven sections plus the Sobre page are built and data-backed: Panorama (executive summary), Preços, Crédito, Mercado, Atividade, Macro and São Paulo (Bloomberg-dense chart grids). Atividade goes beyond the mockup — it carries the employment, income and production series.

## Running the App

```r
# From R console, in the project root
shiny::runApp()
```

First run requires network access to fetch RPPI data; subsequent runs read the disk cache at `.cache/rppi.rds`. There is no build step, linter, or test suite.

**Deployment (Posit Connect Cloud).** The app is read-only over a pre-warmed cache — it never refetches at runtime, so it stays stateless. It's deployed via **Posit Connect Cloud linked directly to this GitHub repo**: Connect Cloud clones the repo at its current commit and deploys that, with no build step and no bundle upload — it never sees `tools/deploy.R`. So the pre-warmed data must be **committed to git**: `load_dataset()` in `R/pipeline/loader.R` reads `.cache/<name>.rds` (gitignored, local-only) first, then falls back to `data-cache/<name>.rds` — a git-tracked sibling directory that ships with every push. To publish fresh data: `Rscript tools/prewarm.R` (force-fetches every dataset into `.cache/*.rds` with a fresh `fetched_at`, confirms every line says `ok`, then copies the results into `data-cache/`), then `git add data-cache && git commit && git push` — the push both ships the new data and triggers Connect Cloud's own git-linked auto-redeploy. `.github/workflows/refresh-data.yml` runs this on a weekly schedule (plus manual `workflow_dispatch`) so nobody has to remember to do it by hand. That job installs current P3M binaries with `r-lib/actions/setup-r-dependencies` (pak) instead of restoring `renv.lock`, and sets `RENV_CONFIG_AUTOLOADER_ENABLED: false` so `.Rprofile` does not point `.libPaths()` at an empty `renv/library`. Restoring the lockfile there source-builds every package pinned behind P3M's current release, which needs system libraries the runner lacks. The job only writes `.rds` data files, so it does not need the app's pinned versions; keep its `packages:` list in step with the `library()` calls in `R/_setup.R`.

Deploying to a traditional (non-Cloud) Posit Connect server instead? `Rscript tools/deploy.R` still works — it calls `rsconnect::deployApp()` with an explicit `appFiles` list that bundles the `.cache/*.rds` seed and omits dev-only files. `rsconnect/` is gitignored.

Dependencies are pinned with **renv** (`renv.lock`); `.Rprofile` auto-activates the project library. On a fresh clone run `renv::restore()` to install the recorded versions. `realestatebr` is on CRAN, recorded as a normal Repository package (it was previously GitHub-sourced). `brand.yml` — used implicitly by `bs_theme(brand = TRUE)` — is referenced via a `requireNamespace()` guard at the top of `app.R` so renv tracks it. `trendseries` supplies trend and rolling transformations and calls `seasonal` for SEATS adjustment; these transformations run during preparation, while the deployed app reads prepared series from the cache. After adding a package, run `renv::snapshot()`.

## Architecture

### Entry Point and Data Flow

`app.R` is the single entry point. It sources, in order: `R/utils.R`, `R/_setup.R`, `R/echarts_helpers.R`. The theme is `bs_theme(version = 5, brand = TRUE)` — Ekio colors and typography come from `_brand.yml` (requires the `brand.yml` package) — plus `styles.css` rules ported from the mockup.

### UI Shell

`bslib::page_sidebar(fillable = FALSE)` with a dark branded `sidebar(class = "ekio-sidebar")` containing custom nav links (`ekio_nav_item()`); the main area is a `navset_hidden(id = "main_nav")` with one `nav_panel_hidden()` per section. The nav links carry `role="link"` / `tabindex="0"` / `aria-current` and are activated by mouse click or Enter/Space (the `nav_js` snippet handles both, toggling `.active` + `aria-current` and setting `input$sidebar_nav`); the server calls `nav_select("main_nav", ...)`. Each page is a `tagList` starting with `page_header(title, subtitle)`. The sidebar footer shows when the data was last refreshed (the `fetched_at` stamp, via `output$sidebar_updated`); there is no in-app refresh button — the app is read-only over a pre-warmed cache (see Deployment).

Dense pages follow the mockup pattern: a `.filter-bar` div of `filter_group()` inputs (the Métrica radio is styled into chips by `styles.css`), then 2-column `layout_columns()` rows of `chart_card()` (card with `.chart-card-header` title + `.chart-tag` badge + an echarts output). The whole Preços page is national (Brasil) — there is no city selector; the filter-bar is just the Métrica chip (`acum12m`/`chg`) + Período. Preços implements this fully: a 7-card national `.kpi-grid` at the top (`output$precos_kpi_grid` — IGMI-R, INCC, IPCA, IGP-M, IVAR, FipeZap venda/aluguel, each the latest 12m accumulated variation for Brasil), then a fixed-Brasil 12m pair (`plot_precos_infl` = IGMI-R vs. INCC vs. IPCA; `plot_precos_venda_aluguel` = IGMI-R venda vs. national IVAR aluguel — both `echart_wide_lines`); the metric pair (driven by the chip radio — Venda = FipeZap + IGMI-R + national IVG-R via `sale_with_ivgr(., "Brazil")`; Aluguel = FipeZap + national IVAR via `rent_with_ivar(., "Brazil")` — both relabel the national-only source's rows to "Brazil" so `echart_series` picks them up); a yearly-accumulated row (`echart_yearly_bars` dodged bars INCC/IPCA/IGMI-R/IVAR for years ≥ 2022, beside a scrollable `yearly_accum_table()` `.mini-table` of 2010..latest, most-recent-first — both fed by `yearly_accum_data()`, which compounds monthly inflation within the calendar year and takes Dec/Dec-1 for the price-index levels); and a 5-city comparison (`selectizeInput`, FipeZap sale) beside the last-month summary table (`city_summary_table()` → `.mini-table`). The metric-pair titles are `textOutput(..., inline = TRUE)` in the header (filled with the selected metric). The Período select maps to an initial datazoom window (`window_start` reactive).

Panorama is an executive-summary page containing only an 8-card `.kpi-grid`, rendered server-side by `output$kpi_grid`. Each card uses `kpi_card()` with a value, pp/`%` delta, and CSS-bar sparkline. KPI sources are Selic, IPCA/IGP-M 12m, RPPI venda/aluguel SP, real SBPE credit volume, VSO SP, and inadimplência PF.

The five other dense tabs each have a `.filter-bar` over 2-column `chart_card()` rows. Single-series cards use the **`trend_card_ui()` / `trend_card_server()` Shiny module**, which passes prepared `value` and `trend` columns to `echart_trend_single()`. Crédito contains volume and units financed plus the financing rate, household debt conditions, and delinquency. Macro contains inflation over 12 months and the Selic/IPCA real-rate comparison. Mercado and São Paulo use prepared rolling and constant-price columns for VGV and credit values. Atividade uses prepared seasonally adjusted, YoY, and trend columns. `win_from(period, ref, default)` maps period inputs to datazoom windows.

**Data pipeline:**
- `R/_setup.R` is only the composition root: it attaches packages and sources pipeline modules in dependency order, followed by dashboard data helpers.
- `R/pipeline/registries.R` contains `SOURCE_REGISTRY` plus the RPPI, BCB, ABECIP, ABRAINC, Secovi, and BCB activity series registries. Registries hold upstream identifiers and processing policy such as frequency, kind, scale, seasonal treatment, and deflator.
- Dataset adapters live in `R/pipeline/rppi.R`, `bcb.R`, `abecip.R`, `abrainc.R`, and `secovi.R`. They validate the upstream schema, return sorted tibbles, normalize dates, and attach registry metadata. BCB preserves its upstream `value` and adds `value_std`, where rates expressed in percentage points are converted to fractions.
- `R/pipeline/time-series.R` owns interpolation with `zoo`, SEATS seasonal adjustment through `trendseries`/`seasonal`, STL and HP trends, HP cycles, and standard rate/level features. `R/pipeline/inflation.R` builds price indices and deflates nominal values using an already-loaded inflation tibble.
- `R/pipeline/loader.R` implements `load_dataset(name, force = FALSE)`: fetch → prepare → stamp `fetched_at` and `pipeline_version` → cache. It upgrades older caches in memory and preserves the last good cache for incremental SGS fetches and transient upstream failures.
- `R/dashboard/data-helpers.R` contains dashboard-only selection and reshaping helpers (`activity_pick()`, `split_rppi()`, `yearly_accum_data()`, Secovi room views, `bcb_pick()`, and `abrainc_pick()`). These are not ingestion or canonical preparation functions.
- `fetch_bcb_sgs()` in `R/pipeline/bcb.R` is the thin `GetBCBData` adapter. `SGS_ATIVIDADE` drives incremental activity fetching; source-adjusted series pass through and the remainder use SEATS before STL trend extraction.

**`R/echarts_helpers.R`** — chart builders sharing `echart_finish()` (tooltip, legend, time axis, optional zero markline, datazoom honoring `window_start`) and `add_lines()`. Tooltip numbers use pt-BR formatting selected by `tooltip_for(y_name)`. Chart builders receive prepared values: `echart_trend_single()` reads `value` and `trend`, while `echart_wide_lines()` draws already-assembled comparison data. RPPI-specific builders retain display scaling for fraction-valued `chg` and `acum12m` columns.

**`R/utils.R`** — palette and display formatting plus KPI and table components. `get_color_palette()` delegates to `ekioplot::ekio_pal()`, while `fmt_pct_br()`, `fmt_num_br()`, `pp_dir()`, and `pp_lbl()` format prepared values for the UI.

**`analysis/`** — exploratory scripts not loaded by the app: `plot_secovi.R` (ggplot2 charts off the gitignored `data/secovi-sp.csv`) and `prep_secovi.R` (draft data prep).

### Server Pattern

All seven datasets are loaded once at app startup into a global `initial_data` list (shared across sessions, not re-read per session); each session reads it through trivial read-only reactives (`rppi_data`, `bcb_data`, …). The data is static for the life of the process — there is no runtime refetch. City choices populate once via `observe` + `updateSelectInput`, defaulting `input$city` to São Paulo and seeding `input$cmp_cities` from `MAIN_CITIES`. Charts `req()` their inputs before rendering.

## Data Sources

Most app data comes from the [`realestatebr`](https://github.com/viniciusoike/realestatebr) package via `get_dataset(name)`. Available datasets (see `list_datasets()`): `rppi`, `rppi_bis`, `abecip` (housing credit), `abrainc` (primary market), `bcb_realestate`, `bcb_series` (macro: IPCA, IGP-M, INCC… — note Selic is *not* here), `fgv_ibre`, `secovi` (São Paulo). Two things come straight from the BCB SGS API through `fetch_bcb_sgs()` instead: the Selic meta rate (432) and the employment, income and production series listed in `SGS_ATIVIDADE` (PNAD Contínua, empregos formais, massa de rendimento, renda disponível, produção industrial, varejo, PMS, IBC-Br). Where BCB publishes a seasonally adjusted version, the registry points at it (`sa_source = TRUE`); the rest are adjusted at prep time with trendseries.

## Design Direction (mockup)

Six sections via a left sidebar: **Panorama** (executive summary with KPI cards), **Preços**, **Crédito**, **Mercado**, **São Paulo**, and **Macro**. **Atividade** follows the same dense grid but is not part of the mockup. Key principles from `mockup-brief.md`:

- Never show raw data — every series gets trend extraction (STL), deseasonalization, or aggregation
- Ekio branding: blue `#1E3A5F` primary, orange `#DD6B20` accent, teal `#2C7A7B` secondary — defined in `_brand.yml` and as CSS variables in `styles.css`
- Build broadly first; iterate and cut back later — comprehensiveness over UI polish

## Conventions

- 2-space indentation, UTF-8 encoding (set in `.Rproj`)
- Portuguese UI labels; English internal column names and identifiers
- RStudio-style section headers in R code (`# Section ----`), never box-style comment banners
- `data/` and `.cache/` are gitignored — local data comes from `realestatebr` or manual download
- Chart colors always go through `get_color_palette()` / `pal` (or `echart_palette()` for >5 series)
- Attach single packages, never `library(tidyverse)` — the meta-package drags `ragg` and `textshaping` into `renv.lock`, and those source-build on CI. This applies to `analysis/` too, since `renv::snapshot()` reads it
- `CLAUDE.md` is the canonical version of this file — keep the two in sync when updating
