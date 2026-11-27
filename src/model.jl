# =============================================================================
#  Faroe Islands main grid without oil: brownfield capacity expansion (reader 7.1-7.2)
#  with a cable to a neighbour (Iceland or Scotland) as a transport model (reader 6.4).
#  One year, hourly, one linear program. Structure and names follow the course file
#  09_investment.jl.
#
#  Reader notation: d_t demand, G output, CU curtailment, D_stor charge, L_stor level,
#  CAP_G / CAP_D / CAP_L new capacity, g_max / d_max / l_max existing capacity,
#  ava availability, ann annuity, F_z,zz,t flow between zones, ntc transfer capacity.
#  New symbols (not in the reader): bio_t fixed biogas, inflow_t water into the hydro
#  reservoir, L_hyd hydro reservoir level, SPILL_t spilled water, pi_import_t price of
#  the neighbour, fix_x / var_x yearly cable cost: fixed part and part per MW (Härtel et al. 2017),
#  cable_loss share of the imported energy lost in cable and converters.
# =============================================================================
using JuMP
using HiGHS
using DataFrames, CSV

const DATA_DIR = joinpath(dirname(@__DIR__), "data", "processed")

annuity_factor(n, r) = r * (1 + r)^n / (((1 + r)^n) - 1)              # reader 7.1: ann = OC * af
successor(arr, x) = (x == length(arr)) ? 1 : x + 1                     # cyclic year: last hour -> first hour

