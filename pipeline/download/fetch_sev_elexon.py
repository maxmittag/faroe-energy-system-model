# NOT needed to run the model: the downloaded files are in data/raw/. Kept to document where the data came from.
"""Download SEV and Elexon raw data (run once, saves to data/raw/).

Sources (no keys needed):
- SEV hourly production per plant, 2023-01-01 .. yesterday (www.sev.fo/api/elproduction)
- Elexon GB Market Index price (half-hourly), as price profile for a cable to Scotland
"""
import json, time, datetime as dt, urllib.request, pathlib, csv

RAW = pathlib.Path(__file__).resolve().parents[2] / "data" / "raw"
RAW.mkdir(parents=True, exist_ok=True)
# Writes plain .csv files; the repository stores them gzip-compressed (same content).
START = dt.date(2023, 1, 1)
END = dt.date.today() - dt.timedelta(days=1)
UA = {"User-Agent": "Mozilla/5.0 (CBS student project)"}


def get(url, tries=5, timeout=120):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            return json.loads(urllib.request.urlopen(req, timeout=timeout).read())
        except Exception as e:  # noqa
            print("  retry", i + 1, str(e)[:80], flush=True)
            time.sleep(10 * (i + 1))
    raise RuntimeError("failed: " + url)


def sev():
    out = RAW / "sev" / "sev_production_hourly.csv"
    out.parent.mkdir(exist_ok=True)
    done = set()
    if out.exists():
        with open(out, encoding="utf-8") as f:
            done = {r["chunk"] for r in csv.DictReader(f)}
    new = not out.exists()
    f = open(out, "a", newline="", encoding="utf-8")
    w = csv.writer(f)
    if new:
        w.writerow(["chunk", "date_local", "powerplant", "motivepower", "area", "mwh"])
    d = START
    while d <= END:
        e = min(d + dt.timedelta(days=7), END + dt.timedelta(days=1))
        chunk = d.isoformat()
        if chunk not in done:
            # API window: from day-1 17:00 to day 17:00 local (as in electricitymaps parser)
            a = (d - dt.timedelta(days=1)).strftime("%Y%m%d") + "170000"
            b = (e - dt.timedelta(days=1)).strftime("%Y%m%d") + "170000"
            url = f"https://www.sev.fo/api/elproduction/search?type=item&group=powerplant&from={a}&to={b}"
            rows = get(url)
            for r in rows:
                w.writerow([chunk, r["date"], r["powerplant"], r["motivepower"], r["area"], r["mwh"]])
            f.flush()
            print("SEV", chunk, len(rows), flush=True)
            time.sleep(4)
        d = e
    f.close()


def elexon():
    out = RAW / "elexon" / "gb_market_index_price.csv"
    out.parent.mkdir(exist_ok=True)
    if out.exists():
        return
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["startTime", "dataProvider", "price_gbp_mwh", "volume"])
        d = START
        while d <= END:
            e = min(d + dt.timedelta(days=7), END + dt.timedelta(days=1))
            url = (f"https://data.elexon.co.uk/bmrs/api/v1/balancing/pricing/market-index?from={d}T00:00Z&to={e}T00:00Z&format=json")
            for r in get(url).get("data", []):
                w.writerow([r["startTime"], r["dataProvider"], r["price"], r["volume"]])
            d = e
            time.sleep(1)
    print("Elexon done", flush=True)


if __name__ == "__main__":
    elexon()
    sev()
    print("ALL DONE", flush=True)
