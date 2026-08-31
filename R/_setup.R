# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

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

# bcb_series carries Selic as a daily series; the app wants one value a month.
prep_bcb_selic <- function(df) {
  need <- c("date", "name_simplified", "value")
  if (is.null(df) || nrow(df) == 0 || !all(need %in% names(df))) {
    return(data.frame(date = as.Date(character()), value = numeric()))
  }
  sel <- df[df$name_simplified == "selic", c("date", "value")]
  if (nrow(sel) == 0) {
    return(data.frame(date = as.Date(character()), value = numeric()))
  }
  sel |>
    dplyr::filter(!is.na(.data$value)) |>
    dplyr::mutate(month = lubridate::floor_date(.data$date, "month")) |>
    dplyr::group_by(.data$month) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup() |>
    dplyr::transmute(date = .data$month, value = .data$value) |>
    dplyr::arrange(.data$date)
}

# Selic, preferring realestatebr. bcb_series carries it daily back to 1999 and
# is fetched anyway, so this costs nothing and avoids a second SGS call — the
# call that used to fail often enough to empty the dataset and stop the
# pre-warm. Older caches predate Selic landing in bcb_series, so fall back to
# a direct windowed SGS 432 request when it is absent.
fetch_bcb_selic <- function() {
  series <- tryCatch(load_dataset("bcb_series"), error = function(e) NULL)
  out <- prep_bcb_selic(series)
  if (nrow(out) > 0) return(out)
  warning("bcb_series carries no 'selic'; falling back to a direct SGS fetch.")
  fetch_bcb_sgs(432, start = as.Date("1999-01-01"))
}

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
  # Selic comes out of bcb_series, which carries it daily back to 1999.
  # Requesting SGS 432 directly used to empty this dataset whenever BCB
  # throttled the call, and an empty Selic fails the whole pre-warm.
  bcb_selic = list(
    fetch = fetch_bcb_selic,
    prep  = function(df) df
  ),
  # Employment, income and production series. realestatebr does not carry
  # these, so they come from SGS directly — incrementally, off the previous
  # cache, so a refresh asks for a few months rather than two decades.
  bcb_activity = list(
    fetch = function(previous) fetch_bcb_activity(previous),
    prep  = function(df) prep_bcb_activity(df)
  )
)

# SGS request retry ------------------------------------------------------------

# One SGS request, retried with backoff. BCB throttles bursts and times out on
# large spans, which used to empty a whole dataset on a single bad response.
# Raises with the HTTP status so callers can report why a series is missing.
sgs_request <- function(code, from, to, tries = 4L) {
  url <- sprintf(
    paste0(
      "https://api.bcb.gov.br/dados/serie/bcdata.sgs.%d/dados",
      "?formato=json&dataInicial=%s&dataFinal=%s"
    ),
    code, format(from, "%d/%m/%Y"), format(to, "%d/%m/%Y")
  )
  last <- NULL
  for (attempt in seq_len(tries)) {
    res <- tryCatch({
      # BCB's API rejects non-browser User-Agents with HTTP 406.
      h <- curl::new_handle(timeout = 120L, connecttimeout = 20L)
      curl::handle_setheaders(
        h, "User-Agent" = "Mozilla/5.0 (painel-mercado-imobiliario)"
      )
      resp <- curl::curl_fetch_memory(url, handle = h)
      if (resp$status_code != 200) stop("HTTP ", resp$status_code)
      body <- rawToChar(resp$content)
      Encoding(body) <- "UTF-8"
      if (!nzchar(trimws(body))) return(sgs_empty())
      jsonlite::fromJSON(body)
    }, error = function(e) e)
    if (!inherits(res, "error")) return(res)
    last <- res
    # Linear backoff: BCB recovers in seconds, so there is no need to
    # wait minutes before the last attempt.
    if (attempt < tries) Sys.sleep(2 * attempt)
  }
  stop("SGS ", code, " failed after ", tries, " tries: ", conditionMessage(last))
}

sgs_empty <- function() data.frame(data = character(), valor = character())

