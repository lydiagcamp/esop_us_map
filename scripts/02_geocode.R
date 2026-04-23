# 02_geocode.R
#
# Geocode unique mailing addresses from the ESOP panel using the Census Geocoder
# batch API (via tidygeocoder). Fall back to ZIP centroid (zipcodeR) when:
#   - the address is a P.O. Box (Census Geocoder cannot place these)
#   - the Census Geocoder returns no match
#
# Strategy:
#   1. Deduplicate 171K panel rows to unique (address, city, state, zip) — 41K addrs.
#   2. Flag P.O. Boxes; skip Census for these, use ZIP centroid directly.
#   3. Send remaining addresses to Census in manual batches of 9,000.
#   4. ZIP centroid fallback for PO Boxes + Census no-matches.
#   5. Join results back to full panel via address key.
#
# geocode_method values:
#   "address"      — Census Geocoder matched
#   "zip_centroid" — fell back to ZIP centroid (PO Box or no Census match)
#   NA             — no match from either source
#
# Input  : data-processed/esops_panel.rds
# Output : data-processed/esops_panel_geo.rds

setwd("/Users/lydiacamp/Desktop/MA UC3M/TFM/esop_us_map")
source("scripts/00_config.R")

library(tidyverse)
library(tidygeocoder)
library(zipcodeR)

panel <- readRDS(file.path(PROCESSED_DIR, "esops_panel.rds"))
message("Panel rows: ", nrow(panel))

# ---------------------------------------------------------------------------
# 1. Build unique address table with a stable integer key
# ---------------------------------------------------------------------------

unique_addrs <- panel |>
  distinct(address, city, state, zip) |>
  mutate(addr_id = row_number())

message("Unique address combos: ", nrow(unique_addrs))

# ---------------------------------------------------------------------------
# 2. Clean addresses and flag P.O. Boxes
#    Pattern uses [. ]* (literal dot or space) which works in base R grepl().
# ---------------------------------------------------------------------------

PO_BOX_PATTERN <- "P[. ]*O[. ]*BOX|POST OFFICE"

unique_addrs <- unique_addrs |>
  mutate(
    address_clean = str_squish(address),
    city_clean    = str_squish(city),
    # 5-digit ZIP for Census (handles ZIP+4 input but 5-digit is safer)
    zip5          = str_extract(as.character(zip), "^\\d{5}"),
    is_po_box     = grepl(PO_BOX_PATTERN, address_clean, ignore.case = TRUE)
  )

n_po  <- sum(unique_addrs$is_po_box)
n_geo <- nrow(unique_addrs) - n_po
message("P.O. Box addresses (ZIP centroid fallback): ", n_po)
message("Addresses to send to Census Geocoder:       ", n_geo)

# ---------------------------------------------------------------------------
# 3. Census Geocoder — manual batching (API limit is 10,000 per request)
# ---------------------------------------------------------------------------

to_geocode <- unique_addrs |>
  filter(!is_po_box) |>
  select(addr_id, address_clean, city_clean, state, zip5)

BATCH_SIZE <- 9000
n_batches  <- ceiling(nrow(to_geocode) / BATCH_SIZE)
message("\nSending to Census Geocoder: ", n_batches, " batches of up to ", BATCH_SIZE, " ...")

census_batches <- vector("list", n_batches)

for (b in seq_len(n_batches)) {
  start <- (b - 1) * BATCH_SIZE + 1
  end   <- min(b * BATCH_SIZE, nrow(to_geocode))
  message("  Batch ", b, "/", n_batches, " (rows ", start, "-", end, ") ...")

  census_batches[[b]] <- to_geocode[start:end, ] |>
    geocode(
      street     = address_clean,
      city       = city_clean,
      state      = state,
      postalcode = zip5,
      method     = "census",
      lat        = lat,
      long       = lng
    )

  n_hit <- sum(!is.na(census_batches[[b]]$lat))
  message("    Matched: ", n_hit, " / ", end - start + 1)
}

