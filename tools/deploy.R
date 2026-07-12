# Deploy the app to a traditional Posit Connect server with the pre-warmed
# cache bundled via rsconnect::deployApp(). NOT used for Posit Connect Cloud
# (which deploys straight from the linked GitHub repo) — that path instead
# reads the git-tracked data-cache/ seed directly; see R/_setup.R's SEED_DIR
# and tools/prewarm.R.
#
# Run tools/prewarm.R first so .cache/*.rds is fresh — those files ship in the
# bundle and the app reads them at startup (no live fetch on the host).
# appFiles is listed explicitly so the dotfile cache is included deterministically
# and dev-only files (mockup.html, analysis/, LICENSE) are left out.
#
# Usage:  Rscript tools/deploy.R
#
# Assumes an rsconnect account/server is already registered
# (rsconnect::accounts()). Set the server/account here if you have more than one.

seed <- list.files(".cache", pattern = "\\.rds$", full.names = TRUE)
if (length(seed) == 0) {
  stop("No .cache/*.rds found. Run tools/prewarm.R before deploying.")
}

app_files <- c(
  "app.R", "styles.css", "_brand.yml", "renv.lock", ".Rprofile",
  list.files("R", pattern = "\\.R$", full.names = TRUE),
  seed
)

rsconnect::deployApp(
  appName     = "painel-mercado-imobiliario",
  appTitle    = "Painel do Mercado Imobiliário — EKIO",
  appFiles    = app_files,
  forceUpdate = TRUE
)
