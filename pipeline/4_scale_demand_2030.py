"""4_scale_demand_2030.py - group assumption (meeting 28.10.2026): 2030 demand = 600/506 x today's hourly profile, factor fixed at 1.186.
Multiplies ONLY the 'demand' column of both input files; every other column is copied byte for byte.

Output: data/processed/input_2030_iceland.csv, data/processed/input_2030_scotland.csv
"""
import pathlib

FACTOR = 1.186
DATA = pathlib.Path(__file__).resolve().parent.parent / "data" / "processed"

for src, dst in [("input_today_iceland.csv", "input_2030_iceland.csv"), ("input_today_scotland.csv", "input_2030_scotland.csv")]:
    lines = (DATA / src).read_text().splitlines()
    head = lines[0].split(",")
    k = head.index("demand")
    out = [lines[0]]
    for ln in lines[1:]:
        if not ln.strip():
            continue
        cells = ln.split(",")
        cells[k] = f"{float(cells[k]) * FACTOR:.6f}"
        out.append(",".join(cells))
    (DATA / dst).write_text("\n".join(out) + "\n", newline="\n")
    print(dst, len(out) - 1, "hours")
