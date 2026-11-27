# Model description

## Question

How much new wind, solar and storage does the Faroese main grid need to run one year without oil, and how does an
import cable to Iceland (or Scotland) change the build-out and the yearly cost?

## Model

Brownfield capacity expansion model (course reader ch. 7.1-7.2) for the zone Faroe Islands (FO), plus a transport model
(reader ch. 6.4) with a second zone, the neighbour (Iceland IS or Scotland GB). The neighbour is represented only by its
hourly day-ahead price. One year, 8,760 hours, one linear program, solved with HiGHS (interior point).
Code: `src/model.jl` (equations), `src/report.jl` (result table and checks), `src/config.jl` (all settings with
their defaults), `run.jl` (scenarios).

**Sets.** $T$ hours; $P$ = {wind, pv, oil, hydro, battery, phs}; $RES$ = {wind, pv}; $DISP$ = {oil, hydro, battery, phs};
$S$ = {battery, phs} $\subset DISP$.

**Variables.** $G_{disp,t}$ output (storage: discharge); $D^{stor}_{s,t}$ charge; $L^{stor}_{s,t}$ storage level;
$CU_t$ curtailment; $CAP^G_p, CAP^D_s, CAP^L_s$ new capacity; $F_{FO,IS,t}$ export, $F_{IS,FO,t}$ import;
$L^{hyd}_t$ hydro reservoir level; $SPILL_t$ spilled water; $NTC$ cable size (only in the "size chosen by the model" cases).

**Parameters.** $d_t$ demand; $ava_{res,t}$ availability of new capacity (Copernicus C3S); $ava^{ex}_{res,t}$
availability of existing capacity (SEV output / installed capacity); $g^{max}_p, d^{max}_s, l^{max}_s$ existing capacity;
$\eta^{in}_s, \eta^{out}_s$ efficiencies; $vc_p$ variable cost; $ann_p$ annuity incl. fixed O&M; $ntc$ cable size;
$bio_t$ fixed biogas output; $inflow_t$ water into the hydro reservoir; $\pi_t$ import price; $fix_x$ fixed yearly cable
cost, $var_x$ yearly cable cost per MW; $build$ = 1 if the run has a cable, else 0 (a parameter, not a variable);
$loss$ cable losses.

**Objective** (reader 7.1, plus trade and cable):

$$\min C = \sum_{disp,t} vc_{disp} \, G_{disp,t} + \sum_{p \in \{wind,pv,battery,phs\}} ann_p \, CAP^G_p + \sum_{s} ann^L_s \, CAP^L_s + \sum_t \pi_t \,(F_{IS,FO,t} - F_{FO,IS,t}) + fix_x \cdot build + var_x \cdot ntc$$

with $ann_p = OC_p \cdot \frac{r(1+r)^{n_p}}{(1+r)^{n_p}-1} + fom_p$ and $r$ = 5 %.

