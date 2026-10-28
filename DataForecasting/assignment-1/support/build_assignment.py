"""Rebuild the fixed Assignment 1 submission from the saved source snapshots."""

from hashlib import sha256
from pathlib import Path
from statistics import mean, stdev
import json
import os
import subprocess
import zipfile

os.environ.setdefault("MPLCONFIGDIR", "/private/tmp/dataforecasting-matplotlib")
os.environ.setdefault("XDG_CACHE_HOME", "/private/tmp/dataforecasting-cache")
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "support" / "raw"
QA = Path("/private/tmp/dataforecasting-assignment1-qa")
QA.mkdir(exist_ok=True)
FIGURES = ROOT / "support" / "figures"
FIGURES.mkdir(exist_ok=True)
AS_OF = pd.Timestamp("2026-10-05")
RETRIEVED = "2026-10-05"


def chart_data(filename, expected_symbol):
    payload = json.loads((RAW / filename).read_text())
    assert payload["chart"]["error"] is None
    result = payload["chart"]["result"][0]
    assert result["meta"]["symbol"] == expected_symbol
    frame = pd.DataFrame(result["indicators"]["quote"][0])
    frame["adjclose"] = result["indicators"]["adjclose"][0]["adjclose"]
    frame.index = (
        pd.to_datetime(result["timestamp"], unit="s", utc=True)
        .tz_convert("America/New_York").normalize().tz_localize(None)
    )
    frame.index.name = "date"
    assert frame.index.is_unique and frame.index.is_monotonic_increasing
    return frame.loc[frame.index < AS_OF]


nvda = chart_data("nvda_daily.json", "NVDA")
sp500 = chart_data("sp500_daily.json", "^GSPC")
vix = pd.read_csv(RAW / "vix_daily.csv", parse_dates=["DATE"]).set_index("DATE")
vix = vix.sort_index().loc[lambda x: x.index < AS_OF]
assert vix.index.is_unique

# Saturday-Friday buckets, labelled on Friday. Keep completed weeks only.
weekly = nvda.resample("W-FRI", closed="right", label="right").agg(
    nvda_adjusted_close_usd=("adjclose", "last"),
    nvda_volume_shares=("volume", "sum"),
)
weekly = weekly.loc[weekly.index < AS_OF].tail(312)
assert nvda.loc[weekly.index.min() - pd.Timedelta(days=6):, ["adjclose", "volume"]].notna().all().all()
weekly["nvda_volume_shares"] = weekly["nvda_volume_shares"].astype("int64")

# Use the same trading dates for the two market indexes in the retained months.
vix_on_sp_dates = vix.reindex(sp500.index)["CLOSE"]
assert vix_on_sp_dates.notna().all(), "A VIX close is missing on an S&P 500 trading date"
monthly = pd.concat([
    sp500["close"].resample("MS").mean().rename("sp500_mean_close"),
    vix_on_sp_dates.resample("MS").mean().rename("vix_mean_close"),
    vix_on_sp_dates.resample("MS").max().rename("vix_max_close"),
], axis=1)
monthly = monthly.loc[monthly.index < AS_OF.to_period("M").start_time].tail(108)
sp_dates = sp500.loc[monthly.index.min():monthly.index.max() + pd.offsets.MonthEnd()].index
vix_dates = vix.loc[monthly.index.min():monthly.index.max() + pd.offsets.MonthEnd()].index
excluded_vix_dates = vix_dates.difference(sp_dates)
assert len(excluded_vix_dates) == 33 and sp_dates.difference(vix_dates).empty
assert sp500.loc[sp_dates, "close"].notna().all() and vix.loc[vix_dates, "CLOSE"].notna().all()

# The Eurostat request fixes every dimension except time, so values are indexed by quarter.
gdp_raw = json.loads((RAW / "euro_area_gdp_eurostat.json").read_text())
assert gdp_raw["source"] == "ESTAT"
expected_dimensions = {"freq": "Q", "unit": "CLV_I20", "s_adj": "SCA", "na_item": "B1GQ", "geo": "EA20"}
for dimension, code in expected_dimensions.items():
    assert gdp_raw["dimension"][dimension]["category"]["index"] == {code: 0}
