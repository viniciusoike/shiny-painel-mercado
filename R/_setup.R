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
  raw <- if (!is.null(spec$fetch)) {
    spec$fetch()
  } else {
    suppressWarnings(
      realestatebr::get_dataset(spec$dataset, table = spec$table)
    )
  }
  out <- spec$prep(raw)

  # A transient fetch failure (e.g. BCB API hiccup) yields an empty frame;
  # keep the previous cache rather than clobbering it with nothing.
  if (nrow(out) == 0 && file.exists(path)) {
    return(readRDS(path))
  }

  attr(out, "fetched_at") <- Sys.time()
  dir.create(CACHE_DIR, showWarnings = FALSE, recursive = TRUE)
  saveRDS(out, path)
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
