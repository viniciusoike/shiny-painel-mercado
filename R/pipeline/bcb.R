# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# BCB preparation and ingestion ----------------------------------------------

# bcb_series carries Selic as a daily series; the app wants one value a month.
prep_bcb_selic <- function(df) {
  if (
    all(c("date", "value") %in% names(df)) &&
      !"name_simplified" %in% names(df)
  ) {
    return(
      df |>
        tibble::as_tibble() |>
        dplyr::mutate(date = lubridate::floor_date(.data$date, "month")) |>
        dplyr::group_by(.data$date) |>
        dplyr::slice_tail(n = 1) |>
        dplyr::ungroup() |>
        add_standard_features(kind = "rate")
    )
  }

  need <- c("date", "name_simplified", "value")
  if (is.null(df) || nrow(df) == 0 || !all(need %in% names(df))) {
    return(tibble::tibble(date = as.Date(character()), value = numeric()))
  }
  sel <- df[df$name_simplified == "selic", c("date", "value")]
  if (nrow(sel) == 0) {
    return(tibble::tibble(date = as.Date(character()), value = numeric()))
  }
  sel |>
    dplyr::filter(!is.na(.data$value)) |>
    dplyr::mutate(month = lubridate::floor_date(.data$date, "month")) |>
    dplyr::group_by(.data$month) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup() |>
    dplyr::mutate(date = .data$month) |>
    dplyr::select("date", "value") |>
    add_standard_features(kind = "rate")
}

prep_bcb_series <- function(data) {
  prepared <- make_prep(
    "bcb_series",
    c("date", "code_bcb", "name_simplified", "value")
  )(data) |>
    tibble::as_tibble() |>
    dplyr::mutate(date = lubridate::floor_date(.data$date, "month")) |>
    dplyr::group_by(.data$name_simplified, .data$code_bcb, .data$date) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup() |>
    dplyr::left_join(
      BCB_SERIES_REGISTRY,
      by = c("name_simplified" = "series", "code_bcb" = "code")
    ) |>
    dplyr::mutate(
      value_std = dplyr::case_when(
        .data$scale == "percent" ~ standardize_rate(.data$value, "percent"),
        TRUE ~ .data$value
      )
    )

  prepared |>
    dplyr::group_by(.data$name_simplified) |>
    dplyr::group_modify(
      ~ {
        kind <- .x$kind[[1]]
        output <- add_standard_features(.x, kind = kind)

        if (identical(kind, "rate_change")) {
          rates <- add_rate_features(
            dplyr::select(output, "date", value = "value_std")
          )
          output$change_12m <- rates$change_12m
          output$change_ytd <- rates$change_ytd
        } else {
          output$change_12m <- output$change_yoy
          output$change_ytd <- NA_real_
        }

        output
      }
    ) |>
    dplyr::ungroup() |>
    dplyr::arrange(.data$name_simplified, .data$date)
}

# Selic, preferring realestatebr. bcb_series carries it daily back to 1999 and
# is fetched anyway, so this costs nothing and avoids a second SGS call — the
# call that used to fail often enough to empty the dataset and stop the
# pre-warm. Older caches predate Selic landing in bcb_series, so fall back to
# a direct windowed SGS 432 request when it is absent.
fetch_bcb_selic <- function() {
  series <- tryCatch(load_dataset("bcb_series"), error = function(e) NULL)
  out <- prep_bcb_selic(series)
  if (nrow(out) > 0) {
    return(out)
  }
  cli::cli_warn(
    "Dataset {.val bcb_series} has no Selic series; fetching SGS 432."
  )
  fetch_bcb_sgs(432, start = as.Date("1999-01-01"))
}

# BCB SGS fetch ---------------------------------------------------------------

# Fetch one BCB SGS series through GetBCBData and reduce it to one observation
# per month. GetBCBData handles long date ranges, retries, and response parsing;
# the app retains responsibility for monthly aggregation and failure metadata.
fetch_bcb_sgs <- function(
  code,
  years = 9,
  start = NULL,
  end = Sys.Date()
) {
  from <- as.Date(
    if (is.null(start)) Sys.Date() - lubridate::years(years) else start
  )
  end <- as.Date(end)
  if (from > end) {
    return(tibble::tibble(date = as.Date(character()), value = numeric()))
  }

  tryCatch(
    {
      raw <- GetBCBData::gbcbd_get_series(
        id = code,
        first.date = from,
        last.date = end,
        be.quiet = TRUE,
        use.memoise = FALSE
      )
      out <- raw |>
        dplyr::filter(!is.na(.data$ref.date)) |>
        dplyr::mutate(month = lubridate::floor_date(.data$ref.date, "month")) |>
        dplyr::group_by(.data$month) |>
        dplyr::slice_tail(n = 1) |>
        dplyr::ungroup() |>
        dplyr::mutate(
          date = .data$month,
          value = as.numeric(.data$value)
        ) |>
        dplyr::select("date", "value") |>
        dplyr::arrange(.data$date)
      if (nrow(out) == 0) {
        attr(out, "fetch_error") <- "GetBCBData returned no observations."
      }
      out
    },
    error = function(e) {
      out <- tibble::tibble(date = as.Date(character()), value = numeric())
      attr(out, "fetch_error") <- conditionMessage(e)
      out
    }
  )
}

