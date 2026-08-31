# Regenerate the bundled cache "seed" before deploying.
#
# Force-fetches every dataset the app uses into .cache/<name>.rds so each file
# carries a fresh `fetched_at` stamp, then copies the results into the
# git-tracked data-cache/ directory. Posit Connect Cloud deploys straight from
# the git repo (no build step, no bundle upload), so data-cache/ is the only
# thing standing between a fresh deploy and a live, from-scratch fetch of
# every dataset (see R/_setup.R's SEED_DIR). To publish fresh data: run this,
# confirm every line says "ok", then `git add data-cache && git commit && git
# push` (or let .github/workflows/refresh-data.yml do it on schedule).
# Deploying to a traditional Posit Connect server instead of Connect Cloud?
# Run tools/deploy.R afterwards to bundle-upload .cache/ via rsconnect.
#
# Usage:  Rscript tools/prewarm.R

source(here::here("R", "utils.R"))
source(here::here("R", "_setup.R"))

datasets <- c("rppi", "bcb_series", "bcb_selic", "bcb_activity",
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

# Publish into the git-tracked seed only once every dataset above is "ok" —
# never copy a partial/failed refresh into the committed seed.
dir.create("data-cache", showWarnings = FALSE, recursive = TRUE)
file.copy(
  list.files(".cache", pattern = "\\.rds$", full.names = TRUE),
  "data-cache",
  overwrite = TRUE
)

message(
  "\nCache seed ready in .cache/ and data-cache/. Next: commit & push ",
  "data-cache/ (Connect Cloud) or run tools/deploy.R (Posit Connect server)."
)
