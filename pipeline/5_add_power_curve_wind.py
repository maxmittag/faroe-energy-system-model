"""5_add_power_curve_wind.py - wind capacity factor from ERA5 wind speed and a turbine power curve.

Group decision 20.11.2026: the C3S wind capacity factor (0.64) is too high for real Faroese parks
(Gellingaklettur about 0.45, Húsahagi about 0.40, actual output after curtailment). Rebuild it from
ERA5 wind speed with a Vestas V117 power curve and ~12 % losses.

Adds ONE column to every data/processed/input_*.csv (steps 2-4 output):
- ava_wind_pc,t = P(v_t) / P_rated * (1 - LOSS)
  v_t  = ERA5 hourly wind speed at 100 m (data/raw/era5/era5_wind_speed_100m_hourly.csv, Open-Meteo
         ERA5 archive, point 62.06 N / 6.85 W = central Streymoy, Húsahagi/Neshagi area).
  P(v) = Vestas V117-3.45 MW power curve: shape of the manufacturer datasheet, rounded to 10-50 kW,
         linear between the points; cut-in 3 m/s, rated 13 m/s, cut-out 25 m/s. Hub height ~100 m,
         so no height correction.
  LOSS = 12 %: wake + availability + electrical losses together. Own assumption, in line with the
         renewables.ninja approach (reanalysis wind speed -> power curve -> correction for real output;
         Staffell & Pfenninger 2016, Energy 114, 1224-1239).
ava_wind (C3S) stays unchanged, so earlier results remain reproducible. Which column the model uses is
the setting wind_profile in src/config.jl.
"""
import glob, pathlib
import numpy as np
import pandas as pd

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw" / "era5" / "era5_wind_speed_100m_hourly.csv"
OUT = ROOT / "data" / "processed"; CHECKS = OUT / "checks"; CHECKS.mkdir(parents=True, exist_ok=True)

# Vestas V117-3.45 MW, simplified power curve (m/s -> kW)
V = np.array([0, 2.9, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 25, 25.01, 40])
P_KW = np.array([0, 0, 20, 120, 290, 540, 880, 1320, 1860, 2450, 2990, 3350, 3450, 3450, 0, 0])
P_RATED = 3450.0
LOSS = 0.12
LOG = []


def say(*a):
    s = " ".join(str(x) for x in a); print(s); LOG.append(s)


ws = pd.read_csv(RAW).set_index("time_utc")["wind_speed_100m"]
for f in sorted(glob.glob(str(OUT / "input_*.csv"))):
    ts = pd.read_csv(f)
    v = ws.reindex(ts.time_utc)
    assert len(ts) == 8760 and v.isna().sum() == 0, f"ERA5 wind speed incomplete for {f}"
    cf = np.interp(v.values, V, P_KW / P_RATED) * (1 - LOSS)
    ts["ava_wind_pc"] = cf.round(5)
    # append the column as text, so all other columns stay byte-identical (pandas would reformat floats)
    lines = pathlib.Path(f).read_text(encoding="utf-8").splitlines()
    if lines[0].endswith(",ava_wind_pc"):                      # re-run: drop the old column first
        lines = [l.rsplit(",", 1)[0] for l in lines]
    lines = [lines[0] + ",ava_wind_pc"] + [l + f",{x:g}" for l, x in zip(lines[1:], ts.ava_wind_pc)]
    pathlib.Path(f).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    say(f"{pathlib.Path(f).name}: ava_wind_pc mean {ts.ava_wind_pc.mean():.3f} (C3S ava_wind {ts.ava_wind.mean():.3f}), "
        f"hourly corr {np.corrcoef(ts.ava_wind_pc, ts.ava_wind)[0, 1]:.3f}")

say(f"\nERA5 100 m wind speed mean {ws.reindex(ts.time_utc).mean():.2f} m/s, hours above cut-out 25 m/s: "
    f"{int((ws.reindex(ts.time_utc) > 25).sum())}")
say("reference, actual output after curtailment (lower bound): Gellingaklettur ~0.45, Húsahagi ~0.40; SEV fleet 0.27")
m = pd.DataFrame({"pc": ts.ava_wind_pc.values, "c3s": ts.ava_wind.values}, index=pd.to_datetime(ts.time_utc)).resample("MS").mean()
m.index = m.index.strftime("%Y-%m")
say("\nmonthly mean wind availability:"); say(m.round(3).to_string())
(CHECKS / "5_add_power_curve_wind.txt").write_text("\n".join(LOG) + "\n", encoding="utf-8", newline="\n")