# BCB activity series ---------------------------------------------------------

# Extra SGS series on employment, income and production. `sa_source = TRUE`
# marks the series BCB already publishes seasonally adjusted; the rest are
# adjusted here with an STL decomposition (trendseries). `kind` drives the
# 12-month comparison: levels use a % change, rates a percentage-point
# difference. `group` sets the block each card lands in on the Atividade tab.

# Fetch every SGS_ATIVIDADE series into one long frame. A series that fails is
# skipped with a warning instead of aborting the whole dataset.
# `previous` is the last good version of this dataset (from cache). When it is
# supplied, each series is refetched only from its last stored observation
# rather than from `start`, which keeps the weekly refresh to a handful of new
# rows per series instead of ~260. A series whose incremental request fails
# keeps its stored history instead of vanishing from the dataset.
fetch_bcb_activity <- function(
  previous = NULL,
  start = as.Date("2004-01-01"),
  revise_months = 6
) {
  have <- !is.null(previous) &&
    nrow(previous) > 0 &&
    all(c("series", "date", "value") %in% names(previous))

  parts <- lapply(seq_len(nrow(SGS_ATIVIDADE)), function(i) {
    row <- SGS_ATIVIDADE[i, ]
    old <- if (have) {
      previous[previous$series == row$series, c("series", "date", "value")]
    } else {
      NULL
    }
    if (!is.null(old) && nrow(old) == 0) {
      old <- NULL
    }

    # Refetch the last few months alongside the new ones: BCB revises recent
    # observations, and re-requesting them costs almost nothing.
    from <- if (is.null(old)) {
      start
    } else {
      max(
        start,
        lubridate::floor_date(max(old$date), "month") -
          months(revise_months)
      )
    }

    d <- fetch_bcb_sgs(row$code, start = from)
    if (nrow(d) == 0) {
      why <- attr(d, "fetch_error")
      cli::cli_warn(c(
        "SGS series {.val {row$series}} ({row$code}) returned no rows.",
        "i" = if (is.null(why)) "No upstream reason was supplied." else why,
        "i" = if (is.null(old)) {
          "No stored history is available."
        } else {
          "Keeping stored history."
        }
      ))
      if (is.null(old)) {
        return(NULL)
      }
      return(old)
    }
    d <- dplyr::mutate(d, series = row$series, .before = 1)
    if (is.null(old)) d else sgs_merge(old, d)
  })

  parts <- Filter(Negate(is.null), parts)
  if (length(parts) == 0) {
    return(tibble::tibble())
  }
  dplyr::bind_rows(parts) |>
    dplyr::left_join(
      dplyr::select(
        SGS_ATIVIDADE,
        series,
        code,
        sa_source,
        kind,
        source,
        frequency,
        scale,
        seasonal,
        deflator
      ),
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

# Seasonally adjust one series with SEATS. Series already adjusted at the source
# pass through; failures fall back to the interpolated series.
deseason_vec <- function(v, dates) {
  deseason_series(v, dates)
}

# Seasonal adjustment (`sa`), STL trend of the adjusted series (`trend`) and
# the 12-month comparison (`yoy`, % for levels and pp for rates), per series.
prep_bcb_activity <- function(df) {
  make_prep("bcb_activity", c("date", "series", "value"))(df)
  if (nrow(df) == 0) {
    return(df)
  }

  policy_columns <- c(
    "code",
    "sa_source",
    "kind",
    "source",
    "frequency",
    "scale",
    "seasonal",
    "deflator"
  )
  df <- df |>
    dplyr::select(-dplyr::any_of(policy_columns)) |>
    dplyr::left_join(
      dplyr::select(SGS_ATIVIDADE, "series", dplyr::all_of(policy_columns)),
      by = "series"
    )

  df |>
    dplyr::group_by(series) |>
    dplyr::group_modify(
      ~ {
        d <- dplyr::arrange(.x, date)
        d$sa <- deseason_series(
          d$value,
          d$date,
          source_adjusted = identical(d$seasonal[1], "source")
        )
        d$trend <- stl_trend_vec(d$sa, d$date)
        d$yoy <- if (identical(d$kind[1], "rate")) {
          d$sa - dplyr::lag(d$sa, 12)
        } else {
          (d$sa / dplyr::lag(d$sa, 12) - 1) * 100
        }
        d$yoy_trend <- trend_series(d$yoy, d$date)
        d
      }
    ) |>
    dplyr::ungroup()
}
