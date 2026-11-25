"""2_add_c3s_profiles.py - wind and solar availability from Copernicus C3S (weather based).

Takes data/processed/base_sev_elma.csv (step 1) and replaces only these two columns:
- ava_wind,t = C3S onshore wind capacity factor (ERA5 100 m wind, Vestas V136/3450, hub 100 m), grid cell
               62.25 N / 6.75 W (the one land cell on the Faroe main island, 0.25 deg grid).
- ava_pv,t   = C3S solar PV capacity factor, same grid cell.
  Source: Copernicus Climate Change Service, "Climate and energy indicators for Europe from 1979 to present
  derived from reanalysis" (sis-energy-derived-reanalysis), CC-BY 4.0. Times in UTC.
Unchanged from step 1: demand, hydro inflow, biogas (SEV) and the Elma price.
Output: data/processed/input_today_iceland.csv (today's demand, Iceland price).
Lecturer (VL13, 22.10.2026): use weather-based capacity factors, not historical output (contains curtailment).
"""
import glob, pathlib
import numpy as np
import pandas as pd

ROOT = pathlib.Path(__file__).resolve().parent.parent
C3S = ROOT / "data" / "raw" / "c3s"
CELL = "62.25_-6.75"
OUT = ROOT / "data" / "processed"; CHECKS = OUT / "checks"; CHECKS.mkdir(parents=True, exist_ok=True)
LOG = []


def say(*a):
    s = " ".join(str(x) for x in a); print(s); LOG.append(s)


def load(short):
    df = pd.concat([pd.read_csv(f, index_col=0, parse_dates=True) for f in sorted(glob.glob(str(C3S / f"cell_{short}_*.csv")))])
    s = df[f"{short}_{CELL}"].sort_index()
    return s[~s.index.duplicated()]


v3 = pd.read_csv(OUT / "base_sev_elma.csv")   # step 1 output (called "v3" below)
idx = pd.to_datetime(v3.time_utc)
wind = load("won").reindex(idx)
pv = load("spv").reindex(idx)
say(f"model year {idx.iloc[0]} .. {idx.iloc[-1]}, {len(idx)} h; missing C3S hours: wind {int(wind.isna().sum())}, pv {int(pv.isna().sum())}")
assert wind.isna().sum() == 0 and pv.isna().sum() == 0, "C3S series incomplete"

ts = v3.copy()
ts["ava_wind"] = np.clip(wind.values, 0, 1).round(5)
ts["ava_pv"] = np.clip(pv.values, 0, 1).round(5)
ts.to_csv(OUT / "input_today_iceland.csv", index=False, lineterminator="\n")

say("\n=== availability v3 (SEV output) vs v4 (C3S weather-based) ===")
say(f"wind CF   v3 {v3.ava_wind.mean():.3f} ({v3.ava_wind.sum():.0f} full-load h)   v4 {ts.ava_wind.mean():.3f} ({ts.ava_wind.sum():.0f} h)   "
    f"hourly corr {np.corrcoef(v3.ava_wind, ts.ava_wind)[0,1]:.3f}")
say(f"PV CF     v3 {v3.ava_pv.mean():.3f} ({v3.ava_pv.sum():.0f} full-load h)   v4 {ts.ava_pv.mean():.3f} ({ts.ava_pv.sum():.0f} h)   "
    f"hourly corr {np.corrcoef(v3.ava_pv, ts.ava_pv)[0,1]:.3f}")
m = pd.DataFrame({"wind_v3": v3.ava_wind.values, "wind_v4": ts.ava_wind.values,
                  "pv_v3": v3.ava_pv.values, "pv_v4": ts.ava_pv.values}, index=idx).resample("MS").mean()
m.index = m.index.strftime("%Y-%m")
say("\nmonthly mean availability:"); say(m.round(3).to_string())
wk = pd.Series(ts.ava_wind.values, index=idx).rolling(168).mean()
summer = wk[(wk.index >= "2026-06-07 23:00") & (wk.index <= "2026-08-31 23:00")]
e7 = summer.idxmin()
say(f"\ncalmest summer week (C3S): {e7 - pd.Timedelta(hours=167)} .. {e7} UTC, mean ava_wind {summer.min():.3f}")
(CHECKS / "2_add_c3s_profiles.txt").write_text("\n".join(LOG) + "\n", encoding="utf-8", newline="\n")
