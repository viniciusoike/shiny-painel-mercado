# Deploy the app to Posit Connect with the pre-warmed cache bundled.
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
