# Assignment 1 - Three time series datasets

Source snapshots retrieved 2026-10-05. Three regular frequencies: weekly, monthly and quarterly. All datasets contain at least 100 observations and no missing exported values. The stock and market-index datasets are multivariate; European macroeconomics adds domain diversity.

Regularity is defined by calendar periods: consecutive Friday week labels, consecutive calendar months, and consecutive calendar quarters. Months and quarters naturally differ in day count. Non-trading days are excluded from stock-market aggregation; they are not filled with fabricated observations. Statistics use the exported CSV values and sample standard deviation (n - 1), with displayed results rounded to two decimals.

## 1. NVIDIA stock

CSV: `01_nvda_weekly.csv`

- Frequency: Weekly
- Time span: 2020-10-16 to 2026-10-02 (Friday labels)
- Underlying trading dates: 2020-10-12 to 2026-10-02.
- Observations: 312
- Attributes: 3, including the time column

Sources: [Yahoo Finance: NVDA historical data](https://finance.yahoo.com/quote/NVDA/history/)

### Attributes and missing data

- `date`: Friday labelling a Saturday-Friday week; YYYY-MM-DD. Missing: **0**.
- `nvda_adjusted_close_usd`: Last trading day's adjusted close in the week, USD per share. Yahoo adjusts this for splits and dividends. Missing: **0**.
- `nvda_volume_shares`: Sum of the daily trading volumes reported by Yahoo within the week, in shares. Missing: **0**.

### Numeric summary

| Attribute | Min | Max | Mean | Sample standard deviation |
|---|---:|---:|---:|---:|
| nvda_adjusted_close_usd | 11.19 | 233.95 | 82.12 | 70.38 |
| nvda_volume_shares | 400,749,200.00 | 4,308,297,000.00 | 1,736,870,065.38 | 815,917,634.39 |

### Reduction and preparation

Daily observations were aggregated into Saturday-Friday weeks: last adjusted close and sum of volume. Only the most recent 312 complete weeks were retained. Open, high, low and unadjusted close were removed. A holiday Friday keeps the last actual quote within that week; the date is a period label. No prices were interpolated or forward-filled.

### Why this series is useful

An individual stock with strong trends and changing trading activity. Useful for studying price versus volume and the effect of differencing or returns on a trending series.

## 2. S&P 500 and VIX

CSV: `02_sp500_vix_monthly.csv`

- Frequency: Monthly
- Time span: 2017-10-01 to 2026-09-01 (month-start labels)
- Covered calendar months: 2017-10 through 2026-09, ending 2026-09-30.
- Observations: 108
- Attributes: 4, including the time column

Sources: [Yahoo Finance: S&P 500 historical data](https://finance.yahoo.com/quote/%5EGSPC/history/); [Cboe: VIX historical data](https://www.cboe.com/tradable_products/vix/vix_historical_data)

### Attributes and missing data

- `date`: First day labelling the calendar month; YYYY-MM-DD. Missing: **0**.
- `sp500_mean_close`: Arithmetic mean of the daily S&P 500 closes, in index points; a price index excluding dividends. Missing: **0**.
- `vix_mean_close`: Arithmetic mean of daily VIX closes, in volatility index points (annualized percentage units). Missing: **0**.
- `vix_max_close`: Largest daily VIX close in the month, in the same units; this is not an intraday high. Missing: **0**.

### Numeric summary

| Attribute | Min | Max | Mean | Sample standard deviation |
|---|---:|---:|---:|---:|
| sp500_mean_close | 2,557.00 | 7,711.32 | 4,360.69 | 1,436.13 |
| vix_mean_close | 10.13 | 57.74 | 19.35 | 6.62 |
| vix_max_close | 11.30 | 82.69 | 24.51 | 10.14 |

### Reduction and preparation

Daily closes were grouped by calendar month: mean for each index and maximum daily close for VIX. The most recent 108 complete months were retained; incomplete October 2026 was excluded. Within this window, 33 extra VIX holiday observations were excluded to use the same S&P 500 trading dates for both indexes. Other daily attributes were removed. No missing values were filled.

### Why this series is useful

A multivariate dataset contrasting broad equity-market trends with volatility spikes. The maximum VIX close retains information about stress that a monthly average can smooth out. No relationship between the variables is assumed.

## 3. Euro-area real GDP index

CSV: `03_euro_area_real_gdp_quarterly.csv`

- Frequency: Quarterly
- Time span: 1996-07-01 to 2026-04-01 (quarter-start labels)
- Covered quarters: 1996Q3 through 2026Q2, ending 2026-06-30.
- Observations: 120
- Attributes: 2, including the time column

Sources: [Eurostat: quarterly GDP (namq_10_gdp)](https://ec.europa.eu/eurostat/databrowser/view/namq_10_gdp/default/table?lang=en)

### Attributes and missing data

- `date`: First day labelling the quarter (January, April, July or October); YYYY-MM-DD. Missing: **0**.
- `real_gdp_index`: Real GDP in chain-linked volumes, index 2020 = 100; seasonally and calendar adjusted. Covers the fixed 20-country euro-area group (EA20). Measures economic output excluding inflation. Missing: **0**.

### Numeric summary

| Attribute | Min | Max | Mean | Sample standard deviation |
|---|---:|---:|---:|---:|
| real_gdp_index | 74.33 | 114.67 | 95.81 | 10.51 |

### Reduction and preparation

Eurostat filters: frequency Q; geography EA20; GDP B1GQ; unit CLV_I20; adjustment SCA. The selected source contains 126 quarters from 1995 Q1 through 2026 Q2; only the latest 120 were retained, removing the oldest six. Quarter codes were converted to quarter-start dates. Constant series metadata were omitted from the CSV. Original index values were preserved without aggregation or imputation.

### Why this series is useful

Adds a European economic domain and slower frequency. Useful for studying long-term growth, recessions and shocks such as the COVID-19 contraction and subsequent rebound. The source's seasonal and calendar adjustment helps focus on economic cycles.
