library(realestatebr)
library(dplyr)
library(tidyr)
library(lubridate)
library(here)
library(jsonlite)
library(curl)

# Labels ----------------------------------------------------------------------

vlvar <- c(
  "Acumulado 12 Meses (%)" = "acum12m",
  "Variação Mensal (%)"    = "chg",
  "Índice"                 = "index",
  "YoY do Trend (STL, %)"  = "trend_yoy"
)

# STL trend -------------------------------------------------------------------

# STL trend of a monthly vector, aligned to `dates`. stl() cannot handle NAs,
# so the trend is computed on the leading/trailing-trimmed contiguous segment
# and mapped back. Returns all-NA when the series is too short (< 36) or has
# interior gaps.
stl_trend_vec <- function(v, dates) {

  ord <- order(dates)
  v   <- v[ord]
  d   <- dates[ord]
  out <- rep(NA_real_, length(v))

  nn <- which(!is.na(v))
  if (length(nn) < 36) return(out[order(ord)])

  first <- nn[1]
  last  <- nn[length(nn)]
  seg   <- v[first:last]
  if (anyNA(seg)) return(out[order(ord)])  # interior gaps break stl()

  trend <- tryCatch({
    s <- d[first]
    ts_obj <- stats::ts(
      seg,
      start     = c(lubridate::year(s), lubridate::month(s)),
      frequency = 12
    )
    fit <- stats::stl(ts_obj, s.window = "periodic", robust = TRUE)
    as.numeric(fit$time.series[, "trend"])
  }, error = function(e) rep(NA_real_, length(seg)))

  out[first:last] <- trend
  out[order(ord)]
}

# STL on the monthly index, then 12-month % change of the trend component.
add_stl_trend <- function(df) {
  df <- dplyr::arrange(df, date)
  df$trend     <- stl_trend_vec(df$index, df$date)
  df$trend_yoy <- (df$trend / dplyr::lag(df$trend, 12) - 1) * 100
  df
}

# Dataset preps ---------------------------------------------------------------

# Generic prep: validate required columns, leave data untouched.
# Dataset-specific transforms replace these as tabs get built.
make_prep <- function(name, required) {
  force(name); force(required)
  function(df) {
    missing <- setdiff(required, names(df))
    if (length(missing) > 0) {
      stop(
        "get_dataset('", name, "') returned unexpected columns. Missing: ",
        paste(missing, collapse = ", "),
        ". Got: ", paste(names(df), collapse = ", ")
      )
    }
    df
  }
}

prep_rppi <- function(df) {
  # realestatebr >= 0.4 renamed category -> transaction_type
  if ("transaction_type" %in% names(df) && !"category" %in% names(df)) {
    df <- dplyr::rename(df, category = transaction_type)
  }

  make_prep("rppi", c("date", "name_muni", "source", "category", "index"))(df)

  df |>
    dplyr::group_by(source, name_muni, category) |>
    dplyr::group_modify(~ add_stl_trend(.x)) |>
    dplyr::ungroup()
}

# Dataset registry ------------------------------------------------------------

# App-level dataset names -> realestatebr (dataset, table) plus a prep
# function. Cached individually at .cache/<name>.rds.
DATASETS <- list(
  rppi = list(
    # table = "all" stacks every index source (FipeZap, IVG-R, IVAR, ...).
    # Only the default FipeZAP table lives in the GitHub cache, so this
    # falls back to a fresh download from the original sources.
    dataset = "rppi", table = "all",
    prep = prep_rppi
  ),
  abecip_sbpe = list(
    dataset = "abecip", table = "sbpe",
    prep = make_prep("abecip", c("date", "sbpe_netflow", "sbpe_stock"))
  ),
  abecip_units = list(
    dataset = "abecip", table = "units",
    prep = make_prep("abecip", "date")
  ),
  abrainc = list(
    dataset = "abrainc", table = "indicator",
    prep = make_prep("abrainc", c("date", "category", "variable", "value"))
  ),
  bcb_series = list(
    dataset = "bcb_series", table = "core",
    prep = make_prep("bcb_series", c("date", "name_simplified", "value"))
  ),
  secovi = list(
    dataset = "secovi", table = "all",
    prep = make_prep("secovi", c("date", "category", "variable", "value"))
  ),
  # Selic meta (SGS 432), the one macro series realestatebr doesn't carry.
  # Fetched straight from BCB; degrades to an empty tibble if unreachable.
  bcb_selic = list(
    fetch = function() fetch_bcb_sgs(432),
    prep  = function(df) df
  )
)

