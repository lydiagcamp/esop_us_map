# 06_join_nceo_links.R
#
# Joins company website URLs from the NCEO dataset onto the panel by EIN,
# so the map can show a clickable company name when a website is on file.
# Applied after 05_manual_overrides.R and before 03_export_web.R /
# 04_export_search_index.R so the website field is present in every export.
#
# NCEO data has no plan-number granularity, so the join is EIN-only: a
# company's website applies to all of that EIN's plans in the panel. Of the
# 84 EINs that appear on multiple NCEO rows, none disagree on the URL, so a
# simple distinct-by-EIN mapping is unambiguous (no tie-break rule needed).
# Rows with the literal placeholder "no website found" are treated as missing.
#
# Input  : docs/data/esops_panel_geo.rds
#          ../archives/unique_inputs/NCEO Data/nceo/nceo.csv
# Output : docs/data/esops_panel_geo.rds  (overwritten in place, adds `website`)

setwd("/Users/lydiacamp/Desktop/MA UC3M/TFM/esop_us_map")
source("code/00_config.R")

library(tidyverse)

NCEO_PATH <- "../archives/unique_inputs/NCEO Data/nceo/nceo.csv"

panel <- readRDS(file.path(PROCESSED_DIR, "esops_panel_geo.rds"))
nceo <- read_csv(NCEO_PATH, show_col_types = FALSE)

links <- nceo |>
  transmute(
    ein = `Sponsor company EIN`,
    website = str_trim(`Company Website`)
  ) |>
  filter(!is.na(website), website != "", website != "no website found") |>
  mutate(
    website = if_else(str_detect(website, "^https?://", negate = TRUE),
                       paste0("https://", website), website)
  ) |>
  distinct(ein, website)

message("Unique EINs with a website: ", n_distinct(links$ein))

panel <- panel |>
  left_join(links, by = "ein")

message("Panel rows with a website matched: ", sum(!is.na(panel$website)),
        " / ", nrow(panel))

saveRDS(panel, file.path(PROCESSED_DIR, "esops_panel_geo.rds"))
message("\nSaved: ", file.path(PROCESSED_DIR, "esops_panel_geo.rds"))
