# ESOP Plans in the United States

Interactive map and panel dataset of Employee Stock Ownership Plans (ESOPs) in the United States, 2000–2024, built from Form 5500 annual filings submitted to the U.S. Department of Labor.


[Form 5500](https://www.dol.gov/agencies/ebsa/employers-and-advisers/plan-administration-and-compliance/reporting-and-filing/form-5500) is an annual filing required by the U.S. Department of Labor for employer-sponsored benefit plans. This project extracts all plans coded as ESOPs (Type of Pension Benefit Code `2O` or `2P`) filed between 2000 and 2024, geocodes their mailing addresses, and visualizes them on an interactive map.

**Live map:** https://lydiagcamp.github.io/esop_us_map

---

## Dataset

`data/esops_panel_geo.rds` · `data/esops_panel_geo.csv`

An unbalanced plan-year panel of **171,911 observations** covering **19,968 unique ESOP plans** across all 50 U.S. states. Plans enter and exit the panel as they are established or terminated; the average plan is observed for 8.6 years.

| Column | Description |
|---|---|
| `ein` | Employer Identification Number |
| `pn` | Plan number |
| `filing_year` | Year of Form 5500 filing |
| `plan_name` | Plan name as reported in that year's filing |
| `canonical_name` | Most recent non-null plan name across all filings |
| `address` | Sponsor mailing address |
| `city` | City |
| `state` | State (2-letter abbreviation) |
| `zip` | ZIP code |
| `naics_code` | 6-digit NAICS industry code |
| `naics_sector` | First 2 digits of NAICS code |
| `active_participants` | Number of active plan participants |
| `gap_before` | Years since prior filing for this plan (NA = first observed year) |
| `state_changed` | Whether the sponsor state differs from the prior year's filing |
| `lat` | Latitude |
| `lng` | Longitude |
| `geocode_method` | `"address"` = Census Geocoder match; `"zip_centroid"` = ZIP centroid fallback; `NA` = no location found |

### Geocoding coverage

| Method | Observations |
|---|---|
| Census address match | 133,012 (77.4%) |
| ZIP centroid fallback | 26,652 (15.5%) |
| No location | 12,247 (7.1%) |

Addresses were geocoded using the [U.S. Census Bureau Geocoder](https://geocoding.geo.census.gov/) batch API. P.O. boxes and unmatched addresses fell back to ZIP code centroids via [zipcodeR](https://github.com/gavinrozzi/zipcodeR).

---

## Repository structure

```
docs/          # GitHub Pages site (map + per-year data files)
data/          # Downloadable dataset (RDS + CSV)
scripts/       # R pipeline scripts
```

---

## Data source

U.S. Department of Labor, Employee Benefits Security Administration —
[Form 5500 Series](https://www.dol.gov/agencies/ebsa/employers-and-advisers/plan-administration-and-compliance/reporting-and-filing/form-5500).

---

## Author

Lydia Camp · [lydiagcamp.github.io](https://lydiagcamp.github.io)