# BCB SGS series -> monthly (last obs per month; a no-op for series already
# published monthly). SGS caps daily-series queries at ~10 years per request,
# so anything longer is fetched in windows and stitched back together.
# Returns an empty data.frame (with a fetch_error attr) on any failure so the
# app keeps running.
fetch_bcb_sgs <- function(code, years = 9, start = NULL, end = Sys.Date(),
                          tries = 4L) {
  from <- as.Date(if (is.null(start)) Sys.Date() - lubridate::years(years) else start)
  end <- as.Date(end)
  if (from > end) return(sgs_monthly(sgs_empty()))

  # Windows of just under 10 years, the span SGS accepts in one request.
  starts <- seq(from, end, by = "10 years")
  ends <- c(starts[-1] - 1, end)

  out <- tryCatch({
    # Indexed rather than Map()ed: mapply() drops the Date class and the
    # bounds would reach sgs_request() as bare numbers.
    parts <- lapply(seq_along(starts), function(i) {
      sgs_request(code, starts[i], ends[i], tries)
    })
    sgs_monthly(dplyr::bind_rows(parts))
  }, error = function(e) {
    df <- data.frame(date = as.Date(character()), value = numeric())
    attr(df, "fetch_error") <- conditionMessage(e)
    df
  })
  out
}

# Raw SGS rows (data/valor) -> one row per month, keeping the last observation.
sgs_monthly <- function(raw) {
  if (is.null(raw) || nrow(raw) == 0) {
    return(data.frame(date = as.Date(character()), value = numeric()))
  }
  raw |>
    dplyr::transmute(
      date  = lubridate::dmy(.data$data),
      value = as.numeric(.data$valor)
    ) |>
    dplyr::filter(!is.na(.data$date)) |>
    dplyr::mutate(month = lubridate::floor_date(.data$date, "month")) |>
    dplyr::group_by(.data$month) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup() |>
    dplyr::transmute(date = .data$month, value = .data$value) |>
    dplyr::arrange(.data$date)
}

# BCB activity series ---------------------------------------------------------

# Extra SGS series on employment, income and production. `sa_source = TRUE`
# marks the series BCB already publishes seasonally adjusted; the rest are
# adjusted here with an STL decomposition (trendseries). `kind` drives the
# 12-month comparison: levels use a % change, rates a percentage-point
# difference. `group` sets the block each card lands in on the Atividade tab.
SGS_ATIVIDADE <- tibble::tribble(
  ~series,                     ~code, ~label,                                              ~unit,          ~sa_source, ~kind,   ~group,
  "pnad_ocupados",             24379, "Pessoas Ocupadas (PNAD Contínua)",                  "mil pessoas",  FALSE,      "level", "trabalho",
  "pnad_forca_trabalho",       24378, "Força de Trabalho (PNAD Contínua)",                 "mil pessoas",  FALSE,      "level", "trabalho",
  "pnad_desocupacao",          24369, "Taxa de Desocupação (PNAD Contínua)",               "%",            FALSE,      "rate",  "trabalho",
  "emprego_formal",            28763, "Estoque de Empregos Formais — Total",               "pessoas",      FALSE,      "level", "trabalho",
  "emprego_formal_construcao", 28770, "Estoque de Empregos Formais — Construção",          "pessoas",      FALSE,      "level", "trabalho",
  "massa_rendimento",          28545, "Massa de Rendimento Real Habitual",                 "R$ milhões",   FALSE,      "level", "renda",
  "rendimento_medio",          24382, "Rendimento Médio Real Habitual",                    "R$",           FALSE,      "level", "renda",
  "renda_disponivel",          29027, "Renda Disponível das Famílias — Massa",             "R$ milhões",   TRUE,       "level", "renda",
  "ipi_geral",                 28503, "Produção Industrial — Geral",                       "índice",       TRUE,       "level", "producao",
  "ipi_construcao",            28511, "Produção Industrial — Insumos da Construção Civil", "índice",       TRUE,       "level", "producao",
  "ipi_duraveis",              28509, "Produção Industrial — Bens de Consumo Duráveis",    "índice",       TRUE,       "level", "producao",
  "ibc_br",                    24364, "IBC-Br — Atividade Econômica",                      "índice",       TRUE,       "level", "producao",
  "varejo",                    28473, "Volume de Vendas no Varejo — Total",                "índice",       TRUE,       "level", "producao",
  "varejo_material_construcao", 28484, "Volume de Vendas — Material de Construção",        "índice",       TRUE,       "level", "producao",
  "pms_servicos",              23982, "Volume de Serviços (PMS) — Total",                  "índice",       FALSE,      "level", "producao"
)

