# =============================================================================
#  Result table for one solved case: capacities, energy flows, cost split and checks.
#  Every number in results/*.csv comes from here.
# =============================================================================

function report(label, m, d, solve_s; counterpart, case_type, demand_case, ntc_fixed = NaN, cap = NaN)
    T, DISP, NONDISP, S, INV = d.T, d.DISP, d.NONDISP, d.S, d.INV
    st = termination_status(m)
    head = DataFrame(case = label, counterpart = counterpart, case_type = case_type, demand_case = demand_case,
        input = d.input_file, no_export = true, status = string(st), primal_status = string(primal_status(m)))
    if st != MOI.OPTIMAL
        println(label, ": ", st); flush(stdout)
        return head
    end
    CAP_G, CAP_L, G, D_stor = m[:CAP_G], m[:CAP_L], m[:G], m[:D_stor]
    F_IS_FO, F_FO_IS, CU, feed_in = m[:F_IS_FO], m[:F_FO_IS], m[:CU], m[:feed_in]
    endo = haskey(object_dictionary(m), :NTC)
    ntc_val = endo ? value(m[:NTC]) : ntc_fixed
    imp = [value(F_IS_FO[t]) for t in T]; ex = [value(F_FO_IS[t]) for t in T]
    avail = sum(value(feed_in[n, t]) for n in NONDISP, t in T)
    cu = sum(value(CU[t]) for t in T)
    # checks
    bal = [sum(value(G[g, t]) for g in DISP) + sum(value(feed_in[n, t]) for n in NONDISP) + d.bio[t] -
           sum(value(D_stor[s, t]) for s in S) - value(CU[t]) + imp[t] - ex[t] - d.demand[t] for t in T]
    oil_max = maximum(value(G["oil", t]) for t in T)
    # cost components (EUR per year), must add up to the objective
    c_inv_gen = sum(d.ic_generation_cap[p] * value(CAP_G[p]) for p in INV)
    c_inv_sto = sum(d.ic_storage_cap[s] * value(CAP_L[s]) for s in S)
    c_var = sum(d.vc[g] * value(G[g, t]) for g in DISP, t in T) * d.dispatch_scale
    c_trade = sum(d.pi_import[t] * (imp[t] - ex[t]) for t in T) * d.dispatch_scale
    c_cable = d.ann_x * ntc_val
    obj = objective_value(m)
    hit_cap = endo ? (ntc_val >= cap - 0.01) : false
    full_hours = ntc_val > 0 ? count(>=(ntc_val - 0.01), imp) : 0      # hours with the cable (almost) full
    out = hcat(head, DataFrame(
        cable_km = ntc_val > 0 ? d.cable_km : 0.0, ann_x_EUR_per_MW = d.ann_x, cap_MW = cap, ntc_hit_cap = hit_cap,
        cost_MEUR = obj / 1e6, ntc_MW = ntc_val,
        new_wind_MW = value(CAP_G["wind"]), new_pv_MW = value(CAP_G["pv"]),
        new_bat_MW = value(CAP_G["battery"]), new_bat_MWh = value(CAP_L["battery"]), new_phs_MW = value(CAP_G["phs"]),
        import_GWh = sum(imp) / 1e3, export_GWh = sum(ex) / 1e3,
        demand_GWh = sum(d.demand) / 1e3, peak_demand_MW = maximum(d.demand),
        import_share_demand = sum(imp) / sum(d.demand), export_share_demand = sum(ex) / sum(d.demand),
        curtail_share = avail > 0 ? cu / avail : 0.0, curtail_GWh = cu / 1e3, avail_res_GWh = avail / 1e3,
        wind_total_MW = d.g_max["wind"] + value(CAP_G["wind"]),
        import_hours = count(>(0.01), imp), export_hours = count(>(0.01), ex), cable_full_hours = full_hours,
        cable_util = ntc_val > 0 ? sum(imp) / (ntc_val * length(T)) : 0.0,
        pi_mean = sum(d.pi_import) / length(T),
        import_price_mean = sum(imp) > 0 ? sum(d.pi_import .* imp) / sum(imp) : NaN,
        hydro_GWh = sum(value(G["hydro", t]) for t in T) / 1e3,
        c_inv_gen_MEUR = c_inv_gen / 1e6, c_inv_storage_MEUR = c_inv_sto / 1e6, c_var_MEUR = c_var / 1e6,
        c_trade_MEUR = c_trade / 1e6, c_cable_MEUR = c_cable / 1e6,
        check_cost_sum_err_EUR = c_inv_gen + c_inv_sto + c_var + c_trade + c_cable - obj,
        check_balance_err_max_MW = maximum(abs.(bal)), check_oil_max_MW = oil_max,
        check_export_max_MW = maximum(ex), check_import_max_MW = maximum(imp),
        solve_s = solve_s))
    println(rpad(label, 22), round(obj / 1e6, digits = 2), " MEUR/yr | cable ", round(ntc_val, digits = 1),
        " MW | new wind ", round(value(CAP_G["wind"]), digits = 1), " MW, pv ", round(value(CAP_G["pv"]), digits = 1),
        " MW, battery ", round(value(CAP_G["battery"]), digits = 1), " MW / ", round(value(CAP_L["battery"]), digits = 1),
        " MWh | import ", round(sum(imp) / 1e3, digits = 1), " GWh | curtailed ",
        round(100 * cu / max(avail, 1e-9), digits = 1), " % | ", solve_s, " s"); flush(stdout)
    return out
end
