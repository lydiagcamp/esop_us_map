# 01_ingest_form5500.R
#
# Read all 25 raw Form 5500 CSV files (2000-2024), extract ESOP plans with
# full mailing address, and build a clean unbalanced plan-year panel.
#
# Filter: esop == 1 (TYPE_PENSION_BNFT_CODE contains "2O" or "2P"),
#         filing_year in 2000:2024, state in 50 US states.
#
# Schema differences across years (verified against all 25 file headers):
#   2000-2008: SPONS_DFE_MAIL_STR_ADDRESS / SPONS_DFE_CITY /
#              SPONS_DFE_STATE / SPONS_DFE_ZIP_CODE
#   2009-2024: SPONS_DFE_MAIL_US_ADDRESS1 / SPONS_DFE_MAIL_US_CITY /
#              SPONS_DFE_MAIL_US_STATE / SPONS_DFE_MAIL_US_ZIP
#   EIN, PN, PLAN_NAME, BUSINESS_CODE, TOT_ACTIVE_PARTCP_CNT are consistent
#   across all years under the same column names.
#
# Deduplication: one row per (ein, pn, filing_year), keeping the record with
#   the highest active_participants count (NA treated as -1 so non-NA wins).
#
# Panel variables added after stacking:
#   canonical_name  — most recent non-NA plan_name per EIN+PN
#   naics_sector    — first 2 digits of naics_code
#   gap_before      — years since prior filing for this plan (NA = first year)
#   state_changed   — TRUE if state differs from the prior year's filing
#
# Input  : RAW_DIR/ff_YYYY.csv  (25 files, 2000-2024)
# Output : data-processed/esops_panel.rds

setwd("/Users/lydiacamp/Desktop/MA UC3M/TFM/esop_us_map")
source("scripts/00_config.R")

library(tidyverse)

dir.create(PROCESSED_DIR, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Read and stack all years
# ---------------------------------------------------------------------------

results <- vector("list", length(YEARS))

for (i in seq_along(YEARS)) {
  yr   <- YEARS[i]
  path <- file.path(RAW_DIR, paste0("ff_", yr, ".csv"))
  message("Reading ", yr, " ...")

  df   <- read_csv(path, show_col_types = FALSE)
  cols <- names(df)

  # Detect schema: pre-2009 uses different address column names
  pre2009 <- "SPONS_DFE_MAIL_STR_ADDRESS" %in% cols

  addr_col  <- if (pre2009) "SPONS_DFE_MAIL_STR_ADDRESS" else "SPONS_DFE_MAIL_US_ADDRESS1"
  city_col  <- if (pre2009) "SPONS_DFE_CITY"             else "SPONS_DFE_MAIL_US_CITY"
  state_col <- if (pre2009) "SPONS_DFE_STATE"             else "SPONS_DFE_MAIL_US_STATE"
  zip_col   <- if (pre2009) "SPONS_DFE_ZIP_CODE"          else "SPONS_DFE_MAIL_US_ZIP"

  results[[i]] <- df |>
    filter(grepl("2O|2P", TYPE_PENSION_BNFT_CODE)) |>
    filter(.data[[state_col]] %in% US_STATES) |>
    transmute(
      filing_year         = yr,
      ein                 = as.character(SPONS_DFE_EIN),
      pn                  = as.character(SPONS_DFE_PN),
      plan_name           = as.character(PLAN_NAME),
      address             = as.character(.data[[addr_col]]),
      city                = as.character(.data[[city_col]]),
      state               = as.character(.data[[state_col]]),
      zip                 = as.character(.data[[zip_col]]),
      naics_code          = as.character(BUSINESS_CODE),
      active_participants = suppressWarnings(as.integer(TOT_ACTIVE_PARTCP_CNT))
    )

  rm(df)
  gc()
  message("  Kept: ", nrow(results[[i]]), " ESOP rows")
}

panel <- bind_rows(results)
rm(results)
gc()

message("\nTotal rows before deduplication: ", nrow(panel))

# ---------------------------------------------------------------------------
# 2. Deduplicate to one row per (ein, pn, filing_year)
#    Keep the record with the highest active_participants; ties go to first row.
# ---------------------------------------------------------------------------

panel <- panel |>
  arrange(ein, pn, filing_year,
          desc(coalesce(active_participants, -1L))) |>
  group_by(ein, pn, filing_year) |>
  slice_head(n = 1) |>
  ungroup()

message("Rows after deduplication:        ", nrow(panel))
message("Unique EIN+PN plans:             ", nrow(distinct(panel, ein, pn)))

# ---------------------------------------------------------------------------
# 3. Add panel-level variables
# ---------------------------------------------------------------------------

panel <- panel |>
  # canonical_name: most recent non-NA plan_name per EIN+PN
  arrange(ein, pn, filing_year) |>
  group_by(ein, pn) |>
  mutate(
    canonical_name = last(plan_name[!is.na(plan_name)]),
    gap_before     = filing_year - lag(filing_year),   # NA for first year
    state_changed  = !is.na(lag(state)) & state != lag(state)
  ) |>
  ungroup() |>
  # naics_sector: first 2 digits of 6-digit NAICS code
  mutate(
    naics_sector = if_else(
      !is.na(naics_code) & nchar(naics_code) >= 2,
      substr(naics_code, 1, 2),
      NA_character_
    )
  ) |>
  # Reorder columns cleanly
  select(
    ein, pn, filing_year,
    plan_name, canonical_name,
    address, city, state, zip,
    naics_code, naics_sector,
    active_participants,
    gap_before, state_changed
  )

# ---------------------------------------------------------------------------
# 4. Diagnostics
# ---------------------------------------------------------------------------

message("\n--- Coverage ---")
message("Years:            ", min(panel$filing_year), "-", max(panel$filing_year))
message("Plan-year rows:   ", nrow(panel))
message("Unique plans:     ", nrow(distinct(panel, ein, pn)))
message("Plans filing 1yr: ", sum(table(paste(panel$ein, panel$pn)) == 1))

message("\n--- Address fill rates ---")
message("  address:  ", round(100 * mean(!is.na(panel$address) & panel$address != ""), 1), "%")
message("  city:     ", round(100 * mean(!is.na(panel$city)    & panel$city    != ""), 1), "%")
message("  state:    ", round(100 * mean(!is.na(panel$state)   & panel$state   != ""), 1), "%")
message("  zip:      ", round(100 * mean(!is.na(panel$zip)     & panel$zip     != ""), 1), "%")

message("\n--- active_participants ---")
message("  Non-NA:   ", round(100 * mean(!is.na(panel$active_participants)), 1), "%")

message("\n--- naics_code ---")
message("  Non-NA:   ", round(100 * mean(!is.na(panel$naics_code) & panel$naics_code != ""), 1), "%")

message("\n--- gap_before ---")
message("  Plans with at least one gap >= 2 yrs: ",
        panel |> filter(!is.na(gap_before) & gap_before >= 2) |>
          distinct(ein, pn) |> nrow())

message("\n--- state_changed events ---")
message("  TRUE: ", sum(panel$state_changed, na.rm = TRUE))

message("\nRows per year:")
panel |>
  count(filing_year) |>
  print(n = 25)

# ---------------------------------------------------------------------------
# 5. Save
# ---------------------------------------------------------------------------

saveRDS(panel, file.path(PROCESSED_DIR, "esops_panel.rds"))
message("\nSaved: data-processed/esops_panel.rds")