# Fetch every SGS_ATIVIDADE series into one long frame. A series that fails is
# skipped with a warning instead of aborting the whole dataset.
# `previous` is the last good version of this dataset (from cache). When it is
# supplied, each series is refetched only from its last stored observation
# rather than from `start`, which keeps the weekly refresh to a handful of new
# rows per series instead of ~260. A series whose incremental request fails
# keeps its stored history instead of vanishing from the dataset.
fetch_bcb_activity <- function(previous = NULL,
                               start = as.Date("2004-01-01"),
                               revise_months = 6) {
  have <- !is.null(previous) && nrow(previous) > 0 &&
    all(c("series", "date", "value") %in% names(previous))

  parts <- lapply(seq_len(nrow(SGS_ATIVIDADE)), function(i) {
    row <- SGS_ATIVIDADE[i, ]
    old <- if (have) previous[previous$series == row$series, c("series", "date", "value")] else NULL
    if (!is.null(old) && nrow(old) == 0) old <- NULL

    # Refetch the last few months alongside the new ones: BCB revises recent
    # observations, and re-requesting them costs almost nothing.
    from <- if (is.null(old)) start else {
      max(start, lubridate::floor_date(max(old$date), "month") -
            months(revise_months))
    }

    d <- fetch_bcb_sgs(row$code, start = from)
    if (nrow(d) == 0) {
      why <- attr(d, "fetch_error")
      warning(
        "SGS series ", row$code, " (", row$series, ") returned no rows",
        if (is.null(why)) "." else paste0(": ", why),
        if (is.null(old)) "" else " Keeping stored history."
      )
      if (is.null(old)) return(NULL)
      return(old)
    }
    d <- dplyr::mutate(d, series = row$series, .before = 1)
    if (is.null(old)) d else sgs_merge(old, d)
  })

  parts <- Filter(Negate(is.null), parts)
  if (length(parts) == 0) return(data.frame())
  dplyr::bind_rows(parts) |>
    dplyr::left_join(
      dplyr::select(SGS_ATIVIDADE, series, code, sa_source, kind),
      by = "series"
    ) |>
    dplyr::arrange(series, date)
}

# Upsert freshly fetched rows over stored ones, newest value winning per date.
# Never returns fewer rows than it was given, so a short incremental response
# cannot truncate a stored series.
sgs_merge <- function(old, new) {
  keep <- old[!old$date %in% new$date, , drop = FALSE]
  out <- dplyr::arrange(dplyr::bind_rows(keep, new), .data$date)
  if (nrow(out) < nrow(old)) old else out
}

# Seasonally adjust one series with STL. Series already adjusted at the source
# pass through; anything trendseries cannot handle falls back to the raw value.
deseason_vec <- function(v, dates) {
  ok <- !is.na(v)
  out <- rep(NA_real_, length(v))
  if (sum(ok) < 36 || !requireNamespace("trendseries", quietly = TRUE)) {
    return(v)
  }
  adj <- tryCatch({
    res <- trendseries::deseason_series(
      data.frame(date = dates[ok], value = v[ok]),
      methods = "stl",
      .quiet = TRUE
    )
    res$seasadj_stl
  }, error = function(e) NULL)
  if (is.null(adj) || length(adj) != sum(ok)) return(v)
  out[ok] <- adj
  out
}

