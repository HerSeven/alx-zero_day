# XauTrendGuard: Gold (XAUUSD) Expert Advisor for MetaTrader 5

XauTrendGuard is a fully automated, **Gold-only** MT5 Expert Advisor written in native MQL5. It trades
multi-timeframe EMA trend pullbacks: H4 bias, H1 trend, M15 setup with RSI and candlestick confirmation,
and M5 entry timing. Stop loss and take profit are based on ATR, with a minimum reward:risk of 1:2. Risk
controls are strict: % equity sizing, 3 % daily and 6 % weekly loss limits, at most 3 positions and 4 trades
per day, and no martingale, grid or averaging down. It also has session and news filters and an on-chart
dashboard.

* Source: [`MQL5/Experts/XauTrendGuard/`](MQL5/Experts/XauTrendGuard/)
* Full guide covering installation, configuration, strategy, backtesting and troubleshooting:
  [`docs/XauTrendGuard_Guide.md`](docs/XauTrendGuard_Guide.md)
* Presets: [`MQL5/Presets/`](MQL5/Presets/)
* Compiled `.ex5`: the GitHub Actions workflow **Compile MQL5 EAs (XauTrendGuard, Bot15)** builds it with the official
  MetaEditor on every push. Download it from the run's `compiled-ex5` artifact.

> **Not a profit guarantee.** No backtest results are claimed. Backtest it, validate it out of sample and
> walk-forward, and run it on demo before you use real money.

## Bot15

**Bot15** is the same EA with wider account limits: up to **50 trades per day**, **9 % max daily loss** and
**15 % max weekly drawdown**. Strategy, filters, per-trade risk (1 %, max 2 %) and the 3-position cap are
unchanged. It has its own magic number, so it can run next to XauTrendGuard.

* Source: [`MQL5/Experts/Bot15/`](MQL5/Experts/Bot15/)
* Guide: [`docs/Bot15_Guide.md`](docs/Bot15_Guide.md)
* Presets: `MQL5/Presets/Bot15_Default.set`, `MQL5/Presets/Bot15_Conservative.set`