**Cable cost** (Härtel et al. 2017, Eq. 2-3, average parameter set; port of Lukas' PR "Cable: losses (3.5 %) and
realistic cost", 27.11.2026), with $l$ the cable length
in km, two converter stations, $s$ = 1.6 price-level factor, $af$ the 40-year annuity factor and 1 % O&M per year:

$$fix_x = s\,(af + 0.01)\,\big(B_l\, l + B_0 + 2 N_0\big), \qquad var_x = s\,(af + 0.01)\,\big(B_{lp}\, l + 2 N_p\big)$$

$B_{lp}$ = 970 EUR/MW/km, $B_l$ = 0.68 M EUR/km, $B_0$ = 0.70 M EUR, $N_p$ = 80,880 EUR/MW per station, $N_0$ = 28.38 M EUR
per station. Iceland (450 km): $fix_x$ = 39.7 M EUR/yr, $var_x$ = 65,357 EUR/MW/yr, so 100 MW cost 46.2 M EUR/yr
(Scotland 400 km: 42.0). **Build or not** is answered by comparing a cable run with the no-cable run; this gives the
same answer as a 0/1 variable but keeps the model an LP. The size chosen by the model answers "if we build, which size?".

**Energy balance in FO** (reader 6.4; its dual is the Faroese price):

$$\sum_{disp} G_{disp,t} + \sum_{res} \left( ava^{ex}_{res,t}\, g^{max}_{res} + ava_{res,t}\, CAP^G_{res} \right) + bio_t - \sum_s D^{stor}_{s,t} - CU_t + (1 - loss)\, F_{IS,FO,t} - F_{FO,IS,t} = d_t \quad \forall t$$

**Constraints**

| Constraint | Equation |
|---|---|
| Output | $G_{disp,t} \le g^{max}_{disp} + CAP^G_{disp}$ |
| Charging | $D^{stor}_{s,t} \le d^{max}_s + CAP^D_s$ |
| Storage level | $L^{stor}_{s,t} \le l^{max}_s + CAP^L_s$ |
| Curtailment | $CU_t \le \sum_{res} \left( ava^{ex}_{res,t}\, g^{max}_{res} + ava_{res,t}\, CAP^G_{res} \right)$ |
| Storage balance (cyclic) | $L^{stor}_{s,t+1} = L^{stor}_{s,t} + \eta^{in}_s D^{stor}_{s,t} - G_{s,t}/\eta^{out}_s$ |
| Hydro reservoir (cyclic) | $L^{hyd}_{t+1} = L^{hyd}_t + inflow_t - G_{hydro,t} - SPILL_t$, $\;L^{hyd}_t \le l^{max}_{hydro}$ |
| Without oil | $G_{oil,t} = 0$ |
| No new hydro or oil plants | $CAP^G_{hydro} = CAP^G_{oil} = 0$ |
| Battery: one inverter | $CAP^G_{battery} = CAP^D_{battery}$ |
| Pumped hydro site | $CAP^D_{phs} = 1.75\,CAP^G_{phs}$, $\;CAP^L_{phs} = 20\,CAP^G_{phs}$, $\;CAP^G_{phs} \le 40$ |
| Cable (reader 6.4) | $F_{FO,IS,t} \le ntc$, $\;F_{IS,FO,t} \le ntc$, $\;F_{FO,IS,t} + F_{IS,FO,t} \le ntc$ |
| Import only | $F_{FO,IS,t} = 0$ |
| Cable size chosen by the model | $ntc = NTC$, $\;0 \le NTC \le cap$ (1,000 MW; Scotland 500 and 1,000 MW) |

All variables are $\ge 0$. "Cyclic" means the level in the last hour connects to the first hour.

## Settings

All settings and their defaults are in `src/config.jl` (no hidden defaults); change them on the command line, e.g.
`julia --project=. run.jl is_2030 cable_loss=0`. Cable losses and cost are a port of Lukas' PR "Cable: losses (3.5 %)
and realistic cost" (27.11.2026).

| Setting | Default | Meaning |
|---|---|---|
| `cable_loss` | 0.035 | share of the imported energy lost in cable and converters (only $1-loss$ arrives, all is paid) |
| `results_dir` | `results` | output folder |

## Scenarios

| Set | Demand | Neighbour, cable length | Cases |
|---|---|---|---|
| `is_2030` (main) | 2030 (today x 1.186) | Iceland, 450 km | no cable; 25 / 50 / 100 MW; size chosen by the model |
| `gb_2030` | 2030 | Scotland, 400 km | 25 / 50 / 100 MW; size chosen (limit 500 and 1,000 MW) |
| `is_today` | today | Iceland, 450 km | as `is_2030` |
| `gb_today` | today | Scotland, 400 km | as `gb_2030` |

## Assumptions

Type: **F** = fact from a source, **G** = group decision, **A** = own assumption.

| ID | Assumption | Value | Source | Type |
|---|---|---|---|---|
| A01 | Without oil | $G_{oil,t} = 0$ in every hour; demand met in every hour (no load shedding) | group | G |
| A02 | One model year for all hourly inputs | 1 Oct 2025 to 30 Sep 2026, 8,760 h, UTC | group; lecturer feedback | G |
| A03 | Import only | no export over the cable | group meeting 28.10.2026 | G |
| A04 | Neighbour = hourly price only | Elma (Iceland) or Elexon GB price; the neighbour always delivers up to $ntc$ at that price | Elma; Elexon | G |
| A05 | Imported power counts as renewable | Iceland's grid is almost fully hydro and geothermal | group | G |
| A06 | Demand today | sum of main-grid production per hour (no interconnector today): 487.8 GWh, peak 78.1 MW | SEV | F + A |
| A07 | Demand 2030 | today's hourly profile x 600/506 = 1.186: 578.5 GWh, peak 92.6 MW | group | G |
| A08 | Main grid only | Suðuroy (separate grid, about 7 % of Faroese demand) excluded | group | G |
| A09 | Existing wind | 61.55 MW (Neshagi 4.65, Húsahagi 11.7, Gellingaklettur 25.2, Flatnahagi 18, Vestmanna 2) | SEV plant list | F |
| A10 | Availability of existing wind | SEV output / installed capacity (capacity factor 0.27; contains curtailment) | SEV | G |
| A11 | Availability of new wind and solar | Copernicus C3S, grid cell 62.25 N / 6.75 W (wind capacity factor 0.64, solar 0.083) | C3S | F + A |
| A12 | Existing PV in the main grid | 0 MW | SEV | F |
| A13 | One profile per technology, no site limits for new wind and PV | | stylised | A |
| A14 | Existing hydro | 37.3 MW, one aggregated reservoir, 5.85 GWh usable (50 % of 11.7 GWh) | SEV plant list; Ea Energy Analyses (2018) | F |
| A15 | Hydro inflow | monthly SEV hydro production, flat within the month | SEV | F + A |
| A16 | Biogas fixed as produced; existing battery 12 MW / 12.5 MWh | | SEV | F |
| A17 | Wind cost | 1.036 M EUR/MW, fixed O&M 12,600 EUR/MW/yr, 30 yr | DEA, sheet 20, 2030 | F |
| A18 | Solar cost (Faroe-specific) | 1.11 M EUR/MW, fixed O&M 7,000 EUR/MW/yr, 30 yr | Tróndheim et al. (2021), Table 5 | F |
| A19 | Battery cost | 170 k EUR/MW + 151 k EUR/MWh, fixed O&M 574 EUR/MW/yr, 25 yr, round trip 92 % | DEA storage, sheet 180, 2030 | F |
| A20 | Pumped hydro option | 4.25 M EUR/MW, fixed O&M 8,507 EUR/MW/yr, 50 yr, round trip 75 %; max 40 MW turbine, pump 1.75 x turbine, 20 h | DEA storage, sheet 160; SEV Mýruverkið II | F |
| A21 | Storage discharge cost | 1 EUR/MWh | course model | F |
| A22 | Cable cost | fixed part + part per MW (see above), price level x 1.6, 40 yr, O&M 1 %/yr | Härtel et al. (2017), Table 1; x 1.6 own calibration to Celtic Interconnector (EIB 20180149) and Shetland HVDC Link (Shetland News 31.10.2023); O&M own assumption | F + A |
| A23 | Cable length | Iceland 450 km, Scotland 400 km | NAEN (2016), p. 9 and Table 1 | F |
| A24 | Discount rate | 5 % real | common value | A |
| A25 | Existing plants are sunk | cost = additional yearly cost of the oil-free system | reader 7.2 | A |
| A26 | Cable losses | 3.5 % of imports | North Sea Link 3.5-4 % (futurewatt.co.uk, author's estimate) | A |
| A26b | Cable outages | not modelled: the cable is always available | group decision 27.11.2026 | G |
| A27 | Curtailment free; perfect foresight over the year | | course model | F |
| A28 | No grid inside the Faroes, no frequency or inertia | | course model | F |
| A29 | Costs as published | price years differ (wind EUR2015, storage EUR2020), no inflation adjustment | DEA | A |
| A30 | GB price | Elexon Market Index (APXMIDP) x 1.16 EUR/GBP | Elexon | A |

## Limitations

- **Price-taking neighbour.** Elma is a thin market; a 25-100 MW cable is as large as its whole traded volume. The model
  assumes Iceland always delivers at that price, also in dry years. With the GB price and free cable size, the result
  only follows the size limit.
- **Wind availability.** Existing farms use curtailed SEV output (0.27), new wind the uncurtailed C3S profile (0.64).
  Both levels are uncertain; the gap drives how much new wind is built.
- **Cable cost** uses one literature formula and one price factor (1.6) calibrated on only two, much larger links.
- **Cable outages are not modelled** (group decision): the cable is always available and no backup plant is costed. A
  single subsea cable can fail for weeks (average repair about 60 days, ENTSO-E/Europacable), so the cable cases
  are optimistic on security of supply.
- **One weather year, perfect foresight, flat demand scaling** (the real 2030 profile is probably more winter-heavy).
- **No grid physics.** Frequency, inertia and reserves are not modelled; running with exactly zero oil may need extra
  equipment that is not costed.
