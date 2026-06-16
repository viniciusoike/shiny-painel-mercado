# Regenerate the bundled cache "seed" before deploying.
#
# Force-fetches every dataset the app uses into .cache/<name>.rds so each file
# carries a fresh `fetched_at` stamp. The app ships this cache and reads it at
# startup, so it never depends on live network access on the host (Posit
# Connect). To publish fresh data: run this, confirm every line says "ok",
# then run tools/deploy.R.
#
# Usage:  Rscript tools/prewarm.R

source(here::here("R", "utils.R"))
source(here::here("R", "_setup.R"))

datasets <- c("rppi", "bcb_series", "bcb_selic",
              "abecip_units", "secovi", "abrainc")

results <- vapply(datasets, function(name) {
  tryCatch({
    d <- load_dataset(name, force = TRUE)  # bypass cache, write fresh .rds
    if (nrow(d) == 0) {
      sprintf("WARN %-14s 0 rows (fetch returned empty — not cached)", name)
    } else {
      ts <- attr(d, "fetched_at")
      sprintf("ok   %-14s %6d rows  (%s)", name, nrow(d),
              if (is.null(ts)) "no stamp" else format(ts, "%Y-%m-%d %H:%M"))
    }
  }, error = function(e) sprintf("FAIL %-14s %s", name, conditionMessage(e)))
}, character(1))

message(paste(results, collapse = "\n"))

if (any(grepl("^(FAIL|WARN)", results))) {
  stop("Pre-warm incomplete — some datasets did not fetch. Do not deploy.")
}
message("\nCache seed ready in .cache/. Next: Rscript tools/deploy.R")
