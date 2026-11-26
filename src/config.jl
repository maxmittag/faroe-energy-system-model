# =============================================================================
#  All switches of the model in ONE place (group rule: no hidden defaults).
#  Any value can be changed on the command line, e.g.
#    julia --project=. run.jl is_2030 cable_loss=0 outage_hours=1344 backup=oil
#  Port of Lukas' PR1 (cable reliability); before: env variables SPIKE_CABLE_LOSS,
#  SPIKE_OUTAGE_HOURS, SPIKE_OUTAGE_START, SPIKE_BACKUP, SPIKE_BACKUP_VC.
# =============================================================================
const DEFAULT_CONFIG = (
    # cable losses (cable + two converter stations), share of the imported energy.
    # North Sea Link 3.5-4 % (futurewatt.co.uk, author's estimate); our cable is shorter, so 3.5 % is on the safe side.
    cable_loss = 0.035,
    # cable outage in hours (0 = none). Typical repair 1,344 h = 8 weeks, fast repair 672 h = 4 weeks
    # (ENTSO-E/Europacable 2019: about 60 days on average; Baltic Cable 2020: 29 days).
    outage_hours = 0,
    # first hour of the outage; 0 = placed automatically in the worst window of the year
    outage_start = 0,
    # backup during the outage: "none" = local green backup (no oil), "oil" = existing Sund plant
    # (86 MW, sunk) may run ONLY in outage hours (heavy fuel oil or biodiesel/HVO)
    backup = "none",
    # cost of backup electricity, EUR/MWh (fuel + O&M). PLACEHOLDER: replace with a sourced SEV/biodiesel value.
    backup_vc = 150.0,
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
    cfg[:backup] in ("none", "oil") || error("backup must be \"none\" or \"oil\"")
    0 <= cfg[:cable_loss] < 1 || error("cable_loss must be between 0 and 1")
    return sets, NamedTuple(cfg)
end
