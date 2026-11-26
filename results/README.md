# Results

Written by `julia --project=. run.jl`. One file per scenario set (`summary_<set>.csv`, one row per case) and
`summary_2030.csv` / `summary_today.csv` (both neighbours together).

Main columns: `cost_MEUR` (extra system cost per year, M EUR), `ntc_MW` (cable size), `new_wind_MW`, `new_pv_MW`,
`new_bat_MW` / `new_bat_MWh`, `new_phs_MW`, `import_GWh`, `curtail_share`, cost split `c_*_MEUR`.
Checks (must be ~0): `check_cost_sum_err_EUR`, `check_balance_err_max_MW`, `check_oil_max_MW`, `check_export_max_MW`.

## Cable reliability runs (Lukas' PR1 + PR2, 2030 sets)

`summary_*.csv` in this folder use the defaults of `src/config.jl` (3.5 % cable losses, no outage, Härtel cable cost).

| Folder | Settings |
|---|---|
| `test_isolation/` | `cable_loss=0 outage_hours=0`: only the new cable cost (PR2 test) |
| `outage4w_green/` | 4-week outage (672 h, from 7 Nov 2025), local green backup |
| `outage8w_green/` | 8-week outage (1,344 h, from 15 Apr 2026), local green backup |
| `outage8w_oil/` | 8-week outage, Sund oil plant as backup at 150 EUR/MWh (placeholder) |
