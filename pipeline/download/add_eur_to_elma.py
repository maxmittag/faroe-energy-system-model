# NOT needed to run the model: the downloaded files are in data/raw/. Kept to document where the data came from.
"""Adds ECB exchange rates (ISK/EUR, USD/EUR, daily, carried forward over weekends) and price_eur_mwh to
elma_dayahead.csv. The two ECB files were downloaded by hand from data-api.ecb.europa.eu
(series EXR D.ISK.EUR.SP00.A and D.USD.EUR.SP00.A). Run only once on a fresh download."""
import pandas as pd, numpy as np
import pathlib
raw = str(pathlib.Path(__file__).resolve().parents[2] / "data" / "raw" / "elma") + "/"
d = pd.read_csv(raw + "elma_dayahead.csv", parse_dates=["time_utc"])
fx = pd.read_csv(raw + "ecb_isk_eur_daily.csv", usecols=["TIME_PERIOD", "OBS_VALUE"])
fx["date"] = pd.to_datetime(fx.TIME_PERIOD)
usd = pd.read_csv(raw + "ecb_usd_eur_daily.csv", usecols=["TIME_PERIOD", "OBS_VALUE"])
usd["date"] = pd.to_datetime(usd.TIME_PERIOD)
d["date"] = pd.to_datetime(d.delivery_date)
cal = pd.DataFrame({"date": pd.date_range("2025-03-01", d.date.max())})
cal = cal.merge(fx[["date", "OBS_VALUE"]].rename(columns={"OBS_VALUE": "isk_per_eur"}), how="left") \
         .merge(usd[["date", "OBS_VALUE"]].rename(columns={"OBS_VALUE": "usd_per_eur"}), how="left").ffill()
d = d.merge(cal, on="date", how="left")
d["price_eur_mwh"] = d.price_isk_mwh / d.isk_per_eur
d.drop(columns="date").to_csv(raw + "elma_dayahead.csv", index=False)  # add FX + EUR columns

