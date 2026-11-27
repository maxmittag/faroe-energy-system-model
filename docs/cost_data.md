# Technology cost data

`data/processed/technologies.csv` is built by `pipeline/6_technologies_from_dea.py` from the two current Danish Energy
Agency (DEA) *Technology Data* catalogues in `data/raw/dea/` (official files, unchanged):

| File | Catalogue | Version | Price year (front page) |
|---|---|---|---|
| `technology_data_for_el_and_dh - 0019.xlsx` | Generation of electricity and district heating | 0019 | EUR2020; sheets 22x, 40x, 41x, 45x, 47x in EUR2025 |
| `technology_datasheet_for_energy_storage - 0011.xlsx` | Energy storage | 0011 | EUR2020; sheets 141a/b, 142 in EUR2025 |

Rule: **year 2030, central estimate (`ctrl`), all costs in EUR2020.** The script reads every number twice (from the
datasheet and from the catalogue's flat table `alldata_long` / `alldata_flat`) and stops if they differ, or if the
price year of a row is not the expected one.

```
python pipeline/6_technologies_from_dea.py     # prints every value it reads, writes technologies.csv (byte-identical on re-run)
```

## Values (2030, EUR2020)

| Technology | DEA sheet | Investment | Fixed O&M | Lifetime | Efficiency | Annual cost in the model (5 %) |
|---|---|---|---|---|---|---|
| Onshore wind | el/DH `20 Onshore turbines` | 1.147 M EUR/MW | 16,663 EUR/MW/yr | 30 yr | - | 91,254 EUR/MW/yr |
| Solar PV, utility | el/DH `22 Utility-scale PV` | 0.476 M EUR/MW (AC) | 8,457 EUR/MW/yr | 40 yr | - | 36,205 EUR/MW/yr |
| Li-ion battery | storage `180 Lithium Ion Battery` | 84 k EUR/MW + 195 k EUR/MWh | 8,091 EUR/MW/yr | 20 yr | 91 % round trip (AC) | 14,831 EUR/MW/yr + 15,647 EUR/MWh/yr |
| Pumped hydro | storage `160 Pumped hydro storage` | 4.254 M EUR/MW (turbine) | 8,507 EUR/MW/yr | 50 yr | 75 % round trip | 241,506 EUR/MW/yr |

How the DEA rows map onto the model columns:

- **PV** is the only sheet in EUR2025. Converted with the DEA's own index from note N of sheet 22
  (FM nettoprisindeks: 2020 = 0.856, 2025 = 1.000): 0.5562 M EUR2025 x 0.856 = 0.4761 M EUR2020; fixed O&M 9,880 x 0.856.
  Per MW AC (the model's PV profile is per MW of capacity; DEA DC/AC = 1.3).
- **Battery.** DEA splits the investment into a power component (0.084 M EUR/MW), an energy component (0.065 M EUR/MWh)
  and other project costs (0.13 M EUR/MWh, note M: "roughly correlate with the system size"). The model has one MW cost
  (charge = discharge, one inverter) and one MWh cost: MW = power component, MWh = energy + other. Check in the script:
  for the DEA 2030 unit (3.6 MWh / 3.6 MW) this gives exactly the DEA "Specific investment" of 0.279 M EUR/MWh.
  Fixed O&M is per MW as the DEA unit says (kEUR2020/MW/year). Charge and discharge efficiency = sqrt(0.91) each.
- **Pumped hydro.** The model puts the whole cost on the turbine MW (storage MWh free, site limits 40 MW / 20 h),
  so the DEA "total, greenfield plant" value is used.
- **Wind** variable O&M (1.98 EUR/MWh) is **not** in the model: the objective only charges variable cost for
  dispatchable plants. At about 0.4 capacity factor that is about 7,000 EUR/MW/yr (about 8 % of the wind annual cost)
  left out. Small; it would need a code change (variable cost on wind output).
- Storage discharge cost stays at 1 EUR/MWh (course model tie-breaker; DEA variable O&M is 0).
- Unchanged, not DEA: oil and hydro (existing, SEV plant list), hydro reservoir (Ea Energy Analyses 2018), existing
  capacities.

## What changed (old `technologies.csv` -> new)

| Technology | Old | New | Annual cost per MW (5 %) |
|---|---|---|---|
| Wind | 1.036 M EUR/MW, FOM 12,600, 30 yr (older DEA edition, EUR2015) | 1.147 M EUR2020/MW, FOM 16,663, 30 yr | 79,993 -> 91,254 (+14 %) |
| PV | 1.11 M EUR/MW, FOM 7,000, 30 yr (Tróndheim et al. 2021, Faroe-specific) | 0.476 M EUR2020/MW, FOM 8,457, 40 yr (DEA, Danish) | 79,207 -> 36,205 (-54 %) |
| Battery MW | 170 k EUR/MW, FOM 574, 25 yr, 92 % | 84 k EUR/MW, FOM 8,091, 20 yr, 91 % | 12,636 -> 14,831 |
| Battery MWh | 151 k EUR/MWh | 195 k EUR/MWh | 10,714 -> 15,647 (+46 %) |
| Pumped hydro | 4.25 M EUR/MW, FOM 8,507 | 4.2536 M EUR/MW, FOM 8,507.2 | unchanged |

The biggest change is PV: the old Faroe-specific value (island logistics, small plants) is 2.3 x the DEA Danish
utility-scale value. Using DEA for all technologies is consistent, but probably too cheap for Faroese PV. A quick
sensitivity on PV cost would be worth adding before the report.

## Price year of the other costs (not changed here)

- **Cable (Härtel et al. 2017 x 1.6).** The factor 1.6 was calibrated on real projects (Celtic Interconnector,
  Shetland HVDC), so the cable is in roughly 2023 prices, not EUR2020. With the DEA index (2023 = 0.973, 2020 = 0.856,
  ratio 1.137), the EUR2020-consistent factor is 1.6 / 1.137 = **1.41**. The default stays 1.6 (group decision);
  the 1.41 run is in `results/sens_cable_scale_1.41_eur2020/`.
- **Import prices** (Elma, Elexon) are nominal 2025/26 market prices. Not deflated.

## Pumped hydro caveat

The storage file header says EUR2020, but sheet 160 note C says the numbers are the 2005 catalogue inflated
"from price level 2002 to 2011" (factor 1.2306), and the values are identical for 2015-2050. So in reality this is
about a 2011 price level, labelled EUR2020 by the DEA. Used as published.

## 2030 results with the new costs (defaults: power-curve wind, cable x 1.6, 3.5 % losses)

M EUR per year; full tables in `results/dea_eur2020/` (old costs: `results/wind_pc/`).

| Case | Old costs | New costs (EUR2020) | New costs, cable x 1.41 |
|---|---|---|---|
| No cable | 40.4 | 44.5 | 44.5 |
| Iceland, size chosen | 49.9 (44.2 MW) | 50.1 (49.2 MW) | 45.0 (49.2 MW) |
| Scotland, size chosen (limit 500) | 57.2 (40.1 MW) | 56.9 (36.8 MW) | 52.4 (37.4 MW) |

- No cable costs 4.1 M EUR/yr more: wind +14 % and battery MWh +46 % outweigh the cheaper PV. The no-cable system
  changes shape: PV 98 -> 249 MW, battery 1,671 -> 712 MWh, and now the full 40 MW pumped hydro is built
  (wind 168 -> 156 MW).
- The cable cases barely move (they build little wind/PV/storage): Iceland +0.2, Scotland -0.3.
- So the gap no cable vs Iceland cable shrinks from 9.5 to 5.6 M EUR/yr; with an EUR2020-consistent cable price
  (x 1.41) it is 0.5 M EUR/yr, i.e. almost break-even. No cable is still cheapest in all runs.

## Break-even cable price factor

`julia --project=. break_even.jl` searches the `cable_scale` at which the cheapest cable case (size chosen by the
model) costs as much as the no-cable system (44.53 M EUR/yr). Result: `results/break_even/break_even_cable_scale.csv`.

| Neighbour | Break-even `cable_scale` | Cable size at break-even |
|---|---|---|
| Iceland | **1.39** | 49 MW |
| Scotland | **1.08** | 39 MW |

Compared with real projects (calibration of the 1.6, roughly 2023 prices, converted to EUR2020 with / 1.137):
Celtic Interconnector about 1.7 -> 1.50, Shetland HVDC Link 1.6-1.9 -> 1.41-1.67.

- Scotland: break-even far below every reference -> a cable does not pay.
- Iceland: break-even 1.39 lies just below the lowest reference (1.41, margin about 1-2 %). Not robust on its own:
  deflating the import price to EUR2020 as well would raise the break-even to about 1.42 (estimate: trade cost
  6.35 M EUR/yr x (1 - 0.856/0.982) / 26.8 M EUR per unit of scale). Factors not in the model all push the real
  cable cost or risk up: outages without backup (repair ~60 days), a thin Elma market taken as price-taker,
  deeper and rougher route than the reference links. Faroe-specific PV costs (higher than DEA) would push the
  no-cable cost up and the break-even up as well.