# BCB SGS daily series -> monthly (last obs per month). BCB caps daily-series
# queries at ~10 years per request, so the window starts 9 years back.
# Returns an empty data.frame (with a fetch_error attr) on any failure so the
# app keeps running.
fetch_bcb_sgs <- function(code, years = 9) {
  start <- format(Sys.Date() - lubridate::years(years), "%d/%m/%Y")
  url <- sprintf(
    "https://api.bcb.gov.br/dados/serie/bcdata.sgs.%d/dados?formato=json&dataInicial=%s",
    code, start
  )
  out <- tryCatch({
    # BCB's API rejects non-browser User-Agents with HTTP 406.
    h <- curl::new_handle()
    curl::handle_setheaders(
      h, "User-Agent" = "Mozilla/5.0 (painel-mercado-imobiliario)"
    )
    resp <- curl::curl_fetch_memory(url, handle = h)
    if (resp$status_code != 200) stop("HTTP ", resp$status_code)
    raw <- jsonlite::fromJSON(rawToChar(resp$content))
    raw |>
      dplyr::transmute(
        date  = lubridate::dmy(.data$data),
        value = as.numeric(.data$valor)
      ) |>
      dplyr::mutate(month = lubridate::floor_date(date, "month")) |>
      dplyr::group_by(month) |>
      dplyr::slice_tail(n = 1) |>
      dplyr::ungroup() |>
      dplyr::transmute(date = month, value = value)
  }, error = function(e) {
    df <- data.frame(date = as.Date(character()), value = numeric())
    attr(df, "fetch_error") <- conditionMessage(e)
    df
  })
  out
}

# Loader ----------------------------------------------------------------------

CACHE_DIR <- here::here(".cache")

cache_path <- function(name) file.path(CACHE_DIR, paste0(name, ".rds"))

load_dataset <- function(name, force = FALSE) {
  spec <- DATASETS[[name]]
  if (is.null(spec)) {
    stop(
      "Unknown dataset '", name, "'. Registered: ",
      paste(names(DATASETS), collapse = ", ")
    )
  }

  path <- cache_path(name)
  if (!force && file.exists(path)) {
    return(readRDS(path))
  }

  # spec$fetch overrides the default realestatebr path (e.g. direct BCB API).
  # A failed fetch/prep (network error, schema change) must never abort startup:
  # degrade to an empty frame and let the fallback below recover from cache.
  out <- tryCatch({
    raw <- if (!is.null(spec$fetch)) {
      spec$fetch()
    } else {
      suppressWarnings(
        realestatebr::get_dataset(spec$dataset, table = spec$table)
      )
    }
    spec$prep(raw)
  }, error = function(e) {
    warning("Fetch/prep for '", name, "' failed: ", conditionMessage(e))
    data.frame()
  })

  # A transient fetch failure (e.g. BCB API hiccup) yields an empty frame.
  # Never persist it: fall back to a previous cache if one exists, otherwise
  # return the empty frame WITHOUT caching so the next load retries instead of
  # poisoning the cache with permanent emptiness.
  if (nrow(out) == 0) {
    if (file.exists(path)) return(readRDS(path))
    warning(
      "Fetch for '", name, "' returned no rows; not caching. ",
      "It will be retried on the next load."
    )
    return(out)
  }

  attr(out, "fetched_at") <- Sys.time()
  # Persisting is best-effort: on a read-only host (e.g. Posit Connect) the
  # write may fail, which must not abort the load — the in-memory frame is fine.
  tryCatch({
    dir.create(CACHE_DIR, showWarnings = FALSE, recursive = TRUE)
    saveRDS(out, path)
  }, error = function(e) {
    warning("Could not write cache for '", name, "': ", conditionMessage(e))
  })
  out
}

load_rppi <- function(force = FALSE) {
  load_dataset("rppi", force = force)
}

# RPPI helpers ----------------------------------------------------------------

split_rppi <- function(df) {
  list(
    rent = dplyr::filter(df, category == "rent"),
    sale = dplyr::filter(df, category == "sale")
  )
}

# IVG-R (BCB) is a national index — sale-only, available solely for "Brazil".
# To show it alongside the per-city sources on the Venda variation chart, relabel
# its Brazil rows to the selected city (a no-op when the city already is Brazil).
sale_with_ivgr <- function(sale, city) {
  base <- dplyr::filter(sale, name_muni == city)
  if (identical(city, "Brazil")) return(base)
  ivgr <- dplyr::filter(sale, source == "IVG-R", name_muni == "Brazil")
  if (nrow(ivgr) == 0) return(base)
  ivgr$name_muni <- city
  dplyr::bind_rows(base, ivgr)
}