# Seasonal adjustment (`sa`), STL trend of the adjusted series (`trend`) and
# the 12-month comparison (`yoy`, % for levels and pp for rates), per series.
prep_bcb_activity <- function(df) {
  make_prep("bcb_activity", c("date", "series", "value"))(df)
  if (nrow(df) == 0) return(df)

  df |>
    dplyr::group_by(series) |>
    dplyr::group_modify(~ {
      d <- dplyr::arrange(.x, date)
      d$sa <- if (isTRUE(d$sa_source[1])) {
        d$value
      } else {
        deseason_vec(d$value, d$date)
      }
      d$trend <- stl_trend_vec(d$sa, d$date)
      d$yoy <- if (identical(d$kind[1], "rate")) {
        d$sa - dplyr::lag(d$sa, 12)
      } else {
        (d$sa / dplyr::lag(d$sa, 12) - 1) * 100
      }
      d
    }) |>
    dplyr::ungroup()
}

# Activity helpers ------------------------------------------------------------

# One activity series as date + value, with `metric` picking the column:
# "sa" (seasonally adjusted level), "raw" (as published), "trend" (STL trend of
# the adjusted series) or "yoy".
activity_pick <- function(act, series, metric = "sa") {
  col <- switch(metric, sa = "sa", raw = "value", trend = "trend", yoy = "yoy", "sa")
  d <- dplyr::filter(act, series == !!series)
  if (nrow(d) == 0) return(data.frame(date = as.Date(character()), value = numeric()))
  d |>
    dplyr::arrange(date) |>
    dplyr::transmute(date, value = .data[[col]])
}

# Metadata row for one activity series (label, unit, kind).
activity_meta <- function(series) {
  as.list(SGS_ATIVIDADE[match(series, SGS_ATIVIDADE$series), ])
}

# Y-axis label for a series under the selected metric. The 12-month view is a %
# change for levels and a pp difference for rates.
activity_unit <- function(series, metric = "sa") {
  m <- activity_meta(series)
  if (identical(metric, "yoy")) {
    if (identical(m$kind, "rate")) "p.p. (12m)" else "% (12m)"
  } else {
    m$unit
  }
}

# Wide date x series frame of one metric, for the multi-series comparisons.
activity_wide <- function(act, series, labels = series, metric = "sa") {
  cols <- lapply(seq_along(series), function(i) {
    dplyr::rename(activity_pick(act, series[i], metric), !!labels[i] := value)
  })
  Reduce(function(a, b) dplyr::full_join(a, b, by = "date"), cols) |>
    dplyr::arrange(date)
}

# Rebase a wide frame to 100 at the first date where every column is observed.
rebase_100 <- function(df, cols) {
  present <- intersect(cols, names(df))
  d <- dplyr::arrange(df, date)
  complete <- which(stats::complete.cases(d[present]))
  if (length(complete) == 0) return(d)
  base <- complete[1]
  for (cl in present) d[[cl]] <- d[[cl]] / d[[cl]][base] * 100
  d
}

# Loader ----------------------------------------------------------------------

CACHE_DIR <- here::here(".cache")
# Git-tracked deploy seed (unlike .cache/, which is gitignored dev-only
# state). Posit Connect Cloud deploys straight from the git repo with no
# build step, so this is the only data a fresh deploy can read before ever
# hitting the network. Populated by tools/prewarm.R; see CLAUDE.md.
SEED_DIR <- here::here("data-cache")