"""
    load_inputs(input_file; cable_km, existing_ava_file, cfg)

Reads one hourly input file (data/processed/input_<year>_<counterpart>.csv), the technology table and
the availability for the EXISTING wind farms, and computes all parameters of the model.
`cable_km` sets the cable length (Iceland 450 km, Scotland 400 km); `cfg` holds the
settings (see src/config.jl), here the cable losses.
"""
function load_inputs(input_file::String; cable_km::Float64, existing_ava_file::String, cfg)
    time_series = CSV.read(joinpath(DATA_DIR, input_file), DataFrame)
    # Existing wind (and PV) capacity uses the availability in `existing_ava_file`. With
    # base_sev_elma.csv this is SEV output / installed capacity (current group setting); new capacity
    # always uses the Copernicus C3S profile of the input file.
    time_series_existing = CSV.read(joinpath(DATA_DIR, existing_ava_file), DataFrame)
    tech_data = CSV.read(joinpath(DATA_DIR, "technologies.csv"), DataFrame)
    tech_data.technology = String.(tech_data.technology)

    ### sets ###
    T = time_series[:, :hour] |> collect
    P = tech_data[:, :technology] |> Vector
    DISP = tech_data[tech_data[!, :dispatchable] .== 1, :technology]      # oil, hydro, battery, phs
    NONDISP = tech_data[tech_data[!, :dispatchable] .== 0, :technology]   # wind, pv (RES in the reader)
    S = ["battery", "phs"]                                                # storage, S ⊂ DISP
    INV = tech_data[tech_data[!, :can_invest] .== 1, :technology]         # may be built: wind, pv, battery, phs

    ### parameters ###
    interest_rate = 0.05
    ic_generation_cap = Dict{String,Float64}()    # EUR per MW per year (annuity + fixed O&M)
    ic_storage_cap = Dict{String,Float64}()       # EUR per MWh per year
    g_max = Dict{String,Float64}()                # existing capacity, MW (brownfield, reader 7.2)
    d_max = Dict{String,Float64}()                # existing charging power, MW
    l_max = Dict{String,Float64}()                # existing storage size, MWh
    eff_in = Dict{String,Float64}()
    eff_out = Dict{String,Float64}()
    vc = Dict{String,Float64}()                   # EUR/MWh

    for row in eachrow(tech_data)
        p = row.technology
        if row.can_invest == 1
            af = annuity_factor(row.lifetime, interest_rate)
            ic_generation_cap[p] = row.investment_generation * af + row.fom
            row.investment_storage > 0 && (ic_storage_cap[p] = row.investment_storage * af)
        end
        g_max[p] = row.g_max
        row.d_max >= 0 && (d_max[p] = row.d_max)
        row.l_max >= 0 && (l_max[p] = row.l_max)
        row.storage_efficiency_in > 0 && (eff_in[p] = row.storage_efficiency_in)
        row.storage_efficiency_out > 0 && (eff_out[p] = row.storage_efficiency_out)
        vc[p] = row.vc
    end
    ic_storage_cap["phs"] = 0.0                   # pumped hydro: whole cost on the turbine MW (DEA sheet 160)

    # --- cable cost: fixed part + part per MW (Härtel et al. 2017; port of Lukas' PR2) ---
    # A small cable costs almost as much as a big one: cable ship, route and two converter stations
    # are paid whatever the size. Härtel et al. (2017), Eq. 2 (cable) and Eq. 3 (converter):
    #   cable B = B_lp*l*p + (B_l*l + B_0),  converter N = N_p*p + N_0   (one system, p << 2 GW)
    # Parameters: "average" set, Table 1, converted to EUR and MW. Open access: https://core.ac.uk/download/249983198.pdf
    B_lp = 970.0             # EUR per MW and km        (cable, grows with size and length)
    B_l = 0.68e6             # EUR per km               (cable, FIXED: laying the route)
    B_0 = 0.70e6             # EUR                      (cable, FIXED: per project)
    N_p = 80.88e3            # EUR per MW per station   (converter, grows with size)
    N_0 = 28.38e6            # EUR per station          (converter, FIXED)
    n_stations = 2           # interconnector: one converter station at each end
    # Price level: the 2011-16 parameters x 1.6 (group decision: one price scenario). Own calibration:
    # Celtic Interconnector actual / formula about 1.7, Shetland HVDC Link about 1.6-1.9; 1.6 = lower end.
    cable_scale = 1.6
    cable_lifetime = 40      # years (own assumption)
    cable_om = 0.01          # O&M per year, share of the investment (own assumption; was 2.5 % cable / 1.5 % converter)
    af_x = annuity_factor(cable_lifetime, interest_rate)
    inv_fix_x = (B_l * cable_km + B_0) + n_stations * N_0           # EUR, fixed terms of Eq. 2 + 3
    inv_var_x = B_lp * cable_km + n_stations * N_p                  # EUR per MW, per-MW terms of Eq. 2 + 3
    fix_x = cable_scale * inv_fix_x * (af_x + cable_om)             # EUR per year, if a cable is built
    var_x = cable_scale * inv_var_x * (af_x + cable_om)             # EUR per MW and year
    # Iceland 450 km: fix_x 39.7 M EUR/yr, var_x 65,357 EUR/MW/yr -> 100 MW = 46.2 M EUR/yr (old linear DEA cost: 16.8)

    # --- cable losses (port of Lukas' PR "Cable: losses (3.5 %) and realistic cost") ---
    # Only (1 - loss) of the imported energy arrives; the Faroes pay for all of it (pi_t x F_IS_FO).

    return (
        input_file = input_file, T = T, P = P, DISP = DISP, NONDISP = NONDISP, S = S, INV = INV,
        ic_generation_cap = ic_generation_cap, ic_storage_cap = ic_storage_cap,
        g_max = g_max, d_max = d_max, l_max = l_max, eff_in = eff_in, eff_out = eff_out, vc = vc,
        # pumped hydro site Mýruverkið II (SEV): 70 MW pump / 40 MW turbine, 20 h at full turbine power
        phs_pump_ratio = 1.75, phs_hours = 20.0, phs_cap_max = 40.0,
        cable_km = cable_km, cable_scale = cable_scale, fix_x = fix_x, var_x = var_x,
        cable_loss = cfg.cable_loss,
        demand = time_series[:, :demand] |> Vector,                           # d_t, MW
        availability = Dict("wind" => time_series[:, :ava_wind], "pv" => time_series[:, :ava_pv]),
        availability_existing = Dict("wind" => time_series_existing[:, :ava_wind],
                                     "pv" => time_series_existing[:, :ava_pv]),
        bio = time_series[:, :biogas] |> Vector,                              # bio_t (new), fixed injection
        inflow = time_series[:, :hydro_inflow] |> Vector,                     # inflow_t (new), MWh per hour
        pi_import = time_series[:, :pi] |> Vector,                            # pi_t (new), EUR/MWh
        dispatch_scale = 8760 / length(T),
    )