# IVAR (FGV) national rent index is stored with name_muni = NA. To show it
# alongside the per-city rent sources, relabel it to the requested city (a no-op
# unless that city is "Brazil", since IVAR has no per-city series here).
rent_with_ivar <- function(rent, city) {
  base <- dplyr::filter(rent, name_muni == city)
  if (!identical(city, "Brazil")) return(base)
  ivar <- dplyr::filter(rent, source == "IVAR", is.na(name_muni))
  if (nrow(ivar) == 0) return(base)
  ivar$name_muni <- city
  dplyr::bind_rows(base, ivar)
}

# Calendar-year accumulated variation (%) per index, one row per year. Inflation
# series (INCC, IPCA — stored as monthly %) compound within the year; price
# indices (IGMI-R, IVAR — levels) use Dec/Dec-1 (last available month for the
# current, partial year). Years run 2010..latest; cells before a series starts
# are NA.
yearly_accum_data <- function(bcb, sp) {
  infl_year <- function(name) {
    bcb |>
      dplyr::filter(name_simplified == !!name, !is.na(value)) |>
      dplyr::arrange(date) |>
      dplyr::mutate(year = lubridate::year(date)) |>
      dplyr::group_by(year) |>
      dplyr::summarise(v = (prod(1 + value / 100) - 1) * 100, .groups = "drop")
  }
  idx_year <- function(df) {
    df |>
      dplyr::filter(!is.na(index)) |>
      dplyr::arrange(date) |>
      dplyr::mutate(year = lubridate::year(date)) |>
      dplyr::group_by(year) |>
      dplyr::slice_max(date, n = 1, with_ties = FALSE) |>
      dplyr::ungroup() |>
      dplyr::arrange(year) |>
      dplyr::transmute(year, v = (index / dplyr::lag(index) - 1) * 100)
  }

  incc <- infl_year("incc")
  ipca <- infl_year("ipca")
  igmi <- idx_year(dplyr::filter(sp$sale, source == "IGMI-R", name_muni == "Brazil"))
  ivar <- idx_year(dplyr::filter(sp$rent, source == "IVAR", is.na(name_muni)))

  max_year <- suppressWarnings(max(c(incc$year, ipca$year, igmi$year, ivar$year)))
  if (!is.finite(max_year)) return(data.frame())
  years <- 2010:max_year
  pick <- function(t) t$v[match(years, t$year)]
  data.frame(
    year = years,
    incc = pick(incc), ipca = pick(ipca),
    igmi = pick(igmi), ivar = pick(ivar)
  )
}

city_choices <- function(df) {
  cities <- sort(unique(df$name_muni))
  # data uses "Brazil" and title-case "Rio De Janeiro"
  preferred <- c("Brazil", "Brasil", "São Paulo", "Rio De Janeiro",
                 "Rio de Janeiro")
  c(intersect(preferred, cities), setdiff(cities, preferred))
}

# Main capitals for the comparison chart and summary table, in display order.
MAIN_CITIES <- c(
  "São Paulo", "Rio De Janeiro", "Belo Horizonte", "Curitiba",
  "Porto Alegre", "Brasília", "Salvador", "Fortaleza", "Recife", "Goiânia"
)

# Secovi helpers --------------------------------------------------------------

# Pull one Secovi series as date + value, sorted. `name` is optional.
secovi_pick <- function(sec, variable, name = NULL) {
  d <- dplyr::filter(sec, variable == !!variable)
  if (!is.null(name)) d <- dplyr::filter(d, name == !!name)
  d |>
    dplyr::arrange(date) |>
    dplyr::select(date, value)
}

# Tipologia chip -> sales variable suffix (Secovi splits 1/2/3/4 rooms).
SECOVI_TIPOLOGIA <- c(
  "Total"  = "sales",
  "1 dorm" = "sales_1rooms",
  "2 dorm" = "sales_2rooms",
  "3 dorm" = "sales_3rooms"
)

# BCB / ABRAINC helpers -------------------------------------------------------

# One bcb_series series as date + value, sorted.
bcb_pick <- function(bcb, name) {
  bcb |>
    dplyr::filter(name_simplified == !!name) |>
    dplyr::arrange(date) |>
    dplyr::select(date, value)
}

# One ABRAINC series (category + segment variable) as date + value, sorted.
abrainc_pick <- function(ab, category, variable = "total") {
  ab |>
    dplyr::filter(category == !!category, variable == !!variable) |>
    dplyr::arrange(date) |>
    dplyr::select(date, value)
}

# Segmento chip -> ABRAINC segment variable.
ABRAINC_SEGMENTO <- c(
  "Total"       = "total",
  "Econômico"   = "social_housing",
  "Alto Padrão" = "market_rate"
)
