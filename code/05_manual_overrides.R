# 05_manual_overrides.R
#
# Manual corrections for specific plans where the Form 5500 address on file
# is unusable for geocoding (e.g. a P.O. Box) but a real address is known.
# Applied after 02_geocode.R and before 03_export_web.R / 04_export_search_index.R
# so corrections survive a full pipeline rerun from raw data.
#
# Each override is keyed by (ein, pn) and patches address/city/state/zip/lat/lng
# across all of that plan's rows in the panel.
#
# Input  : docs/data/esops_panel_geo.rds
# Output : docs/data/esops_panel_geo.rds  (overwritten in place)

setwd("/Users/lydiacamp/Desktop/MA UC3M/TFM/esop_us_map")
source("code/00_config.R")

library(tidyverse)

panel <- readRDS(file.path(PROCESSED_DIR, "esops_panel_geo.rds"))

# ---------------------------------------------------------------------------
# Overrides table
#
# Steel Dynamics Inc. ESOP (ein 561909053, pn 001): Form 5500 filings list a
# P.O. Box (PO BOX 58818, RALEIGH, NC), which never geocodes. Replaced with
# the company's real HQ street address. Census Geocoder couldn't match this
# address (TIGER/Line gap); geocoded via OSM/Nominatim instead
# (lat/lng verified against Steel Dynamics' known Fort Wayne, IN HQ).
# ---------------------------------------------------------------------------

overrides <- tribble(
  ~ein,        ~pn,    ~address,                   ~city,          ~state, ~zip,     ~lat,      ~lng,        ~geocode_method,
  "561909053", "001",  "7575 W Jefferson Blvd",     "Fort Wayne",   "IN",   "46804",  41.040506, -85.237635,  "manual_override"
)

message("Applying ", nrow(overrides), " manual override(s)...")

panel <- panel |>
  rows_update(overrides, by = c("ein", "pn"), unmatched = "ignore")

message("Rows affected per override:")
overrides |>
  select(ein, pn) |>
  left_join(panel |> count(ein, pn), by = c("ein", "pn")) |>
  print()

saveRDS(panel, file.path(PROCESSED_DIR, "esops_panel_geo.rds"))
message("\nSaved: ", file.path(PROCESSED_DIR, "esops_panel_geo.rds"))
