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
    0 <= cfg[:cable_loss] < 1 || error("cable_loss must be between 0 and 1")
    return sets, NamedTuple(cfg)
end
