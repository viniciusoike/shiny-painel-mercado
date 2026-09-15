# Check the contracts that the scheduled refresh depends on before making any
# network requests. This is intentionally a small Rscript smoke test rather
# than a package test suite; the dashboard is not structured as an R package.
#
# Usage: Rscript tools/check-refresh.R

source(here::here("R", "utils.R"))
source(here::here("R", "_setup.R"))

if (!requireNamespace("seasonal", quietly = TRUE)) {
  cli::cli_abort(
    "Package {.pkg seasonal} is required for SEATS seasonal adjustment."
  )
}

if (!"augment_rolling" %in% getNamespaceExports("trendseries")) {
  cli::cli_abort(
    "Package {.pkg trendseries} must export {.fn augment_rolling}."
  )
}

# The upstream RPPI table uses `transaction_type`; preparation exposes the
# dashboard's canonical `category` column.
rppi_fixture <- tibble::tibble(
  date = seq(as.Date("2023-01-01"), by = "month", length.out = 36),
  name_muni = "Brazil",
  source = "FipeZap",
  transaction_type = "sale",
  index = seq(100, 135),
  chg = 0.01,
  acum12m = 0.12
)
rppi_result <- prep_rppi(rppi_fixture)
if (
  nrow(rppi_result) != nrow(rppi_fixture) ||
    !"category" %in% names(rppi_result)
) {
  cli::cli_abort("RPPI preparation did not preserve its schema contract.")
}

# Strict refreshes must surface a failed fetch even when an old cache exists.
check_strict_refresh <- function() {
  old_cache_dir <- CACHE_DIR
  old_seed_dir <- SEED_DIR
  old_registry <- SOURCE_REGISTRY
  temp_paths <- character()
  on.exit({
    unlink(temp_paths, recursive = TRUE, force = TRUE)
    CACHE_DIR <<- old_cache_dir
    SEED_DIR <<- old_seed_dir
    SOURCE_REGISTRY <<- old_registry
  })

  CACHE_DIR <<- tempfile("refresh-check-cache-")
  SEED_DIR <<- tempfile("refresh-check-seed-")
  temp_paths <- c(temp_paths, CACHE_DIR, SEED_DIR)
  dir.create(CACHE_DIR)
  SOURCE_REGISTRY <<- list(
    refresh_check = list(
      fetch = function() cli::cli_abort("Expected upstream failure."),
      prep = tibble::as_tibble
    )
  )

  previous <- tibble::tibble(value = 1)
  attr(previous, "fetched_at") <- as.POSIXct(
    "2026-08-31 20:28:00",
    tz = "UTC"
  )
  attr(previous, "pipeline_version") <- PIPELINE_VERSION
  saveRDS(previous, cache_path("refresh_check"))

  error <- tryCatch(
    {
      load_dataset("refresh_check", update = TRUE, strict = TRUE)
      NULL
    },
    error = identity
  )
  if (
    is.null(error) ||
      !grepl("Fetch/preparation failed", conditionMessage(error))
  ) {
    cli::cli_abort("Strict refresh accepted a stale cache fallback.")
  }

  fallback <- suppressWarnings(
    load_dataset("refresh_check", update = TRUE)
  )
  if (!identical(attr(fallback, "fetched_at"), attr(previous, "fetched_at"))) {
    cli::cli_abort("Non-strict startup did not retain its cache fallback.")
  }

  SOURCE_REGISTRY <<- list(
    refresh_check = list(
      fetch = function() tibble::tibble(value = numeric()),
      prep = tibble::as_tibble
    )
  )
  empty_error <- tryCatch(
    {
      load_dataset("refresh_check", update = TRUE, strict = TRUE)
      NULL
    },
    error = identity
  )
  if (
    is.null(empty_error) ||
      !grepl("returned no rows", conditionMessage(empty_error))
  ) {
    cli::cli_abort("Strict refresh accepted an empty fetch.")
  }

  CACHE_DIR <<- tempfile("refresh-check-not-directory-")
  temp_paths <- c(temp_paths, CACHE_DIR)
  file.create(CACHE_DIR)
  SOURCE_REGISTRY <<- list(
    refresh_check = list(
      fetch = function() tibble::tibble(value = 2),
      prep = tibble::as_tibble
    )
  )
  write_error <- tryCatch(
    {
      suppressWarnings(
        load_dataset("refresh_check", update = TRUE, strict = TRUE)
      )
      NULL
    },
    error = identity
  )
  if (
    is.null(write_error) ||
      !grepl("Could not write", conditionMessage(write_error))
  ) {
    cli::cli_abort("Strict refresh accepted a failed cache write.")
  }
}

check_strict_refresh()
cli::cli_inform("Refresh contracts passed.")
