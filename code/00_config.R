# 00_config.R
# Central configuration for esop_us_map. All scripts source this file.
# Run scripts from the project root: esop_us_map/

# --- Input data -----------------------------------------------------------------
RAW_DIR <- normalizePath(
  "../ESOP_TFM/data/raw/esops/1999-2024_Form5500",
  mustWork = FALSE
)

# --- Scope ----------------------------------------------------------------------
YEARS <- 2000:2024

US_STATES <- c(
  "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
  "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
  "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
  "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
  "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
)

# --- Output paths ---------------------------------------------------------------
PROCESSED_DIR <- "data-processed"
DOCS_DATA_DIR <- "docs/data"