cache_path <- function(name, dir = CACHE_DIR) file.path(dir, paste0(name, ".rds"))

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

  seed <- cache_path(name, SEED_DIR)
  if (!force && file.exists(seed)) {
    return(readRDS(seed))
  }

  # The last good copy, read even under force = TRUE: an incremental fetch
  # needs it to know where to resume, and it is the fallback if the fetch
  # comes back empty.
  previous <- tryCatch({
    if (file.exists(path)) readRDS(path)
    else if (file.exists(seed)) readRDS(seed)
    else NULL
  }, error = function(e) NULL)

  # spec$fetch overrides the default realestatebr path (e.g. direct BCB API).
  # A failed fetch/prep (network error, schema change) must never abort startup:
  # degrade to an empty frame and let the fallback below recover from cache.
  out <- tryCatch({
    raw <- if (!is.null(spec$fetch)) {
      # A fetch function taking an argument gets the last good cache, so it
      # can ask upstream only for what it does not already have.
      if (length(formals(spec$fetch))) spec$fetch(previous) else spec$fetch()
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
    if (!is.null(previous) && nrow(previous) > 0) return(previous)
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

# Trailing n-month rolling sum of a sorted date+value frame (monthly series;
# any NA inside a window yields NA, and the first n-1 rows are NA).
roll_sum <- function(df, n = 12) {
  v <- df$value
  out <- rep(NA_real_, length(v))
  if (length(v) >= n) {
    for (i in seq(n, length(v))) out[i] <- sum(v[(i - n + 1):i])
  }
  df$value <- out
  df
}

# Trailing n-month rolling mean of a sorted date+value frame. The first n-1
# rows are NA (no partial-window means); later NAs are preserved.
roll_mean <- function(df, n = 12) {
  v <- df$value
  out <- rep(NA_real_, length(v))
  if (length(v) >= n) {
    for (i in seq(n, length(v))) out[i] <- mean(v[(i - n + 1):i])
  }
  df$value <- out
  df
}

# Dormitório label -> Secovi sales variable (the 1/2/3/4-room sales split).
# Ordered small-to-large so stacked bands and table columns read consistently.
SECOVI_ROOMS <- c(
  "1 dorm" = "sales_1rooms",
  "2 dorm" = "sales_2rooms",
  "3 dorm" = "sales_3rooms",
  "4 dorm" = "sales_4rooms"
)

# Wide date x dormitório frame for one Secovi metric `name` (default the
# monthly unit count). One column per SECOVI_ROOMS label.
secovi_rooms_wide <- function(sec, name = "unidades") {
  cols <- lapply(names(SECOVI_ROOMS), function(lab) {
    dplyr::rename(secovi_pick(sec, SECOVI_ROOMS[[lab]], name), !!lab := value)
  })
  Reduce(function(a, b) dplyr::full_join(a, b, by = "date"), cols) |>
    dplyr::arrange(date)
}

# 12-month rolling sum of sales units per dormitório, wide (for the stacked
# area). Rolls each band on its own so partial leading windows stay NA.
secovi_rooms_units_12m <- function(sec) {
  cols <- lapply(names(SECOVI_ROOMS), function(lab) {
    rolled <- roll_sum(secovi_pick(sec, SECOVI_ROOMS[[lab]], "unidades"))
    dplyr::rename(rolled, !!lab := value)
  })
  Reduce(function(a, b) dplyr::full_join(a, b, by = "date"), cols) |>
    dplyr::arrange(date)
}

# Annual sales units per dormitório (year x band, wide). Only complete years
# (12 monthly observations) are kept so partial years never skew comparisons.
secovi_rooms_yearly <- function(sec) {
  parts <- lapply(names(SECOVI_ROOMS), function(lab) {
    secovi_pick(sec, SECOVI_ROOMS[[lab]], "unidades") |>
      dplyr::mutate(year = lubridate::year(date)) |>
      dplyr::group_by(year) |>
      dplyr::summarise(
        n = sum(!is.na(value)),
        value = sum(value, na.rm = TRUE),
        .groups = "drop"
      ) |>
      dplyr::transmute(year, !!lab := ifelse(n == 12, value, NA_real_))
  })
  Reduce(function(a, b) dplyr::full_join(a, b, by = "year"), parts) |>
    dplyr::arrange(year)
}

# Convert an annual wide frame (year + band cols) to within-year percentage
# shares (each year's bands sum to 100; all-NA years stay NA).
rooms_to_shares <- function(df, cols = names(SECOVI_ROOMS)) {
  present <- intersect(cols, names(df))
  m <- as.matrix(df[present])
  tot <- rowSums(m, na.rm = TRUE)
  tot[tot == 0] <- NA_real_
  out <- data.frame(year = df$year)
  out[present] <- round(sweep(m, 1, tot, "/") * 100, 1)
  out
}

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