assert gdp_raw["id"][-1] == "time" and all(size == 1 for size in gdp_raw["size"][:-1])
gdp_records = [
    (pd.Period(quarter.replace("-", ""), freq="Q").start_time, gdp_raw["value"].get(str(position)))
    for quarter, position in gdp_raw["dimension"]["time"]["category"]["index"].items()
]
gdp = pd.DataFrame(gdp_records, columns=["date", "real_gdp_index"]).set_index("date").sort_index()
gdp = gdp.loc[gdp.index.to_period("Q").end_time < AS_OF].tail(120)

definitions = [
    {
        "title": "NVIDIA stock", "subtitle": "Weekly | Individual technology stock",
        "filename": "01_nvda_weekly.csv", "frame": weekly, "frequency": "Weekly", "rule": "W-FRI",
        "sources": [("Yahoo Finance: NVDA historical data", "https://finance.yahoo.com/quote/NVDA/history/")],
        "attributes": [
            ("date", "Friday labelling a Saturday-Friday week; YYYY-MM-DD."),
            ("nvda_adjusted_close_usd", "Last trading day's adjusted close in the week, USD per share. Yahoo adjusts this for splits and dividends."),
            ("nvda_volume_shares", "Sum of the daily trading volumes reported by Yahoo within the week, in shares."),
        ],
        "processing": "Daily observations were aggregated into Saturday-Friday weeks: last adjusted close and sum of volume. Only the most recent 312 complete weeks were retained. Open, high, low and unadjusted close were removed. A holiday Friday keeps the last actual quote within that week; the date is a period label. No prices were interpolated or forward-filled.",
        "interest": "An individual stock with strong trends and changing trading activity. Useful for studying price versus volume and the effect of differencing or returns on a trending series.",
        "span": f"{weekly.index.min():%Y-%m-%d} to {weekly.index.max():%Y-%m-%d} (Friday labels)",
        "coverage": f"Underlying trading dates: {nvda.loc[weekly.index.min() - pd.Timedelta(days=6):].index.min():%Y-%m-%d} to {nvda.index.max():%Y-%m-%d}.",
        "plot_columns": ["nvda_adjusted_close_usd"], "plot_labels": ["Adjusted close (USD/share)"],
    },
    {
        "title": "S&P 500 and VIX", "subtitle": "Monthly | Equity market level and expected volatility",
        "filename": "02_sp500_vix_monthly.csv", "frame": monthly, "frequency": "Monthly", "rule": "MS",
        "sources": [
            ("Yahoo Finance: S&P 500 historical data", "https://finance.yahoo.com/quote/%5EGSPC/history/"),
            ("Cboe: VIX historical data", "https://www.cboe.com/tradable_products/vix/vix_historical_data"),
        ],
        "attributes": [
            ("date", "First day labelling the calendar month; YYYY-MM-DD."),
            ("sp500_mean_close", "Arithmetic mean of the daily S&P 500 closes, in index points; a price index excluding dividends."),
            ("vix_mean_close", "Arithmetic mean of daily VIX closes, in volatility index points (annualized percentage units)."),
            ("vix_max_close", "Largest daily VIX close in the month, in the same units; this is not an intraday high."),
        ],
        "processing": "Daily closes were grouped by calendar month: mean for each index and maximum daily close for VIX. The most recent 108 complete months were retained; incomplete October 2026 was excluded. Within this window, 33 extra VIX holiday observations were excluded to use the same S&P 500 trading dates for both indexes. Other daily attributes were removed. No missing values were filled.",
        "interest": "A multivariate dataset contrasting broad equity-market trends with volatility spikes. The maximum VIX close retains information about stress that a monthly average can smooth out. No relationship between the variables is assumed.",
        "span": f"{monthly.index.min():%Y-%m-%d} to {monthly.index.max():%Y-%m-%d} (month-start labels)",
        "coverage": f"Covered calendar months: {monthly.index.min():%Y-%m} through {monthly.index.max():%Y-%m}, ending {(monthly.index.max() + pd.offsets.MonthEnd()):%Y-%m-%d}.",
        "plot_columns": ["sp500_mean_close", "vix_mean_close", "vix_max_close"],
        "plot_labels": ["S&P 500 mean (points)", "VIX mean", "VIX max daily close"],
    },
    {
        "title": "Euro-area real GDP index", "subtitle": "Quarterly | European macroeconomics",
        "filename": "03_euro_area_real_gdp_quarterly.csv", "frame": gdp, "frequency": "Quarterly", "rule": "QS-JAN",
        "sources": [("Eurostat: quarterly GDP (namq_10_gdp)", "https://ec.europa.eu/eurostat/databrowser/view/namq_10_gdp/default/table?lang=en")],
        "attributes": [
            ("date", "First day labelling the quarter (January, April, July or October); YYYY-MM-DD."),
            ("real_gdp_index", "Real GDP in chain-linked volumes, index 2020 = 100; seasonally and calendar adjusted. Covers the fixed 20-country euro-area group (EA20). Measures economic output excluding inflation."),
        ],
        "processing": "Eurostat filters: frequency Q; geography EA20; GDP B1GQ; unit CLV_I20; adjustment SCA. The selected source contains 126 quarters from 1995 Q1 through 2026 Q2; only the latest 120 were retained, removing the oldest six. Quarter codes were converted to quarter-start dates. Constant series metadata were omitted from the CSV. Original index values were preserved without aggregation or imputation.",
        "interest": "Adds a European economic domain and slower frequency. Useful for studying long-term growth, recessions and shocks such as the COVID-19 contraction and subsequent rebound. The source's seasonal and calendar adjustment helps focus on economic cycles.",
        "span": f"{gdp.index.min():%Y-%m-%d} to {gdp.index.max():%Y-%m-%d} (quarter-start labels)",
        "coverage": f"Covered quarters: {gdp.index.min().to_period('Q')} through {gdp.index.max().to_period('Q')}, ending {gdp.index.max().to_period('Q').end_time:%Y-%m-%d}.",
        "plot_columns": ["real_gdp_index"], "plot_labels": ["Real GDP index (2020 = 100)"],
    },
]

