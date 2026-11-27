# =============================================================================
#  All switches of the model in ONE place (group rule: no hidden defaults).
#  Any value can be changed on the command line, e.g.
#    julia --project=. run.jl is_2030 cable_loss=0 results_dir=results/test_isolation
#  Port of Lukas' PR "Cable: losses (3.5 %) and realistic cost" (27.11.2026); before: env variable
#  SPIKE_CABLE_LOSS. Cable outages and backup plants are NOT modelled (group decision, see docs/model.md).
# =============================================================================
const DEFAULT_CONFIG = (
    # cable losses (cable + two converter stations), share of the imported energy.
    # North Sea Link 3.5-4 % (futurewatt.co.uk, author's estimate); our cable is shorter, so 3.5 % is on the safe side.
    cable_loss = 0.035,
    # price-level factor on the Härtel et al. (2017) cable cost (group decision: one price scenario, 1.6).
    # Own calibration: Celtic Interconnector actual / formula about 1.7, Shetland HVDC Link about 1.6-1.9;
    # 1.6 = lower end. 1.0 = unscaled formula (Åland-Finland 100 MW reference, open reviewer question).
    cable_scale = 1.6,
    # wind profile for NEW wind capacity (column of the input file):
    #   "power_curve" = ERA5 100 m wind speed x Vestas V117 power curve x (1 - 12 % losses), CF 0.41 (ava_wind_pc,
    #                   pipeline/5_add_power_curve_wind.py). Default, because the group decided on 20.11.2026 to move
    #                   from 0.64 to about 0.42 (real parks: Gellingaklettur ~0.45, Húsahagi ~0.40).
    #   "c3s"         = Copernicus C3S capacity factor, CF 0.64 (ava_wind; the setting of all results before this)
    wind_profile = "power_curve",
    # wind profile for the EXISTING 61.55 MW: "sev" = SEV output / installed capacity, CF 0.27 (Antonia's PR,
    # group setting since 23.11.2026); "power_curve" = same profile as new wind (test: one profile for both)
    existing_wind_profile = "sev",
    # output folder (relative to the repository root)
    results_dir = "results",
)

"""
    parse_config(args)

Splits command line arguments into scenario sets and `key=value` overrides of `DEFAULT_CONFIG`.
"""
function parse_config(args)
    sets = String[]
    cfg = Dict{Symbol,Any}(pairs(DEFAULT_CONFIG))
    for a in args
        if occursin('=', a)
            k, v = split(a, '='; limit = 2)
            key = Symbol(k)
            haskey(cfg, key) || error("unknown setting $k, choose from $(join(keys(DEFAULT_CONFIG), ", "))")
            old = cfg[key]
            cfg[key] = old isa AbstractString ? String(v) : parse(typeof(old), v)
        else
            push!(sets, a)
        end
    end
    cfg[:wind_profile] in ("power_curve", "c3s") || error("wind_profile must be \"power_curve\" or \"c3s\"")
    cfg[:existing_wind_profile] in ("sev", "power_curve") ||
        error("existing_wind_profile must be \"sev\" or \"power_curve\"")
    0 <= cfg[:cable_loss] < 1 || error("cable_loss must be between 0 and 1")
    return sets, NamedTuple(cfg)
end