census_result <- bind_rows(census_batches)

n_matched  <- sum(!is.na(census_result$lat))
n_no_match <- sum( is.na(census_result$lat))
message("\nCensus Geocoder total:")
message("  Matched:  ", n_matched,  " (", round(100 * n_matched  / nrow(census_result), 1), "%)")
message("  No match: ", n_no_match, " (", round(100 * n_no_match / nrow(census_result), 1), "%)")

# ---------------------------------------------------------------------------
# 4. ZIP centroid fallback for PO Boxes + Census no-matches
# ---------------------------------------------------------------------------

zip_centroids <- suppressWarnings(zip_code_db) |>
  select(zipcode, lat_centroid = lat, lng_centroid = lng) |>
  filter(!is.na(lat_centroid), !is.na(lng_centroid))

message("\nZIP centroid database: ", nrow(zip_centroids), " entries")

po_box_rows   <- unique_addrs |> filter(is_po_box)  |> select(addr_id, zip5)
no_match_rows <- census_result |> filter(is.na(lat)) |> select(addr_id, zip5)

fallback_needed <- bind_rows(po_box_rows, no_match_rows)

fallback_result <- fallback_needed |>
  left_join(zip_centroids, by = c("zip5" = "zipcode")) |>
  rename(lat = lat_centroid, lng = lng_centroid) |>
  mutate(geocode_method = if_else(!is.na(lat), "zip_centroid", NA_character_))

n_zip_hit <- sum(!is.na(fallback_result$lat))
n_no_loc  <- sum( is.na(fallback_result$lat))
message("ZIP centroid fallback:")
message("  Located:     ", n_zip_hit)
message("  No location: ", n_no_loc)

# ---------------------------------------------------------------------------
# 5. Combine into one geocoding lookup table
# ---------------------------------------------------------------------------

census_hits <- census_result |>
  filter(!is.na(lat)) |>
  select(addr_id, lat, lng) |>
  mutate(geocode_method = "address")

fallback_hits <- fallback_result |>
  filter(!is.na(lat)) |>
  select(addr_id, lat, lng, geocode_method)

no_location <- fallback_result |>
  filter(is.na(lat)) |>
  select(addr_id) |>
  mutate(lat = NA_real_, lng = NA_real_, geocode_method = NA_character_)

geocode_lookup <- bind_rows(census_hits, fallback_hits, no_location)

message("\n--- Final geocoding summary ---")
message("  Census address match: ", nrow(census_hits))
message("  ZIP centroid:         ", nrow(fallback_hits))
message("  No location:          ", nrow(no_location))
message("  Total unique addrs:   ", nrow(geocode_lookup))

# ---------------------------------------------------------------------------
# 6. Join geocoding back to the full panel
# ---------------------------------------------------------------------------

unique_addrs_geo <- unique_addrs |>
  left_join(geocode_lookup, by = "addr_id")

panel_geo <- panel |>
  left_join(
    unique_addrs_geo |> select(address, city, state, zip, lat, lng, geocode_method),
    by = c("address", "city", "state", "zip")
  )

message("\n--- Panel geocoding coverage ---")
message("  Total rows:     ", nrow(panel_geo))
message("  Geocoded (any): ", sum(!is.na(panel_geo$lat)),
        " (", round(100 * mean(!is.na(panel_geo$lat)), 1), "%)")
message("  Census address: ", sum(panel_geo$geocode_method == "address",      na.rm = TRUE))
message("  ZIP centroid:   ", sum(panel_geo$geocode_method == "zip_centroid", na.rm = TRUE))
message("  No location:    ", sum(is.na(panel_geo$lat)))

# ---------------------------------------------------------------------------
# 7. Save
# ---------------------------------------------------------------------------

saveRDS(panel_geo, file.path(PROCESSED_DIR, "esops_panel_geo.rds"))
message("\nSaved: data-processed/esops_panel_geo.rds")