for item in definitions:
    frame = item["frame"]
    assert len(frame) >= 100 and frame.index.is_unique and frame.index.is_monotonic_increasing
    assert frame.index.equals(pd.date_range(frame.index.min(), frame.index.max(), freq=item["rule"], name="date"))
    assert frame.notna().all().all()
    frame.to_csv(ROOT / item["filename"], index_label="date", date_format="%Y-%m-%d", float_format="%.6f")
    # Compute the report from the exported values, rather than unrounded source floats.
    exported = pd.read_csv(ROOT / item["filename"], parse_dates=["date"]).set_index("date")
    item["frame"] = exported
    item["stats"] = {
        name: {"min": min(values), "max": max(values), "mean": mean(values), "std": stdev(values)}
        for name, series in exported.items() for values in [series.tolist()]
    }

plt.rcParams.update({
    "font.family": "serif",
    "font.serif": ["STIXGeneral"],
    "text.color": "#222222",
    "axes.labelcolor": "#222222",
    "axes.edgecolor": "#666666",
    "axes.linewidth": 0.6,
    "xtick.color": "#444444",
    "ytick.color": "#444444",
})


def plot(item, position):
    frame = item["frame"]
    fig, axes = plt.subplots(1, 2 if position == 1 else 1, figsize=(7.4, 1.75), dpi=180, squeeze=False)
    axes = axes[0]
    if position == 1:
        axes[0].plot(frame.index, frame["sp500_mean_close"], color="#222222", linewidth=1.2)
        axes[0].set_title("S&P 500 monthly mean", loc="left", fontsize=9)
        axes[0].set_ylabel("Index points", fontsize=8)
        axes[1].plot(frame.index, frame["vix_mean_close"], label="Mean", color="#222222", linewidth=1.2)
        axes[1].plot(frame.index, frame["vix_max_close"], label="Max close", color="#777777", linewidth=1.0, linestyle="--")
        axes[1].set_title("VIX monthly average and peak", loc="left", fontsize=9)
        axes[1].set_ylabel("Volatility points", fontsize=8)
        axes[1].legend(fontsize=7, frameon=False, loc="upper right")
    else:
        axes[0].plot(frame.index, frame[item["plot_columns"][0]], color="#222222", linewidth=1.2)
        axes[0].set_ylabel(item["plot_labels"][0], fontsize=8)
    for ax in axes:
        ax.spines[["top", "right"]].set_visible(False)
        ax.grid(axis="y", color="#DDDDDD", linewidth=0.5)
        ax.tick_params(labelsize=7)
    fig.tight_layout(pad=1.2)
    path = FIGURES / f"series-{position + 1}.png"
    fig.savefig(path, facecolor="white")
    plt.close(fig)
    return path


