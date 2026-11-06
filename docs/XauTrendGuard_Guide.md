# XauTrendGuard: Gold (XAUUSD) Expert Advisor for MetaTrader 5

> **Risk warning.** XauTrendGuard is a risk-controlled automated trading system. It does **not** guarantee profits.
> No backtest results are claimed in this document. You must backtest, run out-of-sample / walk-forward
> validation and forward-test on a demo account before you trade real money. Leveraged gold CFDs can lose
> money quickly.

---

## Contents

1. [What's in the package](#1-whats-in-the-package)
2. [How the strategy works](#2-how-the-strategy-works)
3. [Risk management](#3-risk-management)
4. [Trade management](#4-trade-management)
5. [Sessions, rollover and news](#5-sessions-rollover-and-news)
6. [Installing on MT5 desktop](#6-installing-on-mt5-desktop)
7. [Configuration guide (all inputs)](#7-configuration-guide)
8. [Recommended initial parameters](#8-recommended-initial-parameters)
9. [Backtesting & optimisation](#9-backtesting--optimisation)
10. [The dashboard](#10-the-dashboard)
11. [Troubleshooting](#11-troubleshooting)
12. [Code architecture](#12-code-architecture)

---

## 1. What's in the package

| Path | Purpose |
|---|---|
| `MQL5/Experts/XauTrendGuard/XauTrendGuard.mq5` | Main EA file (event handlers, engine, dashboard wiring) |
| `MQL5/Experts/XauTrendGuard/Modules/*.mqh` | Modules: inputs, logger, symbol guard, time/sessions, news, signals, risk, execution, trade manager, dashboard, stats |
| `MQL5/Presets/XauTrendGuard_Default.set` | Recommended starting parameters |
| `MQL5/Presets/XauTrendGuard_Conservative.set` | Lower-risk profile |
| `MQL5/Files/XauTrendGuard_News_TEMPLATE.csv` | Template for the news CSV used in backtests |
| `.github/workflows/compile-mql5.yml` | CI job: installs MT5 on Windows, compiles the EA, uploads the `.ex5` |

**Compiled `.ex5`.** Each push runs the GitHub Actions workflow *Compile MQL5 EAs (XauTrendGuard, Bot15)*, which
compiles the EA with the official MetaEditor. The `.ex5` and the compiler log are attached to the run as the
artifact `compiled-ex5`. You can also compile it yourself in MetaEditor (press F7, see §6).

---

## 2. How the strategy works

XauTrendGuard is a **trend-following pullback** system. It waits for an established trend on the higher
timeframes, then for price to pull back to the EMA20/EMA50 zone on M15. It enters only when momentum,
a candlestick pattern and the M5 timeframe all confirm the trend is resuming. **Every value is read from
closed candles (shift ≥ 1)**, so signals don't repaint and there is no look-ahead bias in backtests.

### Timeframe roles

| TF | Role | Rule (BUY; SELL is the mirror image) |
|---|---|---|
| **H4** | Overall direction | EMA50 > EMA200 and close > EMA200 (optional strict: EMA20 > EMA50 too) |
| **H1** | Trend confirmation | EMA20 > EMA50, close > EMA50, and (EMA50 > EMA200 **or** a clearly defined trend: EMA20 & EMA50 rising over `InpSlopeBars`) |
| **M15** | Setup | See the checklist below |
| **M5** | Entry timing | Last closed M5 candle is bullish and closes above M5 EMA20 |

### M15 setup checklist (all must pass)

1. **EMA stack:** EMA20 > EMA50, and EMA50 > EMA200 *or* a clearly defined trend (H4 bullish + rising EMA20/EMA50).
2. **Pullback:** within the last `InpPullbackBars` M15 candles, the low touched the EMA20 zone
   (EMA20 + `InpPullbackTolATR` × ATR). That zone also covers a deeper retrace to EMA50.
3. **Structure intact:** no pullback candle closed below EMA50 − tolerance.
4. **Not over-extended:** the signal candle closes above EMA20, at most `InpMaxExtensionATR` × ATR away.
5. **Candlestick confirmation:** bullish engulfing, bullish pin bar/hammer, or a strong bullish close
   (body ≥ 50 % of range, close in the top 30 %).
6. **RSI momentum:** RSI(14) between 50 and 70 and rising (SELL: 30–50 and falling).
7. **Volatility regime:** ATR between 0.5× and 2.5× its 100-bar average. This skips dead markets and
   extreme spikes.

### Stop loss & take profit

* **SL (default "structure + ATR"):** the further of (a) 1.5 × ATR(M15) from entry, or (b) beyond the swing
  low/high of the last 10 M15 bars plus a 0.2 × ATR buffer. The SL distance is kept within 0.8–3.0 × ATR;
  if a wider stop is needed, the trade is **skipped**.
* **TP:** `InpRiskReward` × SL distance. The minimum is **2.0** and the EA enforces it even if you set less.
  Prices are rounded *away* from entry so the real R:R never falls below 1:2.
* Optional `InpCheckRoomToTarget`: skip the trade if an H1 swing high (or low, for sells) sits between entry
  and the 1:2 target.

### Why several confirmations?

A single indicator flags too many low-quality trades. Requiring the higher-timeframe trend, a pullback,
intact structure, a candle pattern, RSI momentum, an M5 trigger and a sensible spread and volatility means
the EA trades **rarely**, by design. Expect from 0 to a few trades per week, depending on market conditions.

---

## 3. Risk management

| Rule | Default | Notes |
|---|---|---|
| Risk per trade | 1 % of **equity** | Clamped to 0.25 %–2 % whatever you enter |
| Lot size | automatic | `risk money ÷ loss per lot at SL` (uses `OrderCalcProfit`, so it handles any account currency). **Always rounded down** to the volume step |
| Below minimum lot | trade skipped | It never rounds up to the minimum lot (that would exceed your risk) |
| Max simultaneous positions | 3 | Hard cap of 3 (higher values are rejected) |
| Max trades per day | 4 | Hard cap of 4 |
| Max daily loss | 3 % | Equity vs start-of-day balance, including floating P/L. When it is hit: no new trades until the next server day, and positions are closed (`InpCloseOnDailyLimit`) |
| Max weekly drawdown | 6 % | Worst of the drop from the week-start balance and the drop from this week's equity peak. Stops trading until Monday |
| Max total open risk | 3 % | Sum of risk on all positions whose SL is still behind entry |
| Margin check | 90 % of free margin | Lot size is reduced if margin is short, or the trade is skipped |

**Never used:** martingale, grid, averaging down, recovery sizing. Lot size depends **only** on the SL
distance and the risk %. A 2nd or 3rd position in the same direction is allowed only when:

* no existing position is in loss, and
* (default) every existing position already has its SL at breakeven or better (`InpRequireBEBeforeAdd`).

Opposite-direction positions are never opened while a position is open (no hedging).

Daily and weekly limits are measured at **account level**: deposits, withdrawals and other EAs' trades
change the balance they're based on. For clean limits, run the EA on a dedicated account or sub-account.

---

## 4. Trade management

* **Breakeven:** at +1 R the SL moves to entry + 0.05 R, which covers spread and commission.
* **Trailing stop (optional, on by default):** from +1.5 R, the SL trails 2 × ATR(M15) behind price. It only
  ever tightens.
* **Opposite-signal exit:** on each new M15 bar the EA checks for a *complete* opposite setup (every M15 rule
  above). `InpOppExitMode` decides what happens: Off / Always close / Close only in profit / Close only in loss.
* **H1 flip exit (optional):** close when the H1 EMA20 crosses EMA50 against the position.
* **Weekend close (optional):** close everything on Friday at `InpWeekendCloseTime` (Poland time).
* **One entry per M15 setup candle.** The last traded setup is rebuilt from history after a restart, so the
  EA doesn't enter the same setup twice.
* **Execution safety:**
  * spread check (absolute limit plus a spike limit relative to the running average)
  * broker stop level and freeze level are respected
  * filling mode is set from the symbol, with FOK → IOC → RETURN fallback
  * retries on requote, price change, timeout and connection errors
  * after 3 consecutive failures, a 15-minute cooldown

---

## 5. Sessions, rollover and news

### Sessions (Poland local time, Europe/Warsaw)

Poland's summer time (CET ↔ CEST, last Sunday of March / October) is handled automatically. Defaults:

| Session | Default (PL time) |
|---|---|
| London | 09:00 – 17:30 |
| New York | 14:30 – 21:30 |
| London/NY overlap | 14:30 – 17:30 |

Turn each session on or off with `InpUseLondon`, `InpUseNewYork` and `InpUseOverlap`. A new trade is allowed
if the current time falls inside **any enabled** window. Example: to trade only the overlap, disable London
and New York and keep Overlap on.

> The US and EU change clocks on different dates. For about 3 weeks in March and 1 week in Oct/Nov, New York
> opens one hour earlier in Polish time. Widen the NY window if you want to cover those weeks exactly.

### Broker time zone

Converting to Polish time requires the broker server's UTC offset:

* **AUTO (default):** live, it is measured as `TimeTradeServer() − TimeGMT()`. In the Strategy Tester the
  real GMT is not available, so the EA assumes the most common broker convention, **GMT+2 in winter / GMT+3
  in summer (US DST)**, and logs a warning.
* **NY_CLOSE:** always use that GMT+2/+3 rule.
* **FIXED:** use `InpServerGMTOffset` hours. Choose this for backtests if your broker uses another convention.

### Rollover & weekend

No new trades from `InpRolloverBeforeMin` minutes before to `InpRolloverAfterMin` minutes after **server
midnight**, when swaps are applied and spreads widen. No new trades on Friday after `InpFridayCutoff` or at
the weekend.

### News filter

* **Live:** uses the built-in **MT5 economic calendar** (`CalendarValueHistory`, country US, currency USD).
  It blocks new trades from **30 min before to 30 min after** every high-impact USD event. Gold-critical
  events (**CPI, NFP/Non-farm payrolls, FOMC, Fed interest-rate decisions, PCE, Fed Chair speeches**) are
  always included, even when the calendar rates them moderate. `InpNewsOnlyKeyEvents=true` limits the filter
  to these key events.
* **Honest status:** if the calendar returns no data, the dashboard and journal show
  **`INACTIVE - calendar unavailable`**. The EA never pretends the filter is working.
  Set `InpNewsBlockIfOffline=true` to block all new trades while news data is missing.
* **Strategy Tester:** MT5 calendar functions **don't work in the tester**, so the filter reports
  `INACTIVE - no calendar in tester`. To backtest with news protection, provide a CSV file (below).
* Open positions are **not** closed by news. Their SL/TP stay in place.

#### News CSV (for backtests)

Put a file in the **common** data folder (`File → Open Data Folder`, up two levels → `Common\Files`), e.g.
`XauNews.csv`, and set `InpNewsCsvFile=XauNews.csv`. Format: one event per line, **time in UTC**:

```
# time (UTC),title
2024.06.07 12:30,Nonfarm Payrolls
2024.06.12 12:30,CPI m/m
2024.06.12 18:00,FOMC Interest Rate Decision
```

Get historical event times from any economic-calendar export. A template is in
`MQL5/Files/XauTrendGuard_News_TEMPLATE.csv`.

---

## 6. Installing on MT5 desktop

1. **Install MetaTrader 5** from your broker and log in (start with a **demo** account).
2. In MT5: **File → Open Data Folder**. This opens the folder that contains `MQL5`.
3. Copy the whole folder `MQL5/Experts/XauTrendGuard/` (main `.mq5` and the `Modules` subfolder) into
   `<Data Folder>/MQL5/Experts/`. You should end up with:
   ```
   MQL5/Experts/XauTrendGuard/XauTrendGuard.mq5
   MQL5/Experts/XauTrendGuard/Modules/Inputs.mqh ... Stats.mqh
   ```
   Optional: copy `MQL5/Presets/*.set` into `<Data Folder>/MQL5/Presets/`.
4. **Compile:** in MT5 press **F4** (MetaEditor), open `Experts/XauTrendGuard/XauTrendGuard.mq5` and press
   **F7**. The Errors tab should show `0 errors`. Or download the prebuilt `XauTrendGuard.ex5` from the CI
   artifact and put it in the same folder.
5. Back in MT5, **Navigator → Expert Advisors → right-click → Refresh**.
6. Open a **Gold chart** (XAUUSD, XAUUSD.a, XAUUSDm, GOLD ... whatever your broker calls it). Any chart
   timeframe works; M15 is convenient. Add the symbol from Market Watch with *Show All* if it's missing.
7. Drag **XauTrendGuard** onto the chart. In the dialog:
   * **Common** tab: tick **Allow Algo Trading**.
   * **Inputs** tab: adjust, or **Load** a `.set` file.
8. Turn on the **Algo Trading** button in the MT5 toolbar (green). The dashboard should show **ACTIVE**.
9. Check the **Experts** tab of the Toolbox. You should see `Gold symbol: XAUUSD - verified Gold ...` and the
   news filter status.
10. To run 24/5 unattended, use a VPS (MetaQuotes built-in VPS or any Windows VPS). The PC must stay on with
    MT5 running and connected.

**Gold-only guard:** at start-up the EA checks the symbol's name, profit currency (must be USD), base
currency and description. It refuses silver, other metals, gold in other currencies and gold indices or ETFs.
If the chart isn't gold and `InpAutoDetectGold=true`, it looks for a gold symbol in Market Watch, trades that
symbol (timer-driven) and says so on the dashboard. If no verified gold symbol is found, the EA **won't
start**.

---

## 7. Configuration guide

| Group | Input | Default | Meaning |
|---|---|---|---|
| General | `InpMagic` | 26110601 | Identifies this EA's trades. Use a different value per chart/account |
| | `InpAutoDetectGold` | true | Find gold automatically if the chart isn't gold |
| | `InpSymbolOverride` | "" | Force a specific symbol name (it must still pass the gold check) |
| Strategy | `InpEmaFast/Mid/Slow` | 20/50/200 | EMA periods |
| | `InpRsiPeriod` | 14 | RSI on M15 |
| | `InpRsiBuyMin/Max` | 50/70 | Bullish momentum band |
| | `InpRsiSellMin/Max` | 30/50 | Bearish momentum band |
| | `InpAtrPeriod` | 14 | ATR on M15 |
| | `InpRequireH4Bias` | true | H4 must agree |
| | `InpStrictH4Stack` | false | H4 also needs EMA20 > EMA50 |
| | `InpSlopeBars` | 5 | Bars used for the "clearly defined trend" slope |
| | `InpPullbackBars` | 4 | M15 lookback for the pullback touch |
| | `InpPullbackTolATR` | 0.25 | Size of the EMA20 touch zone |
| | `InpMaxExtensionATR` | 1.2 | Max distance from EMA20 at entry |
| | `InpUseM5Trigger` | true | Require the M5 confirmation candle |
| | `InpMaxAtrVsAverage` / `InpMinAtrVsAverage` | 2.5 / 0.5 | Volatility regime filter |
| SL/TP | `InpSLMode` | Structure+ATR | or ATR only |
| | `InpSLAtrMult` | 1.5 | ATR multiple for the SL |
| | `InpSLBufferATR` | 0.2 | Buffer beyond the swing |
| | `InpSwingLookback` | 10 | M15 bars searched for the swing |
| | `InpMinSLAtr` / `InpMaxSLAtr` | 0.8 / 3.0 | SL distance limits; skip if wider |
| | `InpRiskReward` | 2.0 | TP multiple (min 2.0 enforced) |
| | `InpCheckRoomToTarget` | false | Skip if an H1 swing blocks the target |
| Risk | `InpRiskPercent` | 1.0 | 0.25–2.0 |
| | `InpMaxPositions` | 3 | 1–3 |
| | `InpMaxTradesPerDay` | 4 | 1–4 |
| | `InpMaxDailyLossPct` | 3.0 | ≤ 3.0 |
| | `InpMaxWeeklyDDPct` | 6.0 | ≤ 6.0 |
| | `InpMaxOpenRiskPct` | 3.0 | Total open-risk ceiling |
| | `InpCloseOnDailyLimit` / `Weekly` | true | Flatten when a limit is hit |
| | `InpMaxLotCap` | 0 | Absolute lot ceiling (0 = broker max) |
| | `InpRequireBEBeforeAdd` | true | Pyramiding only when the existing positions are risk-free |
| Management | `InpUseBreakeven`, `InpBETriggerR`, `InpBELockR` | true, 1.0, 0.05 | Breakeven |
| | `InpUseTrailing`, `InpTrailStartR`, `InpTrailAtrMult` | true, 1.5, 2.0 | ATR trailing stop |
| | `InpOppExitMode` | Always close | Opposite-signal exit rule |
| | `InpExitOnH1Flip` | false | H1 EMA cross exit |
| | `InpCloseBeforeWeekend`, `InpWeekendCloseTime` | false, 21:30 | Friday flat |
| Execution | `InpMaxSpreadUsd` | 0.60 | Max spread in price units ($/oz). With 2-digit quotes, 0.60 = 60 points |
| | `InpSpreadSpikeMult` | 2.5 | Block when spread > 2.5× its running average |
| | `InpSlippagePoints` | 30 | Max deviation |
| | `InpMaxRetries`, `InpMaxConsecErrors`, `InpErrorCooldownMin` | 3, 3, 15 | Error handling |
| Sessions | see §5 | | |
| News | `InpUseNewsFilter`, `InpNewsBeforeMin`, `InpNewsAfterMin` | true, 30, 30 | |
| | `InpNewsOnlyKeyEvents` | false | Only CPI/NFP/FOMC/Fed/PCE |
| | `InpNewsBlockIfOffline` | false | Block trading if no news data (recommended `true` for live) |
| | `InpNewsCsvFile` | "" | CSV for backtests (Common\Files) |
| Dashboard | `InpShowDashboard`, `InpDashX/Y`, `InpDashFontSize` | | Panel position and size |
| Testing | `InpOptCriterion`, `InpOptMinTrades`, `InpWriteReport` | Composite, 30, true | §9 |
| | `InpLogLevel`, `InpLogToFile` | Normal, false | Logging |

---

## 8. Recommended initial parameters

Start with **`XauTrendGuard_Default.set`** (the defaults above) on a **demo account for at least 4–8 weeks**.
Suggested profiles:

| Profile | Risk % | Max pos | Trades/day | Daily / weekly limit | Trailing | Notes |
|---|---|---|---|---|---|---|
| Conservative | 0.5 | 2 | 2 | 2 % / 4 % | on | `XauTrendGuard_Conservative.set`, `InpNewsBlockIfOffline=true` |
| Default | 1.0 | 3 | 4 | 3 % / 6 % | on | Balanced starting point |
| Max allowed | 2.0 | 3 | 4 | 3 % / 6 % | on | Not recommended until validated |

Also check:

* **Spread:** look at your broker's normal gold spread on the dashboard (`Spread` line) and set
  `InpMaxSpreadUsd` to about 1.5–2× that value.
* **Minimum lot vs account size:** with 1 % risk and a typical gold SL of $8–$15/oz, 0.01 lot (1 oz on most
  brokers) risks about $8–15, so accounts under roughly $1,000 can often not trade at 1 %. The dashboard
  shows "Risk too small for min lot" when that happens.

---

## 9. Backtesting & optimisation

### Single backtest

1. MT5 → **View → Strategy Tester** (Ctrl+R).
2. Expert: `XauTrendGuard\XauTrendGuard`. Symbol: your gold symbol. Timeframe: **M5** or M15. Signals use
   explicit timeframes, so the chart TF only affects the visual chart.
3. Modelling: **"Every tick based on real ticks"** (most accurate spreads) or "Every tick". Avoid
   "Open prices only": breakeven and trailing need intrabar prices.
4. Dates: at least **3–5 years**. The tester loads the H4 warm-up history (EMA200) automatically.
5. Deposit and leverage as on your real account. **Inputs:** load the `.set` file. For backtests set
   `InpServerTZMode` to match your broker (FIXED if it isn't GMT+2/+3), and optionally `InpNewsCsvFile`.
6. Run. When it finishes, the **Journal** prints the XauTrendGuard performance block, and
   `Common\Files\XauTrendGuard_Report_<symbol>.csv` is written with:
   total trades, wins/losses, **win rate**, **net profit**, gross profit/loss, **profit factor**,
   **expected payoff**, average win/loss, **realised reward:risk**, **average R per trade**,
   **max consecutive losses/wins**, **max balance and equity drawdown**.
   The standard MT5 *Backtest* tab shows the same figures as well as Sharpe and recovery factor.

### Test across market regimes

Run separate tests on periods with different character, and compare profit factor, drawdown and consecutive
losses. **Do not tune parameters for one regime.** For example:

| Regime | Example period (XAUUSD) |
|---|---|
| Strong uptrend | 2019, 2020 H1, 2024 |
| Range / chop | 2021 – mid 2022, 2023 H1 |
| Downtrend | Mar – Nov 2022 |
| High volatility shock | Mar 2020, Oct 2023, Apr 2025 |

### Optimisation without curve-fitting

1. Pick **3–5 parameters at most**, e.g. `InpSLAtrMult` (1.2–2.0, step 0.1), `InpPullbackTolATR`
   (0.15–0.40), `InpMaxExtensionATR` (0.8–1.6), `InpTrailStartR` (1.0–2.5), `InpRiskReward` (2.0–3.0).
   Keep risk settings fixed.
2. Optimisation criterion: **"Custom max"**. That uses `OnTester()`, with `InpOptCriterion=Composite`
   (PF × √trades × (1 − equity DD)). Passes with fewer than `InpOptMinTrades` trades score 0.
3. Use **Forward = 1/3** (or 1/4) in the tester settings. MT5 then optimises on the first part and validates
   on the out-of-sample part automatically. Keep only parameter sets that hold up out of sample.
4. **Prefer plateaus:** choose values whose *neighbours* also perform well, not the single best pass.

### Walk-forward validation (manual)

1. Split history into rolling windows, e.g. optimise 2 years → test the next 6 months → shift 6 months → repeat.
2. Write down each out-of-sample result. The strategy is robust only if most OOS windows are acceptable
   (PF > 1.2, DD within your tolerance), with no single window dominating the total.
3. Then forward-test on **demo** in real time for at least 1–2 months before going live with small risk.

> **Honest note:** this package has been compiled in CI, but it **has not been backtested by the author**,
> because no MT5 Strategy Tester was available in the development environment. Any profitability must be
> shown by your own tests on your broker's data.

---

## 10. The dashboard

| Line | Shows |
|---|---|
| Status | **ACTIVE**, or **PAUSED - reason** (user pause, daily/weekly limit, AutoTrading off ...) |
| Symbol | Traded gold symbol and account type (hedging/netting) |
| Price | Bid / Ask |
| Trend | Overall (BULLISH / BEARISH / RANGING) with H4, H1 and M15 states |
| Timeframe | Chart TF and analysis chain H4 > H1 > M15 > M5 |
| Session | Current session, Poland time and CET/CEST |
| Balance / Equity | Account values |
| Daily P/L | Money, % and the limit |
| Drawdown | % below the equity peak |
| Weekly DD | Weekly drawdown vs limit |
| Trades today | Used / maximum |
| Open positions | Count, buys/sells, floating P/L |
| Risk/trade | Configured risk % and current total open risk |
| Spread | Current, in points, and running average |
| News filter | ACTIVE (calendar/CSV) / INACTIVE (reason) / DISABLED |
| Next news | Next relevant USD event (Poland time) |
| Last signal | Most recent valid setup |
| No-trade reason | Why the EA isn't entering right now |

The **PAUSE / RESUME** button stops new trades. Open positions are still managed (breakeven, trailing,
limits).

---

## 11. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| EA removed right after attaching: *"trades GOLD ONLY"* | The chart symbol isn't gold and no gold symbol was found. Open a gold chart, or add XAUUSD to Market Watch |
| *"Max positions must be 1..3"*, *INIT_PARAMETERS_INCORRECT* | An input is above a hard risk cap. Lower it |
| Dashboard: *AutoTrading disabled* | Turn on the **Algo Trading** toolbar button |
| *'Allow Algo Trading' disabled in EA properties* | EA properties (F7 on chart) → Common → tick Allow Algo Trading |
| *Trading not allowed for this account* | You logged in with the investor (read-only) password |
| *Loading indicator history* for a long time | Not enough H4 history. Open an H4 gold chart and scroll back, or raise *Tools → Options → Charts → Max bars* |
| *Risk too small for min lot* | Account too small for 0.01 lot at this SL. Increase risk % (≤ 2), or accept no trading. The EA won't over-risk |
| *Spread too high* / *Abnormal spread* | Normal around rollover and news. If it's constant, raise `InpMaxSpreadUsd` to suit your broker |
| *Outside enabled sessions* at a time you think is in session | Check the dashboard's PL time. If it's wrong, set `InpServerTZMode=FIXED` with the right broker offset |
| News filter *INACTIVE - calendar unavailable* | Some brokers or terminals have no calendar. Check *View → Toolbox → Calendar* shows data. Consider `InpNewsBlockIfOffline=true` |
| News filter *INACTIVE* in the tester | Expected. Supply `InpNewsCsvFile` |
| *Netting account: position already open* | Netting allows one position per symbol. The EA won't merge or reverse positions |
| *Order rejected: 10030 (unsupported filling)* | Handled automatically (FOK → IOC → RETURN). If it persists, contact the broker |
| *Order rejected: 10016 (invalid stops)* | The broker's stop level is larger than the SL. Rare on gold |
| *Error cooldown until ...* | 3 consecutive execution failures. Check the Journal for the broker reason |
| No trades for days | Normal for a selective strategy. Read *No-trade reason* on the dashboard |
| Compile error *cannot open include file* | The `Modules` folder must sit next to `XauTrendGuard.mq5` |

Logs: Toolbox → **Experts** tab (all lines start with `[XTG]`). With `InpLogToFile=true` they are also
written to `MQL5/Files/XauTrendGuard.log`.

---

## 12. Code architecture

```
XauTrendGuard.mq5        OnInit/OnTick/OnTimer/OnTester, Engine(), TryEntry(), CheckExits(), dashboard
Modules/Inputs.mqh       enums + all inputs (grouped)
Modules/Logger.mqh       levelled logger (journal + optional file)
Modules/SymbolGuard.mqh  gold verification + auto-detection of broker variants
Modules/TimeUtils.mqh    UTC/server/Poland time, EU & US DST, session/rollover filter
Modules/NewsFilter.mqh   MT5 calendar + CSV news filter with honest status
Modules/Signals.mqh      indicator handles, MTF trend, setup rules, SL/TP builder
Modules/RiskManager.mqh  sizing, daily/weekly limits, exposure & anti-averaging rules
Modules/Execution.mqh    CTrade wrapper: permissions, retries, filling fallback, cooldown
Modules/TradeManager.mqh breakeven, trailing, opposite/H1/weekend exits
Modules/Dashboard.mqh    chart panel + pause button
Modules/Stats.mqh        performance stats, CSV report, OnTester criterion
```

Engine flow on each new quote: update time → update account and limits → protect the account (limits,
weekend) → manage open positions (breakeven, trailing). On each **new M5 bar**: refresh trends. On each
**new M15 bar**: check exits. Then run the entry pipeline:

```
pause → permissions → cooldown → limits → session → news → spread → setup → duplicate check
      → exposure rules → SL/TP → lot size → execute
```
