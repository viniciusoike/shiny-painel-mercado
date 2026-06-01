# Painel do Mercado Imobiliário — Design Brief

## Concept

A comprehensive Brazilian real estate market dashboard that compiles economic and market indicators into a single place. No equivalent service exists in Brazil. Built as both a daily working tool and an Ekio portfolio piece.

## Structure

Six sections organized via a left sidebar:

| Section | Purpose | Density |
|---------|---------|---------|
| **Panorama** | Market pulse — KPIs at a glance, key trend charts | Clean, spacious |
| **Preços** | Residential property price indices (RPPI) by city/source | Dense |
| **Crédito** | Housing credit: SBPE volumes, rates, delinquency | Dense |
| **Mercado** | Primary market: launches, sales, inventory (Abrainc) | Dense |
| **São Paulo** | Secovi-SP deep dive: VSO, launches, defaults by typology | Dense |
| **Macro** | BCB series: Selic, IPCA, IGP-M, GDP, employment | Dense |

## Design Principles

- **Panorama is executive-summary style**: small KPI cards (8) with sparklines + 2–3 large trend charts
- **All other tabs are Bloomberg-dense**: charts stacked in 2-column grids, minimal chrome, data-first
- **Never show raw data**: every series gets trend extraction (STL), deseasonalization, or aggregation
- **Ekio branding throughout**: blue #1E3A5F primary, orange #DD6B20 accent, teal #2C7A7B secondary, Helvetica Neue

## Data Sources (via `realestatebr` package)

- **RPPI** — compilation of all residential price indices (FipeZAP, IVG-R, IVAR)
- **Abecip** — SBPE credit volumes, rates, units financed
- **Abrainc** — launches, sales, segmented by economic vs high-end
- **BCB** — aggregated real estate credit/funding metrics + macro series API (Selic, IPCA, IGP-M, debt, employment)
- **Secovi-SP** — São Paulo-specific: launches, sales, VSO, inventory, condo defaults

## Tech Stack

- **R Shiny** with **bslib** (Bootstrap 5 theming)
- **echarts4r** for most interactive charts
- **ggplot2** for static analytical plots
- **ggiraph** for complex interactive plots (future)
- **ekioplot** package for brand colors and ggplot themes

## Philosophy

Build broadly first — more indicators, more charts, more views. Iterate based on actual usage. Cut back and optimize later. Comprehensiveness is the differentiator, not UI polish.

## Reference

See `mockup.html` for the visual template.
