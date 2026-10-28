"""Download the seasonal replacement for dataset 3 and save it as a CSV.

Assignment 1 used euro-area real GDP *seasonally adjusted* (Eurostat code SCA),
which means Eurostat had already removed the seasonality. Here we download the
same series *not seasonally adjusted* (code NSA), so the seasonality is still in it.
Same quarters as before: 1996 Q3 to 2026 Q2 (120 quarters).

Run once:  python download_gdp.py
"""

import pandas as pd

# Eurostat table namq_10_gdp, filtered to:
# Q = quarterly, CLV_I20 = real GDP index (2020 = 100), NSA = not seasonally adjusted,
# B1GQ = gross domestic product, EA20 = euro area (20 countries).
URL = (
    "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/namq_10_gdp/"
    "Q.CLV_I20.NSA.B1GQ.EA20?format=SDMX-CSV&startPeriod=1996-Q3&endPeriod=2026-Q2"
)

raw = pd.read_csv(URL)

# Keep only the two columns we need: the quarter ("1996-Q3") and the value.
gdp = pd.DataFrame({
    # "1996-Q3" -> 1996-07-01, the first day of the quarter (same style as the other CSVs).
    "date": pd.PeriodIndex(raw["TIME_PERIOD"].str.replace("-", ""), freq="Q").start_time,
    "real_gdp_index": raw["OBS_VALUE"],
})

assert len(gdp) == 120 and gdp["real_gdp_index"].notna().all()
gdp.to_csv("03_euro_area_real_gdp_nsa_quarterly.csv", index=False, date_format="%Y-%m-%d")
print(gdp.head(), gdp.tail(), sep="\n...\n")
