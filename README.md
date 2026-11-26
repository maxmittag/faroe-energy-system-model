# Faroe Islands without oil: local build-out or an import cable?

Group project in the CBS course *Energy System Economics and Modelling* (2026).

A linear capacity expansion model in Julia/JuMP for the Faroese main grid. It asks what it costs per year to run the
grid for one full year **without oil**, and how an **import cable to Iceland** (or Scotland) changes the new wind,
solar and storage that has to be built. Brownfield capacity expansion (course reader ch. 7) with a two-zone transport
model for the cable (reader ch. 6.4), one year in hourly steps (Oct 2025 to Sep 2026).

## Run it

Needs [Julia](https://julialang.org/downloads) 1.10 or newer (tested with 1.13.1). All data is included.

```
julia --project=. -e "using Pkg; Pkg.instantiate()"   # once: installs the pinned packages (JuMP, HiGHS, CSV, DataFrames)
julia --project=. run.jl                              # all scenarios, about 20-25 min
julia --project=. run.jl is_2030                      # only the main set (Iceland, 2030 demand), about 5 min
julia --project=. run.jl is_2030 outage_hours=1344 backup=oil   # change settings (key=value)
```

All settings and their defaults (cable losses 3.5 %, cable outage, backup during the outage, output folder) are in
`src/config.jl`; see [docs/model.md](docs/model.md#settings).

Results are written to `results/` (one row per case: cost, new capacities, imports, cost split and checks).
Sets: `is_2030`, `gb_2030`, `is_today`, `gb_today` (`is` = Iceland, `gb` = Scotland).

## Structure

```
run.jl              entry point: runs the scenarios, writes results/
src/model.jl        the model: data loading, parameters, variables, objective, constraints
src/report.jl       result table and checks (energy balance, oil = 0, cost components = objective)
src/config.jl       all settings with their defaults
data/processed/     the CSV files the model reads (see data/README.md)
data/raw/           original downloads (SEV, Copernicus C3S, Elma, Elexon) with sources and licences
pipeline/           Python scripts that turn data/raw into data/processed (optional, outputs are included)
results/            model results
docs/model.md       equations, all assumptions with sources, limitations
```

## Data pipeline (optional)

The processed files are included, so this is only needed to check how they were made. Python 3.10+,
`pip install -r requirements.txt`, then from the repository root:

```
python pipeline/1_prepare_base.py       # SEV + Elma -> demand, hydro inflow, biogas, Iceland price, SEV wind profile
python pipeline/2_add_c3s_profiles.py   # Copernicus C3S wind and solar profiles -> input_today_iceland.csv
python pipeline/3_add_gb_price.py       # Elexon GB price -> input_today_scotland.csv
python pipeline/4_scale_demand_2030.py  # demand x 1.186 -> input_2030_*.csv
```

The scripts reproduce the files in `data/processed/` byte for byte. `pipeline/download/` documents how the raw data was
downloaded; it is not needed.

## Main assumptions

- One model year for all hourly data: 1 Oct 2025 to 30 Sep 2026.
- No oil in any hour; demand is met in every hour.
- The cable only imports. The neighbour delivers any amount up to the cable size at its hourly day-ahead price
  (Iceland: Elma; Scotland: Elexon GB price).
- 2030 demand = today's hourly profile x 1.186 (578.5 GWh, peak 92.6 MW).
- Existing wind farms use SEV output / installed capacity; new wind and solar use weather-based capacity factors
  from Copernicus C3S.
- Costs from the Danish Energy Agency technology catalogues (Faroe-specific solar costs from Tróndheim et al., 2021);
  5 % discount rate.
- Cable 450 km to Iceland, 400 km to Scotland; cost = fixed part + part per MW (Härtel et al., 2017, x 1.6);
  3.5 % losses; optional outage of the cable in the worst weeks of the year.

The full list with sources is in [docs/model.md](docs/model.md).

## Data sources

SEV (Faroese utility, hourly production per plant) · Copernicus Climate Change Service (ERA5-based capacity
factors, CC BY 4.0) · Elma (Icelandic day-ahead market) · European Central Bank (exchange rates) · Elexon BMRS
(GB market index price) · Danish Energy Agency Technology Data. Details and attribution: [data/README.md](data/README.md).

Code: MIT licence (see `LICENSE`). Data: see the licences of the sources.
