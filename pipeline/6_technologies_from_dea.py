"""6_technologies_from_dea.py - technology costs from the two current DEA technology catalogues, one price year.

Group decision 27.11.2026: use the official Danish Energy Agency (DEA) files Connor shared, all costs in ONE
price year (EUR2020), year 2030. Reads
  data/raw/dea/technology_data_for_el_and_dh - 0019.xlsx        (electricity and district heating, version 0019)
  data/raw/dea/technology_datasheet_for_energy_storage - 0011.xlsx (energy storage, version 0011)
and writes data/processed/technologies.csv (same columns as before, so the model runs unchanged).

Every DEA number is read twice: from the datasheet itself (column whose 'year' header is 2030, row 'ctrl') and from
the catalogue's flat table (el/DH: 'alldata_long', storage: 'alldata_flat'). The script stops if the two differ.
(The datasheet '180 Lithium Ion Battery' has an empty 2020 column, so counting columns by eye easily picks 2035.)

Price years (catalogue front pages): "Cost data is in 2020 EURO", except el/DH sheets 22x, 40x, 41x, 45x, 47x and
storage sheets 141a/b, 142, which are in 2025 EURO. Only PV (22) needs a conversion; the factor is the DEA's own
index in note N of sheet 22 (FM nettoprisindeks, 2025 = 1.000, 2020 = 0.856), parsed from the note text.

Mapping onto the model (src/model.jl, load_inputs):
  ic_generation_cap = investment_generation * annuity(lifetime, 5 %) + fom      [EUR per MW and year]
  ic_storage_cap    = investment_storage * annuity(lifetime, 5 %)               [EUR per MWh and year]
  battery: CAP_G (discharge MW) = CAP_D (charge MW), one inverter -> the DEA power component goes on the MW,
           energy component + other project costs (DEA: per MWh, note M "roughly correlate with system size")
           on the MWh; fixed O&M per MW of power, as the DEA unit [kEUR2020/MW/year] says.
  phs:     the model puts the whole cost on the turbine MW (ic_storage_cap['phs'] = 0) -> DEA total greenfield
           investment per MW.
  eff_in = eff_out = sqrt(round-trip efficiency); for Li-ion the DEA 2030 AC round trip (91 %) is used.
  vc: only charged for dispatchable plants (oil, hydro, battery, phs) in the objective. Wind/PV stay 0 (DEA wind
      variable O&M 1.98 EUR/MWh would need a model change; see docs/cost_data.md). Storage keeps 1 EUR/MWh (course
      model tie-breaker; DEA: 0).
Non-DEA rows (oil, hydro) and existing capacities are unchanged and listed below with their sources.
"""
import csv, io, math, pathlib, re
import openpyxl
import pandas as pd

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw" / "dea"
EL_DH = RAW / "technology_data_for_el_and_dh - 0019.xlsx"
STORAGE = RAW / "technology_datasheet_for_energy_storage - 0011.xlsx"
OUT = ROOT / "data" / "processed" / "technologies.csv"
YEAR = 2030
PRICE_YEAR = 2020


def wide(wb, sheet, par, year=YEAR):
    """Value of parameter `par` (start of the label in column B) in the 'ctrl' column whose 'year' header == year."""
    rows = list(wb[sheet].iter_rows(values_only=True))
    hdr = next(r for r in rows if r[0] == "year")
    est = rows[rows.index(hdr) + 1]
    col = next(j for j, v in enumerate(hdr) if str(v) == str(year) and str(est[j]).lower() == "ctrl")
    row = next(r for r in rows if isinstance(r[1], str) and r[1].strip().startswith(par))
    return float(row[col])


def flat(df, sheet, par, year=YEAR):
    s = df[(df.ws == sheet) & (df.est == "ctrl") & (df.year == year) & df.par.str.strip().str.startswith(par)]
    assert len(s) == 1, (sheet, par, len(s))
    return float(s.val.iloc[0]), s.priceyear.iloc[0]


