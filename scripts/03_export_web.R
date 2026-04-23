# 03_export_web.R
#
# Export one JS file per year (2000-2024) for the interactive map.
# Each point now carries: lat, lng, plan_name, city, state,
# industry group (g), and the plan's first/last year in the dataset (yr1, yr2).
#
# Industry grouping (10 groups, non-standard NAICS codes → Other):
#   Manufacturing               : 31, 32, 33
#   Professional & Technical    : 54
#   Finance & Insurance         : 52
#   Wholesale & Retail          : 42, 44, 45
#   Construction                : 23
#   Business Services           : 55, 56
#   Health, Education & Arts    : 61, 62, 71, 72
#   Transportation & Utilities  : 22, 48, 49
#   Information                 : 51
#   Other                       : everything else
#
# Input  : data-processed/esops_panel_geo.rds
# Output : docs/data/esop_YYYY.js  (25 files)

setwd("/Users/lydiacamp/Desktop/MA UC3M/TFM/esop_us_map")
source("scripts/00_config.R")

library(tidyverse)
library(jsonlite)

dir.create(DOCS_DATA_DIR, showWarnings = FALSE, recursive = TRUE)

panel <- readRDS(file.path(PROCESSED_DIR, "esops_panel_geo.rds"))
message("Panel rows: ", nrow(panel))

# ---------------------------------------------------------------------------
# 1. Assign industry group
# ---------------------------------------------------------------------------

sector_to_group <- c(
  "31" = "Manufacturing",
  "32" = "Manufacturing",
  "33" = "Manufacturing",
  "54" = "Professional & Technical Services",
  "52" = "Finance & Insurance",
  "42" = "Wholesale & Retail",
  "44" = "Wholesale & Retail",
  "45" = "Wholesale & Retail",
  "23" = "Construction",
  "55" = "Business Services",
  "56" = "Business Services",
  "22" = "Transportation & Utilities",
  "48" = "Transportation & Utilities",
  "49" = "Transportation & Utilities",
  "51" = "Information",
  "61" = "Health, Education & Arts",
  "62" = "Health, Education & Arts",
  "71" = "Health, Education & Arts",
  "72" = "Health, Education & Arts"
)

panel <- panel |>
  mutate(
    industry_group = coalesce(sector_to_group[naics_sector], "Other")
  )

# ---------------------------------------------------------------------------
# 2. Compute first and last year each plan appears in the dataset
# ---------------------------------------------------------------------------

year_range <- panel |>
  group_by(ein, pn) |>
  summarise(
    yr1 = min(filing_year), yr2 = max(filing_year), .groups = "drop"
  )

panel <- panel |> left_join(year_range, by = c("ein", "pn"))

message("Industry group distribution:")
print(count(panel, industry_group, sort = TRUE))

# ---------------------------------------------------------------------------
# 3. Export one JS file per year
# ---------------------------------------------------------------------------

total_size <- 0

for (yr in YEARS) {
  yr_data <- panel |> filter(filing_year == yr)

  pts <- yr_data |>
    filter(!is.na(lat)) |>
    transmute(
      lat = round(lat, 4),
      lng = round(lng, 4),
      n   = plan_name,
      c   = city,
      s   = state,
      g   = industry_group,
      yr1 = yr1,
      yr2 = yr2
    )

  payload <- list(
    points  = pts,
    total   = nrow(yr_data),
    visible = nrow(pts),
    no_loc  = sum(is.na(yr_data$lat))
  )

  js_out <- paste0(
    "window.ESOP_CURRENT=",
    toJSON(payload, auto_unbox = TRUE, na = "null"),
    ";"
  )

  out_path <- file.path(DOCS_DATA_DIR, paste0("esop_", yr, ".js"))
  writeLines(js_out, out_path)

  size_kb <- round(file.size(out_path) / 1024, 1)
  total_size <- total_size + file.size(out_path)
  message(yr, ": ", nrow(pts), " points — ", size_kb, " KB")
}

message("\nTotal data size: ", round(total_size / 1024 / 1024, 1), " MB uncompressed")
message("Done.")