end

"""
    solve_model(d, ntc; endo = false, cap = 1000.0, no_export = true)

Builds and solves the model for the inputs `d` (from `load_inputs`).
- `ntc`: fixed cable size in MW (0 = no cable). Ignored when `endo = true`.
- `endo = true`: the cable size is a decision variable NTC with 0 <= NTC <= cap.
- `no_export = true`: import only (group decision 28.10.2026).
"""
function solve_model(d, ntc; endo = false, cap = 1000.0, no_export = true)
    T, P, DISP, NONDISP, S, INV = d.T, d.P, d.DISP, d.NONDISP, d.S, d.INV
    vc, g_max, d_max, l_max, eff_in, eff_out = d.vc, d.g_max, d.d_max, d.l_max, d.eff_in, d.eff_out

    m = Model(HiGHS.Optimizer)
    set_silent(m)
    set_attribute(m, "solver", "ipm")

    @variables m begin
        # dispatch variables
        G[DISP, T] >= 0        # output of oil, hydro, and storage discharge
        CU[T] >= 0             # curtailment
        D_stor[S, T] >= 0      # storage charge
        L_stor[S, T] >= 0      # storage level
        # investment variables (new capacity on top of g_max)
        CAP_G[P] >= 0
        CAP_D[S] >= 0
        CAP_L[S] >= 0
        # hydro reservoir (new)
        L_hyd[T] >= 0
        SPILL[T] >= 0
        # cable flows (reader 6.4)
        F_FO_IS[T] >= 0        # export Faroe Islands -> neighbour
        F_IS_FO[T] >= 0        # import neighbour -> Faroe Islands
    end

    # build decision for the fixed cable cost: NOT a variable. A run either has a cable (build = 1) or not.
    # "Build at all?" = compare a cable run with the no-cable run. For one yes/no decision this gives the same
    # answer as a 0/1 variable (MILP), but the model stays an LP and the hourly duals (prices) stay valid.
    build = (endo || ntc > 0) ? 1.0 : 0.0

    # cable size as investment variable (like CAP_G): ntc becomes NTC.
    # Read it as "IF a cable is built, which size?": only var_x depends on the size.
    if endo
        @variable(m, 0 <= NTC <= cap)
        ntc = NTC
    end

    # min C = C_gen + C_inv (reader 7.1) + trade with the neighbour at pi_t + yearly cable cost
    @objective(m, Min,
        sum(vc[disp] * G[disp, t] for disp in DISP, t in T) * d.dispatch_scale
        + sum(d.ic_generation_cap[p] * CAP_G[p] for p in INV)
        + sum(d.ic_storage_cap[s] * CAP_L[s] for s in S)
        + sum(d.pi_import[t] * (F_IS_FO[t] - F_FO_IS[t]) for t in T) * d.dispatch_scale
        + d.var_x * ntc          # cable: part per MW (Härtel et al. 2017)
        + d.fix_x * build        # cable: fixed part (route + two converter stations), paid once if a cable exists
    )

    # wind and solar feed-in before curtailment (reader 7.2, split into existing and new capacity):
    # G_res,t = ava_existing_res,t * g_max_res + ava_res,t * CAP_G_res
    @expression(m, feed_in[ndisp = NONDISP, t = T],
        d.availability_existing[ndisp][t] * g_max[ndisp] + d.availability[ndisp][t] * CAP_G[ndisp]
    )

    # energy balance per zone (reader 6.4): generation - charging - curtailment + import - export = d_t
    @constraint(m, ElectricityBalance[t = T],
        sum(G[disp, t] for disp in DISP)
        + sum(feed_in[ndisp, t] for ndisp in NONDISP)
        + d.bio[t]
        - sum(D_stor[s, t] for s in S)
        - CU[t]
        + (1 - d.cable_loss) * F_IS_FO[t]   # import: only (1 - loss) arrives (cable + converter losses)
        - F_FO_IS[t]                        # export (switched off in the import-only runs)
        ==
        d.demand[t]
    )

    # G_disp,t <= g_max_disp + CAP_G_disp and G_s,t <= g_max_s + CAP_G_s (reader 7.2)
    @constraint(m, MaxGeneration[disp = DISP, t = T],
        G[disp, t] <= g_max[disp] + CAP_G[disp]
    )

    # curtailment only of available wind and solar
    @constraint(m, MaxCurtailment[t = T],
        CU[t] <= sum(feed_in[ndisp, t] for ndisp in NONDISP)
    )

    # D_stor_s,t <= d_max_s + CAP_D_s (reader 7.2)
    @constraint(m, MaxCharge[s = S, t = T],
        D_stor[s, t] <= d_max[s] + CAP_D[s]
    )

    # battery: one inverter for charging and discharging (as in the course file)
    @constraint(m, SymmetricChargingPower,
        CAP_G["battery"] == CAP_D["battery"]
    )

    # pumped hydro site: pump size, storage hours and maximum size are fixed by the site (new)
    @constraint(m, PhsPump, CAP_D["phs"] == d.phs_pump_ratio * CAP_G["phs"])
    @constraint(m, PhsEnergy, CAP_L["phs"] == d.phs_hours * CAP_G["phs"])
    @constraint(m, PhsSite, CAP_G["phs"] <= d.phs_cap_max)

    # L_stor_s,t <= l_max_s + CAP_L_s (reader 7.2)
    @constraint(m, MaxLevel[s = S, t = T],
        L_stor[s, t] <= l_max[s] + CAP_L[s]
    )

    # storage balance (reader 5 / 7.1): L_t+1 = L_t + eta_in * D_t - G_t / eta_out, cyclic over the year
    @constraint(m, StorageLevel[s = S, t = T],
        L_stor[s, successor(T, t)]
        ==
        L_stor[s, t]
        + eff_in[s] * D_stor[s, t]
        - (1 / eff_out[s]) * G[s, t]
    )

    # existing hydro: one reservoir with inflow and spill, cyclic over the year (new)
    @constraint(m, HydroLevel[t = T],
        L_hyd[successor(T, t)] == L_hyd[t] + d.inflow[t] - G["hydro", t] - SPILL[t]
    )
    @constraint(m, MaxHydroLevel[t = T], L_hyd[t] <= l_max["hydro"])

    # brownfield: no new hydro or oil plants
    @constraint(m, NoNewCapacity[p = setdiff(P, INV)], CAP_G[p] == 0)

    # without oil: G_oil,t = 0 in every hour
    @constraint(m, NoOil[t = T], G["oil", t] == 0)

    # cable (reader 6.4): 0 <= F_z,zz,t <= ntc; one physical cable, so import + export <= ntc
    @constraint(m, MaxExport[t = T], F_FO_IS[t] <= ntc)
    @constraint(m, MaxImport[t = T], F_IS_FO[t] <= ntc)
    @constraint(m, OneCable[t = T], F_FO_IS[t] + F_IS_FO[t] <= ntc)

    # group decision 28.10.2026: import only, no export from the Faroes
    if no_export
        @constraint(m, NoExport[t = T], F_FO_IS[t] == 0)
    end

    optimize!(m)
    return m
end
