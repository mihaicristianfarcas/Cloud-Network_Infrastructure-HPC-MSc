"""Assignment 2: plots for the three time series.

Run from this folder:  python analysis.py
It reads the three CSV files and saves every plot as a PNG in the figures/ folder.

Plots made (as the assignment asks):
  - a line plot for every dataset
  - seasonal plot + seasonal subseries plot for the seasonal dataset (GDP)
  - pairwise scatter plots for the multivariate datasets (NVIDIA, S&P 500/VIX)
  - lag plots (lags 1 to 12) for every variable
"""

from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap

Path("figures").mkdir(exist_ok=True)

# ---------------------------------------------------------------- style
plt.rcParams.update({
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": True,
    "axes.axisbelow": True,  # grid lines behind the data
    "grid.color": "#e6e6e6",
    "axes.titlesize": 10,
    "axes.labelsize": 9,
    "xtick.labelsize": 8,
    "ytick.labelsize": 8,
})
BLUE = "#2a78d6"
ORANGE = "#eb6834"
# Light blue = old, dark blue = recent. Used whenever colour shows time.
YEAR_COLORS = LinearSegmentedColormap.from_list("years", ["#86b6ef", "#0d366b"])
# One fixed colour per quarter (checked to be colour-blind safe).
QUARTER_COLORS = {1: "#2a78d6", 2: "#eda100", 3: "#e87ba4", 4: "#008300"}


def save(fig, name):
    fig.savefig(f"figures/{name}.png", dpi=150)
    plt.close(fig)
    print(f"saved figures/{name}.png")


def lag_plot(series, title, name, color_by_quarter=False):
    """12 small scatter plots, one per lag k = 1..12.

    Each point is one time t: x = the value k periods earlier, y = the value now.
    Points close to the dashed diagonal mean "the value now is about the same as k periods ago".
    r is the correlation between the two (close to 1 = strong relationship).
    """
    fig, axes = plt.subplots(3, 4, figsize=(10, 8), layout="constrained")
    for k, ax in zip(range(1, 13), axes.flat):
        lagged = series.shift(k)  # the value k periods earlier, lined up with the current one
        if color_by_quarter:
            for q, color in QUARTER_COLORS.items():
                now_in_q = series.index.quarter == q
                ax.scatter(lagged[now_in_q], series[now_in_q], s=8, color=color, label=f"Q{q}")
        else:
            ax.scatter(lagged, series, s=6, color=BLUE, alpha=0.6)
        # Diagonal line y = x (drawn through the smallest value so the axes don't stretch to 0)
        ax.axline((series.min(), series.min()), slope=1, color="grey", linestyle="--", linewidth=0.8)
        ax.set_title(f"lag {k}   (r = {series.autocorr(k):.2f})")
    if color_by_quarter:
        axes[0, 0].legend(title="quarter of y(t)", fontsize=7, title_fontsize=7)
    fig.supxlabel("value k periods earlier, y(t - k)")
    fig.supylabel("value now, y(t)")
    fig.suptitle(title)
    save(fig, name)


# ---------------------------------------------------------------- load the data
nvda = pd.read_csv("01_nvda_weekly.csv", parse_dates=["date"], index_col="date")
market = pd.read_csv("02_sp500_vix_monthly.csv", parse_dates=["date"], index_col="date")
gdp = pd.read_csv("03_euro_area_real_gdp_nsa_quarterly.csv", parse_dates=["date"], index_col="date")

price = nvda["nvda_adjusted_close_usd"]
volume = nvda["nvda_volume_shares"] / 1e9  # in billions of shares, easier to read
sp500 = market["sp500_mean_close"]
vix_mean = market["vix_mean_close"]
vix_max = market["vix_max_close"]
gdp = gdp["real_gdp_index"]


# ================================================================ 1. NVIDIA (weekly)
# 1a. Line plot of both variables
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(9, 6), layout="constrained")
ax1.plot(price, color=BLUE)
ax1.set_title("NVIDIA weekly adjusted close price (USD per share)")
ax2.plot(volume, color=BLUE)
ax2.set_title("NVIDIA weekly trading volume (billion shares)")
save(fig, "1a_nvda_line")

# 1b. Scatter plot: price against volume (only one pair, since there are two variables)
fig, ax = plt.subplots(figsize=(7, 5.2), layout="constrained")
points = ax.scatter(volume, price, c=nvda.index.year, cmap=YEAR_COLORS, s=12)
# Colour key under the plot (horizontal), so it is not read against the price axis
fig.colorbar(points, ax=ax, label="year (colour of the dots)", orientation="horizontal", shrink=0.6)
ax.set_xlabel("weekly volume (billion shares)")
ax.set_ylabel("adjusted close (USD)")
ax.set_title("NVIDIA: price vs. volume (one point per week)")
save(fig, "1b_nvda_scatter")

