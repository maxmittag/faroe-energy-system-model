# Results

Written by `julia --project=. run.jl`. One file per scenario set (`summary_<set>.csv`, one row per case) and
`summary_2030.csv` / `summary_today.csv` (both neighbours together).

Main columns: `cost_MEUR` (extra system cost per year, M EUR), `ntc_MW` (cable size), `new_wind_MW`, `new_pv_MW`,
`new_bat_MW` / `new_bat_MWh`, `new_phs_MW`, `import_GWh`, `curtail_share`, cost split `c_*_MEUR`.
Checks (must be ~0): `check_cost_sum_err_EUR`, `check_balance_err_max_MW`, `check_oil_max_MW`, `check_export_max_MW`.
