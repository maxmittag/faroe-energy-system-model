# =============================================================================
#  Break-even cable price factor: the cable_scale at which the cheapest cable case (size chosen by the model)
#  costs exactly as much as the no-cable system.
#
#    julia --project=. break_even.jl                 both neighbours (2030 demand), other settings = defaults
#    julia --project=. break_even.jl is_2030         one set only
#    julia --project=. break_even.jl is_2030 cable_loss=0 results_dir=results/test
#
#  Method: the no-cable cost does not depend on cable_scale. For a given scale s the cheapest cable system costs
#  C(s) = rest(s) + s * k(s)  (k = cable cost at scale 1). Fixed-point iteration s_new = (C_base - rest) / k,
#  each step a full re-optimisation (size chosen, limit as in run.jl), until |s_new - s| < 0.001.
#  C(s) is the minimum over designs of lines in s, i.e. concave, so the iteration converges in 2-4 solves.
#  Output: <results_dir>/break_even_cable_scale.csv (every iteration, last row per set = break-even).
# =============================================================================
include(joinpath(@__DIR__, "src", "config.jl"))
include(joinpath(@__DIR__, "src", "model.jl"))
include(joinpath(@__DIR__, "src", "report.jl"))

const EXISTING_AVA_FILE = "base_sev_elma.csv"
#                 neighbour   input file                 cable km  size limit (as run.jl)
const BE_SETS = Dict(
    "is_2030" => ("Iceland",  "input_2030_iceland.csv",  450.0, 1000.0),
    "gb_2030" => ("Scotland", "input_2030_scotland.csv", 400.0, 500.0),
)
todo, CFG0 = parse_config(ARGS)
todo = isempty(todo) ? ["is_2030", "gb_2030"] : todo
const OUTDIR = joinpath(@__DIR__, CFG0.results_dir)
mkpath(OUTDIR)

rows = DataFrame()
for key in todo
    counterpart, input, km, cap = BE_SETS[key]
    cfg_at(s) = merge(CFG0, (cable_scale = s,))
    d0 = load_inputs(input; cable_km = km, existing_ava_file = EXISTING_AVA_FILE, cfg = CFG0)
    base = report("base_no_cable", solve_model(d0, 0.0), d0, 0.0; counterpart = "none", case_type = "base",
                  demand_case = "2030")
    c_base = base.cost_MEUR[1]
    println("\n== $key: no cable $(round(c_base, digits = 3)) MEUR/yr"); flush(stdout)
    s = CFG0.cable_scale
    for it in 1:8
        d = load_inputs(input; cable_km = km, existing_ava_file = EXISTING_AVA_FILE, cfg = cfg_at(s))
        r = report("$(key)_variable_scale_$(round(s, digits = 4))", solve_model(d, 0.0; endo = true, cap = cap), d,
                   0.0; counterpart = counterpart, case_type = "variable", demand_case = "2030", cap = cap)
        c, c_cab = r.cost_MEUR[1], r.c_cable_MEUR[1]
        k = c_cab / s                    # cable cost at scale 1 for this design
        s_new = (c_base - (c - c_cab)) / k
        println("  it $it: scale $(round(s, digits = 4)) -> cable $(round(c, digits = 3)) MEUR/yr ",
                "($(round(r.ntc_MW[1], digits = 1)) MW), gap $(round(c - c_base, digits = 3)), next scale ",
                round(s_new, digits = 4)); flush(stdout)
        global rows = vcat(rows, DataFrame(set = key, counterpart = counterpart, iteration = it, cable_scale = s,
            cost_cable_MEUR = c, cost_no_cable_MEUR = c_base, gap_MEUR = c - c_base, ntc_MW = r.ntc_MW[1],
            c_cable_MEUR = c_cab, rest_MEUR = c - c_cab, next_scale = s_new,
            break_even_scale = abs(s_new - s) < 1e-3 ? s_new : NaN), cols = :union)
        abs(s_new - s) < 1e-3 && break
        s = s_new
    end
end
CSV.write(joinpath(OUTDIR, "break_even_cable_scale.csv"), rows)
println("\nwritten ", joinpath(OUTDIR, "break_even_cable_scale.csv"))