# 1c, 1d. Lag plots
lag_plot(price, "NVIDIA adjusted close: lag plots (lags in weeks)", "1c_nvda_lag_price")
lag_plot(volume, "NVIDIA volume: lag plots (lags in weeks)", "1d_nvda_lag_volume")


# ================================================================ 2. S&P 500 and VIX (monthly)
# 2a. Line plot. S&P 500 and VIX have very different scales, so they get separate panels.
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(9, 6), layout="constrained")
ax1.plot(sp500, color=BLUE)
ax1.set_title("S&P 500: monthly mean of daily closes (index points)")
ax2.plot(vix_mean, color=BLUE, label="VIX monthly mean")
ax2.plot(vix_max, color=ORANGE, label="VIX monthly max")
ax2.set_title("VIX: monthly mean and maximum daily close")
ax2.legend(fontsize=8)
save(fig, "2a_market_line")

# 2b. Pairwise scatter plots: every pair of the three variables
pairs = [
    (sp500, vix_mean, "S&P 500 mean", "VIX mean"),
    (sp500, vix_max, "S&P 500 mean", "VIX max"),
    (vix_mean, vix_max, "VIX mean", "VIX max"),
]
fig, axes = plt.subplots(1, 3, figsize=(11, 4.6), layout="constrained")
for (x, y, x_label, y_label), ax in zip(pairs, axes):
    points = ax.scatter(x, y, c=market.index.year, cmap=YEAR_COLORS, s=12)
    ax.set_xlabel(x_label)
    ax.set_ylabel(y_label)
    ax.set_title(f"{y_label} vs. {x_label}")
fig.colorbar(points, ax=axes, label="year (colour of the dots)", orientation="horizontal", shrink=0.4)
save(fig, "2b_market_scatter")

# 2c-2e. Lag plots
lag_plot(sp500, "S&P 500 monthly mean: lag plots (lags in months)", "2c_sp500_lag")
lag_plot(vix_mean, "VIX monthly mean: lag plots (lags in months)", "2d_vix_mean_lag")
lag_plot(vix_max, "VIX monthly max: lag plots (lags in months)", "2e_vix_max_lag")


# ================================================================ 3. Euro-area real GDP, NOT seasonally adjusted (quarterly)
# 3a. Line plot
fig, ax = plt.subplots(figsize=(9, 3.8), layout="constrained")
ax.plot(gdp, color=BLUE)
ax.set_title("Euro-area real GDP index, not seasonally adjusted (2020 = 100)")
save(fig, "3a_gdp_line")

# 3b. Seasonal plot: one line per year, x axis = quarter of the year
first_year, last_year = gdp.index.year.min(), gdp.index.year.max()
fig, ax = plt.subplots(figsize=(7, 5.6), layout="constrained")
for year, values in gdp.groupby(gdp.index.year):
    shade = (year - first_year) / (last_year - first_year)  # 0 = oldest year, 1 = newest
    ax.plot(values.index.quarter, values, color=YEAR_COLORS(shade), marker="o", markersize=3)
ax.set_xticks([1, 2, 3, 4], ["Q1", "Q2", "Q3", "Q4"])
ax.annotate("2020 (COVID-19)", xy=(2, gdp["2020-04-01"]), xytext=(2.15, 86), fontsize=8,
            arrowprops={"arrowstyle": "->", "color": "grey"})
year_scale = plt.cm.ScalarMappable(cmap=YEAR_COLORS, norm=plt.Normalize(first_year, last_year))
fig.colorbar(year_scale, ax=ax, label="year (colour of the line)", orientation="horizontal", shrink=0.6)
ax.set_title("Euro-area real GDP: seasonal plot (one line per year)")
save(fig, "3b_gdp_seasonal")

# 3c. Seasonal subseries plot: one panel per quarter, showing that quarter across all years.
#     The black line is the average of that quarter.
fig, axes = plt.subplots(1, 4, figsize=(10, 3.8), layout="constrained")
for q, ax in zip([1, 2, 3, 4], axes):
    values = gdp[gdp.index.quarter == q]
    ax.plot(values.index.year, values, color=QUARTER_COLORS[q])
    ax.axhline(values.mean(), color="black", linewidth=1)
    ax.set_title(f"Q{q}   (average {values.mean():.1f})")
fig.suptitle("Euro-area real GDP: seasonal subseries plot")
save(fig, "3c_gdp_subseries")

# 3d. Lag plots, coloured by quarter so the seasonal pattern is visible
lag_plot(gdp, "Euro-area real GDP: lag plots (lags in quarters)", "3d_gdp_lag", color_by_quarter=True)
