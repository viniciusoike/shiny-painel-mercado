# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# Loader ----------------------------------------------------------------------

CACHE_DIR <- here::here(".cache")
PIPELINE_VERSION <- 2L
# Git-tracked deploy seed (unlike .cache/, which is gitignored dev-only
# state). Posit Connect Cloud deploys straight from the git repo with no
# build step, so this is the only data a fresh deploy can read before ever
# hitting the network. Populated by tools/prewarm.R; see CLAUDE.md.
SEED_DIR <- here::here("data-cache")

cache_path <- function(name, dir = CACHE_DIR) {
  file.path(dir, paste0(name, ".rds"))
}

prepare_cached_dataset <- function(name, data) {
  if (identical(attr(data, "pipeline_version"), PIPELINE_VERSION)) {
    return(tibble::as_tibble(data))
  }

  fetched_at <- attr(data, "fetched_at")
  prepared <- SOURCE_REGISTRY[[name]]$prep(data) |>
    tibble::as_tibble()
  attr(prepared, "fetched_at") <- fetched_at
  attr(prepared, "pipeline_version") <- PIPELINE_VERSION
  prepared
}

load_dataset <- function(name, force = FALSE) {
  spec <- SOURCE_REGISTRY[[name]]
  if (is.null(spec)) {
    cli::cli_abort(c(
      "Unknown dataset {.val {name}}.",
      "i" = "Registered datasets: {.val {names(SOURCE_REGISTRY)}}."
    ))
  }

  path <- cache_path(name)
  if (!force && file.exists(path)) {
    return(prepare_cached_dataset(name, readRDS(path)))
  }

  seed <- cache_path(name, SEED_DIR)
  if (!force && file.exists(seed)) {
    return(prepare_cached_dataset(name, readRDS(seed)))
  }

  # The last good copy, read even under force = TRUE: an incremental fetch
  # needs it to know where to resume, and it is the fallback if the fetch
  # comes back empty.
  previous <- tryCatch(
    {
      if (file.exists(path)) {
        readRDS(path)
      } else if (file.exists(seed)) {
        readRDS(seed)
      } else {
        NULL
      }
    },
    error = function(e) NULL
  )

  # spec$fetch overrides the default realestatebr path (e.g. direct BCB API).
  # A failed fetch/prep (network error, schema change) must never abort startup:
  # degrade to an empty frame and let the fallback below recover from cache.
  out <- tryCatch(
    {
      raw <- if (!is.null(spec$fetch)) {
        # A fetch function taking an argument gets the last good cache, so it
        # can ask upstream only for what it does not already have.
        if (length(formals(spec$fetch))) spec$fetch(previous) else spec$fetch()
      } else {
        suppressWarnings(
          realestatebr::get_dataset(spec$dataset, table = spec$table)
        )
      }
      spec$prep(raw) |>
        tibble::as_tibble()
    },
    error = function(e) {
      cli::cli_warn(c(
        "Fetch/preparation failed for {.val {name}}.",
        "i" = conditionMessage(e)
      ))
      tibble::tibble()
    }
  )

  # A transient fetch failure (e.g. BCB API hiccup) yields an empty frame.
  # Never persist it: fall back to a previous cache if one exists, otherwise
  # return the empty frame WITHOUT caching so the next load retries instead of
  # poisoning the cache with permanent emptiness.
  if (nrow(out) == 0) {
    if (!is.null(previous) && nrow(previous) > 0) {
      return(prepare_cached_dataset(name, previous))
    }
    cli::cli_warn(c(
      "Fetch for {.val {name}} returned no rows; it was not cached.",
      "i" = "The next load will retry it."
    ))
    return(out)
  }

  attr(out, "fetched_at") <- Sys.time()
  attr(out, "pipeline_version") <- PIPELINE_VERSION
  # Persisting is best-effort: on a read-only host (e.g. Posit Connect) the
  # write may fail, which must not abort the load — the in-memory frame is fine.
  tryCatch(
    {
      dir.create(CACHE_DIR, showWarnings = FALSE, recursive = TRUE)
      saveRDS(out, path)
    },
    error = function(e) {
      cli::cli_warn(c(
        "Could not write the cache for {.val {name}}.",
        "i" = conditionMessage(e)
      ))
    }
  )
  out
}

load_rppi <- function(force = FALSE) {
  load_dataset("rppi", force = force)
}