def get(wb, df, sheet, par, price_year=None):
    v_w, v_f = wide(wb, sheet, par), flat(df, sheet, par)
    assert math.isclose(v_w, v_f[0], rel_tol=1e-9), f"{sheet} / {par}: datasheet {v_w} != flat table {v_f[0]}"
    if price_year is not None:
        assert int(v_f[1]) == price_year, f"{sheet} / {par}: price year {v_f[1]}, expected {price_year}"
    print(f"  {sheet:26s} {par[:55]:55s} {YEAR}: {v_w:.6g}" + (f"  (EUR{int(v_f[1])})" if price_year else ""))
    return v_w


el = openpyxl.load_workbook(EL_DH, data_only=True, read_only=True)
st = openpyxl.load_workbook(STORAGE, data_only=True, read_only=True)
el_long = pd.read_excel(EL_DH, sheet_name="alldata_long", header=1)
st_flat = pd.read_excel(STORAGE, sheet_name="alldata_flat")


def cell_text(wb, sheet, pattern):
    for r in wb[sheet].iter_rows(values_only=True):
        t = " | ".join(str(v) for v in r if v is not None)
        if re.search(pattern, t):
            return t
    raise ValueError(f"{pattern} not found in {sheet}")


# versions and price-year statements of the two files (checked, written into the source column)
V_EL = re.search(r"Version \| (\d+)", " | ".join(str(v) for r in el["Intro"].iter_rows(values_only=True)
                                                 for v in r if v is not None)).group(1)
V_ST = re.search(r"Version: \| (\d+)", " | ".join(str(v) for r in st["Index"].iter_rows(values_only=True)
                                                  for v in r if v is not None)).group(1)
assert (V_EL, V_ST) == ("0019", "0011"), (V_EL, V_ST)
assert "2020 | EURO" in cell_text(el, "Intro", r"^Cost data is in")
assert "2020 | EURO" in cell_text(st, "Index", r"Cost data is in \| 2020")

# PV price index: note N of sheet 22 ("2020":0.856, ..., "2025":1.000)
note_n = cell_text(el, "22 Utility-scale PV", r"^N\. Inflation")
idx = {int(y): float(v) for y, v in re.findall(r'"(\d{4})":\s*([\d.]+)', note_n)}
assert idx[2025] == 1.0
PV_TO_2020 = idx[2020] / idx[2025]  # 0.856 (= 1 / 1.168)

print("DEA el/DH version", V_EL, "| storage version", V_ST, "| PV index 2025 -> 2020:", PV_TO_2020)

# --- wind: sheet 20, EUR2020 ---
S_W = "20 Onshore turbines"
w_inv = get(el, el_long, S_W, "Nominal investment (*total)", 2020) * 1e6
w_fom = get(el, el_long, S_W, "Fixed O&M (*total)", 2020)
w_vom = get(el, el_long, S_W, "Variable O&M (*total)", 2020)
w_life = get(el, el_long, S_W, "Technical lifetime")

# --- PV: sheet 22, EUR2025 -> EUR2020 ---
S_PV = "22 Utility-scale PV"
pv_inv = get(el, el_long, S_PV, "Nominal investment (*total) [MEUR/MW_e]", 2025) * 1e6 * PV_TO_2020
pv_fom = get(el, el_long, S_PV, "Fixed O&M (*total) [EUR/MW_e/y]", 2025) * PV_TO_2020
pv_life = get(el, el_long, S_PV, "Technical lifetime")

# --- Li-ion battery: storage sheet 180, EUR2020 ---
S_B = "180 Lithium Ion Battery"
b_energy = get(st, st_flat, S_B, "- energy component", 2020) * 1e6
b_power = get(st, st_flat, S_B, "- power component", 2020) * 1e6
b_other = get(st, st_flat, S_B, "- other project costs", 2020) * 1e6
b_fom = get(st, st_flat, S_B, "Fixed O&M", 2020) * 1e3
b_life = get(st, st_flat, S_B, "Technical lifetime")
b_rte = get(st, st_flat, S_B, "Round trip efficiency [%] AC") / 100
# check of the split: the 2030 unit is 3.6 MWh / 3.6 MW (1 h), so energy + other + power / 1 h must equal the
# DEA "Specific investment [MEUR2020/MWh]" (0.279)
b_spec = get(st, st_flat, S_B, "Specific investment", 2020) * 1e6
b_hours = get(st, st_flat, S_B, "Energy storage capacity for one unit") / get(st, st_flat, S_B, "Output power for one unit")
assert math.isclose(b_energy + b_other + b_power / b_hours, b_spec, rel_tol=1e-6), "battery split != specific investment"