def latex_escape(text):
    replacements = {
        "\\": r"\textbackslash{}", "&": r"\&", "%": r"\%", "$": r"\$",
        "#": r"\#", "_": r"\_", "{": r"\{", "}": r"\}",
        "~": r"\textasciitilde{}", "^": r"\textasciicircum{}",
    }
    return "".join(replacements.get(char, char) for char in text)


latex = [r"""\documentclass[11pt,a4paper]{article}
\usepackage[T1]{fontenc}
\usepackage{lmodern}
\usepackage[margin=22mm]{geometry}
\usepackage{microtype}
\usepackage{booktabs}
\usepackage{graphicx}
\usepackage{titlesec}
\usepackage{fancyhdr}
\usepackage[hidelinks]{hyperref}
\hypersetup{pdftitle={Assignment 1 - Three Time Series Datasets}}
\setlength{\parindent}{0pt}
\setlength{\parskip}{5pt}
\renewcommand{\baselinestretch}{1.04}
\titleformat{\section}{\large\bfseries}{\thesection.}{0.6em}{}
\titlespacing*{\section}{0pt}{10pt}{7pt}
\pagestyle{fancy}
\fancyhf{}
\fancyfoot[L]{\footnotesize Data Forecasting - Assignment 1}
\fancyfoot[R]{\footnotesize\thepage}
\renewcommand{\headrulewidth}{0pt}
\renewcommand{\footrulewidth}{0pt}
\raggedbottom
\begin{document}
{\Large\bfseries Assignment 1: Time series datasets}\par
{\small Source snapshots retrieved 5 October 2026}\par
{\small Weekly, monthly and quarterly data; at least 100 observations each.
The two market datasets are multivariate; European macroeconomics adds a different domain.
All exported attributes have zero missing values. Calendar months and quarters are regular periods despite differing day counts.}\par
"""]
markdown = [
    "# Assignment 1 - Three time series datasets", "",
    f"Source snapshots retrieved {RETRIEVED}. Three regular frequencies: weekly, monthly and quarterly. All datasets contain at least 100 observations and no missing exported values. The stock and market-index datasets are multivariate; European macroeconomics adds domain diversity.", "",
    "Regularity is defined by calendar periods: consecutive Friday week labels, consecutive calendar months, and consecutive calendar quarters. Months and quarters naturally differ in day count. Non-trading days are excluded from stock-market aggregation; they are not filled with fabricated observations. Statistics use the exported CSV values and sample standard deviation (n - 1), with displayed results rounded to two decimals.", "",
]
for position, item in enumerate(definitions):
    if position:
        latex.append(r"\newpage")
    frame = item["frame"]
    latex += [
        r"\section{" + latex_escape(item["title"]) + "}",
        r"{\small " + latex_escape(item["subtitle"]) + r"}\par",
        r"{\small\textbf{CSV:} \texttt{" + latex_escape(item["filename"]) + r"}\\",
        rf"\textbf{{Frequency:}} {item['frequency']}\quad\textbf{{Observations:}} {len(frame)}\quad\textbf{{Attributes:}} {len(frame.columns) + 1} (including date)\\",
        r"\textbf{Time span:} " + latex_escape(item["span"]) + r"\\",
        latex_escape(item["coverage"]) + r"}\par",
        r"\textbf{Sources.}\par",
    ]
    for label, url in item["sources"]:
        latex.append(r"{\small\href{" + latex_escape(url) + "}{" + latex_escape(label) + r"}\quad\url{" + url.replace("%", r"\%") + r"}}\par")
    latex.append(r"\textbf{Attributes and missing data.}\par")
    for name, description in item["attributes"]:
        latex.append(r"{\small\raggedright\texttt{" + latex_escape(name) + "}: " + latex_escape(description) + r" \mbox{Missing: 0.}\par}")
    latex += [
        r"\textbf{Numeric summary.}\par",
        r"{\footnotesize\setlength{\tabcolsep}{3.5pt}\renewcommand{\arraystretch}{1.25}",
        r"\begin{tabular*}{\textwidth}{@{\extracolsep{\fill}}lrrrr@{}}",
        r"\toprule Attribute & Min & Max & Mean & Std. dev.\\ \midrule",
    ]
    for name, values in item["stats"].items():
        latex.append(r"\texttt{" + latex_escape(name) + "} & " + " & ".join(f"{values[key]:,.2f}" for key in ["min", "max", "mean", "std"]) + r"\\")
    latex += [
        r"\bottomrule\end{tabular*}}\par",
        r"{\footnotesize Sample standard deviation ($n-1$); calculated from exported CSV values. Display rounded to two decimals.}\par",
        r"\textbf{Reduction and preparation.}\par",
        latex_escape(item["processing"]) + r"\par",
        r"\textbf{Why this series is useful.}\par",
        latex_escape(item["interest"]) + r"\par",
        r"\includegraphics[width=\textwidth]{figures/" + plot(item, position).name + "}",
    ]
    markdown += [f"## {position + 1}. {item['title']}", "", f"CSV: `{item['filename']}`", "",
        f"- Frequency: {item['frequency']}", f"- Time span: {item['span']}", f"- {item['coverage']}",
        f"- Observations: {len(frame)}", f"- Attributes: {len(frame.columns) + 1}, including the time column", "",
        "Sources: " + "; ".join(f"[{label}]({url})" for label, url in item["sources"]), "",
        "### Attributes and missing data", ""]
    markdown += [f"- `{name}`: {description} Missing: **0**." for name, description in item["attributes"]]
    markdown += ["", "### Numeric summary", "", "| Attribute | Min | Max | Mean | Sample standard deviation |", "|---|---:|---:|---:|---:|"]
    markdown += ["| " + name + " | " + " | ".join(f"{values[key]:,.2f}" for key in ["min", "max", "mean", "std"]) + " |" for name, values in item["stats"].items()]
    markdown += ["", "### Reduction and preparation", "", item["processing"], "", "### Why this series is useful", "", item["interest"], ""]


