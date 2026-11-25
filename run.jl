# =============================================================================
#  Runs all scenarios of the Faroe model and writes the result tables to results/.
#
#    julia --project=. run.jl                 all four sets (about 20-25 min)
#    julia --project=. run.jl is_2030         only one set: is_2030, gb_2030, is_today, gb_today
#
#  One set = one neighbour (Iceland "is" or Scotland "gb") and one demand case ("2030" or "today").
#  Output: results/summary_<set>.csv (one row per case) and results/summary_2030.csv /
#  results/summary_today.csv (both neighbours together).
# =============================================================================
include(joinpath(@__DIR__, "src", "model.jl"))
include(joinpath(@__DIR__, "src", "report.jl"))

# Wind/PV availability of the EXISTING farms: SEV output / installed capacity (group setting since 23.11.2026).
# New capacity always uses the Copernicus C3S profile of the input file.
const EXISTING_AVA_FILE = "base_sev_elma.csv"

#                 neighbour   demand    input file                  cable km
const SETS = Dict(
    "is_2030"  => ("is", "2030",  "input_2030_iceland.csv",   450.0),
    "gb_2030"  => ("gb", "2030",  "input_2030_scotland.csv",  400.0),
    "is_today" => ("is", "today", "input_today_iceland.csv",  450.0),
    "gb_today" => ("gb", "today", "input_today_scotland.csv", 400.0),
)
const ORDER = ["is_2030", "gb_2030", "is_today", "gb_today"]
const RESULTS = joinpath(@__DIR__, "results")

function run_case(d, label; demand_case, counterpart, ntc = 0.0, endo = false, cap = NaN, case_type = "fixed")
    t0 = time()
    m = endo ? solve_model(d, 0.0; endo = true, cap = cap) : solve_model(d, ntc)
    return report(label, m, d, round(time() - t0, digits = 1); counterpart = counterpart, case_type = case_type,
        demand_case = demand_case, ntc_fixed = ntc, cap = cap)
end

function run_set(key)
    tag, demand_case, input, km = SETS[key]
    d = load_inputs(input; cable_km = km, existing_ava_file = EXISTING_AVA_FILE)
    counterpart = tag == "is" ? "Iceland" : "Scotland"
    println("\n== $key: $counterpart, $demand_case demand ($input), cable $km km, ann_x ", round(d.ann_x),
        " EUR/MW/yr, demand ", round(sum(d.demand) / 1e3, digits = 1), " GWh, peak ",
        round(maximum(d.demand), digits = 1), " MW"); flush(stdout)
    rc(label; kw...) = run_case(d, label; demand_case = demand_case, merge((counterpart = counterpart,), kw)...)
    rows = DataFrame()
    if tag == "is"
        rows = vcat(rows, rc("base_no_cable"; ntc = 0.0, counterpart = "none", case_type = "base"), cols = :union)
        for n in [25.0, 50.0, 100.0]
            rows = vcat(rows, rc("is_fixed_$(Int(n))"; ntc = n), cols = :union)
        end
        rows = vcat(rows, rc("is_variable_cap1000"; endo = true, cap = 1000.0, case_type = "variable"), cols = :union)
    else
        for n in [25.0, 50.0, 100.0]
            rows = vcat(rows, rc("gb_fixed_$(Int(n))"; ntc = n), cols = :union)
        end
        r500 = rc("gb_variable_cap500"; endo = true, cap = 500.0, case_type = "variable")
        rows = vcat(rows, r500, cols = :union)
        if r500.status[1] == "OPTIMAL" && r500.ntc_hit_cap[1]   # if the cap binds, show that it moves with the cap
            rows = vcat(rows, rc("gb_variable_cap1000"; endo = true, cap = 1000.0, case_type = "variable"), cols = :union)
        end
        # check: the no-cable case must not depend on which price file is loaded
        rows = vcat(rows, rc("check_base_gb_input"; ntc = 0.0, counterpart = "none", case_type = "check"), cols = :union)
    end
    CSV.write(joinpath(RESULTS, "summary_$(key).csv"), rows)
    return rows
end

todo = isempty(ARGS) ? ORDER : ARGS
foreach(k -> haskey(SETS, k) || error("unknown set $k, choose from $(join(ORDER, ", "))"), todo)
mkpath(RESULTS)
for k in todo
    run_set(k)
end

# combined tables per demand case (from whatever set files exist)
for dc in ["2030", "today"]
    files = filter(isfile, [joinpath(RESULTS, "summary_$(t)_$(dc).csv") for t in ("is", "gb")])
    isempty(files) && continue
    CSV.write(joinpath(RESULTS, "summary_$(dc).csv"), vcat([CSV.read(f, DataFrame) for f in files]..., cols = :union))
end
println("\nresults written to ", RESULTS)
