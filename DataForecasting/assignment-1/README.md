# Assignment 1 - Time series datasets

Upload the **three numbered CSV files** and **dataset_report.pdf**. They are also packaged together in `assignment_1_submission.zip`; use the ZIP if the course upload accepts archives.

| CSV | Subject | Frequency | Observations | Numeric attributes |
|---|---|---|---:|---:|
| `01_nvda_weekly.csv` | NVIDIA adjusted stock price and trading volume | Weekly | 312 | 2 |
| `02_sp500_vix_monthly.csv` | S&P 500 average, VIX average and VIX peak daily close | Monthly | 108 | 3 |
| `03_euro_area_real_gdp_quarterly.csv` | Euro-area real GDP index (2020 = 100; fixed 20-country group) | Quarterly | 120 | 1 |

The report contains source links, frequencies and time spans, observation and attribute counts, attribute definitions, per-column missing-value counts, min/max/mean/sample standard deviation, and every reduction or aggregation operation. `dataset_report.md` provides an editable text copy.

The set follows the interest in stocks and indexes while adding European macroeconomics for domain diversity. The values can have trends, shocks and volatility, but the observation periods are regular, as required by the assignment. All exported columns have zero missing values. Dates label periods; read the report before treating them as actual quote dates.

## Reproduce the files

The original downloads and their URLs/hashes are saved under `support/`. Rebuilding uses those fixed snapshots and does not fetch changing online data. Install Tectonic and make sure `tectonic` is available on your PATH; the report is generated as LaTeX in `support/dataset_report.tex` and compiled with Tectonic.

```sh
python3 -m venv /tmp/dataforecasting-assignment1-venv
/tmp/dataforecasting-assignment1-venv/bin/python -m pip install -r support/requirements.txt
/tmp/dataforecasting-assignment1-venv/bin/python support/build_assignment.py
```

Run these commands from this directory. The report figures are saved in `support/figures/`; compilation logs are written outside the submission folder. Tectonic may download TeX packages on its first run.

To edit only the report layout, change `support/dataset_report.tex`, then compile it from the `support/` directory with `tectonic --outdir .. dataset_report.tex`. Re-running the Python builder regenerates the LaTeX source and submission ZIP.
