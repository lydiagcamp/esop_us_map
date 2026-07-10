# 04_export_search_index.R
#
# Export a single all-years search index for the map's ESOP name lookup.
# One row per unique plan (ein, pn), using that plan's first filing year
# (yr1) location so the year-slider and pin position stay consistent when
# a search result is selected. Plans with no geocoded location in yr1 are
# still included (marked with has_loc = false) so they remain searchable
# by name, but the front end disables map-jump behavior for them.
#
# Input  : docs/data/esops_panel_geo.rds
# Output : docs/data/esop_search_index.js

setwd("/Users/lydiacamp/Desktop/MA UC3M/TFM/esop_us_map")
source("code/00_config.R")

library(tidyverse)
library(jsonlite)

panel <- readRDS(file.path(PROCESSED_DIR, "esops_panel_geo.rds"))

year_range <- panel |>
  group_by(ein, pn) |>
  summarise(yr1 = min(filing_year), yr2 = max(filing_year), .groups = "drop")

first_year_rows <- panel |>
  inner_join(year_range, by = c("ein", "pn")) |>
  filter(filing_year == yr1) |>
  arrange(ein, pn, desc(coalesce(active_participants, -1L))) |>
  group_by(ein, pn) |>
  slice_head(n = 1) |>
  ungroup()

index <- first_year_rows |>
  transmute(
    id      = paste(ein, pn, sep = "-"),
    n       = coalesce(canonical_name, plan_name),
    c       = city,
    s       = state,
    lat     = round(lat, 4),
    lng     = round(lng, 4),
    yr1     = yr1,
    yr2     = yr2,
    has_loc = !is.na(lat),
    w       = website
  ) |>
  filter(!is.na(n) & n != "") |>
  distinct(id, .keep_all = TRUE) |>
  arrange(n)

message("Search index entries: ", nrow(index))

js_out <- paste0(
  "window.ESOP_SEARCH_INDEX=",
  toJSON(index, auto_unbox = TRUE, na = "null"),
  ";"
)

out_path <- file.path(DOCS_DATA_DIR, "esop_search_index.js")
writeLines(js_out, out_path)

size_kb <- round(file.size(out_path) / 1024, 1)
message("Wrote ", out_path, " — ", size_kb, " KB")