pdf = ROOT / "dataset_report.pdf"
latex.append(r"\end{document}")
tex_source = ROOT / "support" / "dataset_report.tex"
tex_source.write_text("\n".join(latex) + "\n")
compilation = subprocess.run(
    ["tectonic", "--keep-logs", "--outdir", str(QA), str(tex_source)],
    cwd=tex_source.parent, check=True, capture_output=True, text=True,
)
(QA / "tectonic-output.txt").write_text(compilation.stdout + compilation.stderr)
print(compilation.stdout + compilation.stderr)
pdf.write_bytes((QA / pdf.name).read_bytes())
(ROOT / "dataset_report.md").write_text("\n".join(markdown))

source_urls = {
    "nvda_daily.json": "https://query1.finance.yahoo.com/v8/finance/chart/NVDA?range=10y&interval=1d",
    "sp500_daily.json": "https://query1.finance.yahoo.com/v8/finance/chart/%5EGSPC?range=10y&interval=1d",
    "vix_daily.csv": "https://cdn.cboe.com/api/global/us_indices/daily_prices/VIX_History.csv",
    "euro_area_gdp_eurostat.json": "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/namq_10_gdp?lang=EN&freq=Q&unit=CLV_I20&s_adj=SCA&na_item=B1GQ&geo=EA20&sinceTimePeriod=1995-Q1",
}
manifest = {
    "retrieved_on": RETRIEVED,
    "source_snapshots": [{"file": f"raw/{name}", "download_url": url, "sha256": sha256((RAW / name).read_bytes()).hexdigest()} for name, url in source_urls.items()],
    "datasets": [{"file": item["filename"], "frequency": item["frequency"], "observations": len(item["frame"]), "attributes": ["date"] + item["frame"].columns.tolist(), "start_label": str(item["frame"].index.min().date()), "end_label": str(item["frame"].index.max().date()), "missing": {name: 0 for name, _ in item["attributes"]}, "statistics": item["stats"]} for item in definitions],
    "standard_deviation": "Sample standard deviation, ddof=1, computed from exported values",
    "vix_dates_excluded_to_align_with_sp500": excluded_vix_dates.strftime("%Y-%m-%d").tolist(),
    "eurostat_series": {"dataset": "namq_10_gdp", "filters": expected_dimensions, "updated": gdp_raw["updated"], "source_observations": len(gdp_raw["value"])},
}
(ROOT / "support" / "source_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
with zipfile.ZipFile(ROOT / "assignment_1_submission.zip", "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for filename in [item["filename"] for item in definitions] + [pdf.name]:
        archive.write(ROOT / filename, arcname=filename)
print(json.dumps(manifest["datasets"], indent=2))
print(f"Created {pdf} and submission ZIP")
