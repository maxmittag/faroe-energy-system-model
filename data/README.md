# Data

Everything the model needs is in this folder. Nothing has to be downloaded.

## `processed/`: what the model reads

| File | Content |
|---|---|
| `input_2030_iceland.csv` | main case: 2030 demand, Iceland price |
| `input_2030_scotland.csv` | 2030 demand, Scotland (GB) price |
| `input_today_iceland.csv` | today's demand, Iceland price |
| `input_today_scotland.csv` | today's demand, Scotland (GB) price |
| `base_sev_elma.csv` | step 1 output. The model takes the wind/solar availability of the **existing** farms from here (SEV output / installed capacity) |
| `technologies.csv` | costs (DEA catalogues, 2030, EUR2020; step 6, see `docs/cost_data.md`), lifetimes, efficiencies and existing capacities, with the source of every row |
| `checks/` | printed checks of the preparation steps (yearly sums, monthly tables, cleaning log) |

Every hourly file has 8,760 rows (1 Oct 2025 00:00 to 30 Sep 2026 23:00, UTC) and the columns
`hour, time_utc, demand` (MW), `ava_wind, ava_pv` (capacity factor 0-1), `hydro_inflow` (MWh per hour),
`biogas` (MW, fixed), `pi` (import price, EUR/MWh), `ava_wind_pc` (power-curve wind capacity factor, step 5). The four `input_*` files differ only in `demand` (2030 = today x 1.186)
and `pi` (Iceland or Scotland).

The `pipeline/` scripts rebuild all of these from `raw/` and give byte-identical files.

## `raw/`: original downloads

| Folder | Data | Source | Used for |
|---|---|---|---|
| `sev/` | hourly production per power plant, Jan 2023 to Oct 2026 (gzip) | SEV, Faroese utility and grid operator, public endpoint behind sev.fo (same source as Electricity Maps). Retrieved 15 Oct 2026 | demand, hydro inflow, biogas, availability of existing wind |
| `c3s/` | hourly onshore wind and solar PV capacity factors, Oct 2025 to Sep 2026 (one file per month; the model uses grid cell 62.25 N / 6.75 W) | Copernicus Climate Change Service (C3S), *Climate and energy indicators for Europe from 1979 to present derived from reanalysis* (ERA5 based), dataset `sis-energy-derived-reanalysis` | availability of new wind and solar |
| `elma/` | Iceland day-ahead prices and volumes, hourly, Mar 2025 to Oct 2026, plus ECB daily ISK/EUR and USD/EUR rates | Elma (Icelandic power exchange), elma.is; European Central Bank, data-api.ecb.europa.eu | Iceland import price |
| `era5/` | hourly wind speed at 100 m, Oct 2025 to Sep 2026 (`era5_wind_speed_100m_hourly.csv`: `time_utc`, `wind_speed_100m` in m/s) at 62.06 N / 6.85 W (central Streymoy, Húsahagi/Neshagi area; Open-Meteo snaps to its nearest grid point, 62.11 N / 6.96 W, 176 m) | ERA5 reanalysis (Copernicus/ECMWF) via the Open-Meteo historical weather API, `archive-api.open-meteo.com/v1/archive?latitude=62.06&longitude=-6.85&hourly=wind_speed_100m&wind_speed_unit=ms`. Retrieved Oct 2026, cut to the model year | availability of new wind (`ava_wind_pc`) |
| `elexon/` | GB Market Index Data, half-hourly (gzip) | Elexon BMRS, data.elexon.co.uk | Scotland import price |
| `dea/` | Danish Energy Agency *Technology Data* catalogues, official files unchanged: `technology_data_for_el_and_dh - 0019.xlsx` (electricity and district heating, version 0019) and `technology_datasheet_for_energy_storage - 0011.xlsx` (energy storage, version 0011) | Danish Energy Agency (Energistyrelsen), https://ens.dk/media/8615/download and https://ens.dk/media/6589/download (shared in the group by Connor, same versions) | `technologies.csv` via `pipeline/6_technologies_from_dea.py` (see `docs/cost_data.md`) |

## Licences and attribution

- **C3S:** CC BY 4.0. *Generated using Copernicus Climate Change Service information (2026). Neither the European
  Commission nor ECMWF is responsible for any use that may be made of the Copernicus information or data it contains.*
- **ERA5 / Open-Meteo:** CC BY 4.0. *Contains modified Copernicus Climate Change Service information (2026)*; weather data by Open-Meteo.com.
- **Elexon:** *Contains BMRS data © Elexon Limited copyright and database right 2026*, used under the BMRS Data Licence.
- **ECB:** reuse permitted with the source named (European Central Bank).
- **SEV, Elma:** publicly accessible on the providers' websites; no licence is stated. Included here only so that this
  non-commercial student project can be reproduced. Source: SEV (sev.fo), Elma (elma.is).
- **DEA (`raw/dea/`):** CC BY 4.0 (stated on the front page of both files). *Source: Danish Energy Agency, Technology
  Data for Generation of Electricity and District Heating (version 0019) and Technology Data for Energy Storage
  (version 0011).* The files are included unchanged.
- **Cost data in `technologies.csv`**: DEA catalogues above (wind, solar PV, Li-ion battery, pumped hydro);
  Ea Energy Analyses (2018) for the hydro reservoir; SEV plant list for existing capacities.

## Known weaknesses of the data

- SEV output is **curtailed** wind (capacity factor 0.27 in the model year). It is used only for the existing farms.
- The C3S wind capacity factor (0.64) is high: one 0.25° grid cell, a fixed 100 m turbine, no wake or availability losses.
- Elma is a thin market (median about 35 MWh traded per hour). Its price is taken as given for any import volume.
- The GB price is the national price (incl. negative hours), converted at a fixed 1.16 EUR/GBP.
- Hydro inflow = SEV hydro production per month (not natural inflow), spread evenly over the hours of the month.