# --- pumped hydro: storage sheet 160, header says EUR2020 (note C: inflated 2002 -> 2011, see docs/cost_data.md) ---
S_P = "160 Pumped hydro storage"
p_inv = get(st, st_flat, S_P, "Investment, total, greenfield plant", 2020) * 1e6
p_fom = get(st, st_flat, S_P, "Fixed O&M", 2020)
p_life = get(st, st_flat, S_P, "Technical lifetime")
p_rte = get(st, st_flat, S_P, "Total efficiency") / 100

EL_SRC = f"DEA el/DH catalogue v{V_EL}"
ST_SRC = f"DEA storage catalogue v{V_ST}"
COLS = ["technology", "dispatchable", "can_invest", "vc", "lifetime", "investment_generation", "investment_storage",
        "fom", "g_max", "d_max", "l_max", "storage_efficiency_in", "storage_efficiency_out", "source"]
ROWS = [
    # existing wind and PV, oil, hydro, battery and the PHS site: unchanged (SEV plant list etc.)
    ["wind", 0, 1, 0, w_life, w_inv, -1, w_fom, 61.55, -1, -1, -1, -1,
     f"{EL_SRC} sheet '{S_W}' col {YEAR} EUR{PRICE_YEAR} (variable O&M {w_vom:.2f} EUR/MWh not modelled); "
     "existing = farms in the SEV feed (Neshagi 4.65 + Husahagi 11.7 + Gellingaklettur 25.2 + Flatnahagi 18 "
     "+ Vestmanna 2; SEV plant list)"],
    ["pv", 0, 1, 0, pv_life, pv_inv, -1, pv_fom, 0, -1, -1, -1, -1,
     f"{EL_SRC} sheet '{S_PV}' col {YEAR} EUR2025 x {PV_TO_2020:.3f} (DEA index note N) = EUR{PRICE_YEAR}; "
     "no PV in the main grid today"],
    ["oil", 1, 0, 0, -1, -1, -1, 0, 86.1, -1, -1, -1, -1,
     "SEV plant list (Sund 82.5 + Strond 3.6); not allowed to run"],
    ["hydro", 1, 0, 0, -1, -1, -1, 0, 37.3, -1, 5850, -1, -1,
     "SEV plant list; reservoir 50 % of 11.7 GWh (Ea Energy Analyses 2018 Table 3)"],
    ["battery", 1, 1, 1, b_life, b_power, b_energy + b_other, b_fom, 12, 12, 12.5, math.sqrt(b_rte),
     math.sqrt(b_rte),
     f"{ST_SRC} sheet '{S_B}' col {YEAR} EUR{PRICE_YEAR}: power component per MW; energy + other project costs "
     f"per MWh; fixed O&M per MW; AC round trip {b_rte:.0%}; existing Sund 12 MW / 12.5 MWh"],
    ["phs", 1, 1, 1, p_life, p_inv, -1, p_fom, 0, 0, 0, math.sqrt(p_rte), math.sqrt(p_rte),
     f"{ST_SRC} sheet '{S_P}' col {YEAR} total greenfield EUR{PRICE_YEAR} per file header (note C: 2011 "
     "price level; see docs/cost_data.md); site Myruverkid II (SEV)"],
]


def fmt(v):
    if isinstance(v, str):
        return v
    if float(v).is_integer():
        return str(int(v))
    return f"{v:.6f}".rstrip("0").rstrip(".") if abs(v) < 10 else f"{v:.2f}".rstrip("0").rstrip(".")


buf = io.StringIO()
w = csv.writer(buf, lineterminator="\n")
w.writerow(COLS)
for r in ROWS:
    w.writerow([fmt(v) for v in r])
OUT.write_text(buf.getvalue(), encoding="utf-8", newline="\n")
print("\nwrote", OUT.relative_to(ROOT))
print(buf.getvalue())
