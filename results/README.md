# Results

Written by `julia --project=. run.jl`. One file per scenario set (`summary_<set>.csv`, one row per case) and
`summary_2030.csv` / `summary_today.csv` (both neighbours together).

Main columns: `cost_MEUR` (extra system cost per year, M EUR), `ntc_MW` (cable size), `new_wind_MW`, `new_pv_MW`,
`new_bat_MW` / `new_bat_MWh`, `new_phs_MW`, `import_GWh`, `curtail_share`, cost split `c_*_MEUR`.
Checks (must be ~0): `check_cost_sum_err_EUR`, `check_balance_err_max_MW`, `check_oil_max_MW`, `check_export_max_MW`.

## Top-level summary files

`summary_*.csv` in this folder use 3.5 % cable losses, Härtel cable cost x 1.6 and the C3S wind profile for new
wind (`wind_profile=c3s`, the default before 27.11.2026).

## Power-curve wind profile (default since 27.11.2026, 2030 sets)

| Folder | Settings |
|---|---|
| `wind_pc/` | defaults: new wind = ERA5 x V117 power curve x (1 - 12 %), capacity factor 0.41; existing wind = SEV |
| `wind_pc_both/` | `is_2030 existing_wind_profile=power_curve`: the same power-curve profile also for the existing 61.55 MW |

## Cable losses and cost test (Lukas' PR "Cable: losses (3.5 %) and realistic cost", 2030 sets, C3S wind profile)

| Folder | Settings |
|---|---|
| `test_isolation/` | `cable_loss=0`: only the new cable cost (test 1 of the PR) |

## Sensitivity: cable price factor (power-curve wind, 2030 sets, defaults otherwise)

| Folder | Settings | Result (M EUR/yr) |
|---|---|---|
| `sens_cable_scale_1.0/` | `is_2030 gb_2030 cable_scale=1.0` (unscaled Härtel formula) | no cable 40.4; Iceland size chosen 33.9 (48.8 MW), Scotland size chosen 42.7 (47.1 MW): **Iceland cable beats no cable** |
| `sens_cable_scale_2.0/` | `is_2030 gb_2030 cable_scale=2.0` | no cable 40.4; Iceland size chosen 60.5 (43.1 MW), Scotland 66.8 (37.5 MW) |
