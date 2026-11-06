//+------------------------------------------------------------------+
//|                                                   Inputs.mqh     |
//|  XauTrendGuard - enumerations and user-configurable parameters   |
//+------------------------------------------------------------------+
#ifndef XTG_INPUTS_MQH
#define XTG_INPUTS_MQH

//--- How the broker (trade server) time zone is determined
enum ENUM_XTG_SERVER_TZ
  {
   XTG_TZ_AUTO     = 0, // Auto (live: detected; tester: GMT+2/+3 US-DST rule)
   XTG_TZ_NY_CLOSE = 1, // GMT+2 winter / GMT+3 summer (US DST) - most brokers
   XTG_TZ_FIXED    = 2  // Fixed offset (see "Fixed server GMT offset")
  };

//--- Stop-loss placement method
enum ENUM_XTG_SL_MODE
  {
   XTG_SL_ATR           = 0, // ATR multiple only
   XTG_SL_STRUCTURE_ATR = 1  // Beyond swing high/low, at least ATR multiple
  };

//--- What to do with an open position when a confirmed opposite setup appears
enum ENUM_XTG_OPP_EXIT
  {
   XTG_OPP_OFF        = 0, // Never close on opposite signal
   XTG_OPP_ANY        = 1, // Always close
   XTG_OPP_IF_PROFIT  = 2, // Close only if position is in profit
   XTG_OPP_IF_LOSS    = 3  // Close only if position is in loss
  };

//--- Custom optimisation criterion returned by OnTester()
enum ENUM_XTG_OPT_CRITERION
  {
   XTG_CRIT_COMPOSITE     = 0, // PF x sqrt(trades) x (1 - DD%)
   XTG_CRIT_NET_PROFIT    = 1, // Net profit
   XTG_CRIT_PROFIT_FACTOR = 2, // Profit factor
   XTG_CRIT_RECOVERY      = 3, // Net profit / max equity drawdown
   XTG_CRIT_EXPECTANCY_R  = 4  // Average R-multiple per trade
  };

//--- Logging verbosity
enum ENUM_XTG_LOG_LEVEL
  {
   XTG_LOG_ERROR = 0, // Errors only
   XTG_LOG_WARN  = 1, // Errors + warnings
   XTG_LOG_INFO  = 2, // Normal (recommended)
   XTG_LOG_DEBUG = 3  // Debug (verbose)
  };

//==================================================================
input group "=== General ==="
input long     InpMagic               = 26110601;  // Magic number (unique per EA instance)
input string   InpTradeComment        = "XTG";     // Order comment prefix
input bool     InpAutoDetectGold      = true;      // If chart is not Gold, find a Gold symbol automatically
input string   InpSymbolOverride      = "";        // Force Gold symbol name (blank = automatic)

input group "=== Trend & entry strategy ==="
input int      InpEmaFast             = 20;        // EMA fast period
input int      InpEmaMid              = 50;        // EMA medium period
input int      InpEmaSlow             = 200;       // EMA slow period
input int      InpRsiPeriod           = 14;        // RSI period (M15)
input double   InpRsiBuyMin           = 50.0;      // BUY: RSI minimum
input double   InpRsiBuyMax           = 70.0;      // BUY: RSI maximum (avoid overbought)
input double   InpRsiSellMin          = 30.0;      // SELL: RSI minimum (avoid oversold)
input double   InpRsiSellMax          = 50.0;      // SELL: RSI maximum
input int      InpAtrPeriod           = 14;        // ATR period (M15)
input bool     InpRequireH4Bias       = true;      // Require H4 trend agreement
input bool     InpStrictH4Stack       = false;     // H4: also require EMA fast > mid (strict stack)
input int      InpSlopeBars           = 5;         // Bars used to measure EMA slope ("clear trend")
input int      InpPullbackBars        = 4;         // M15 bars to look back for the pullback
input double   InpPullbackTolATR      = 0.25;      // Pullback tolerance around EMA fast (x ATR)
input double   InpMaxExtensionATR     = 1.2;       // Max distance close-to-EMA fast at entry (x ATR)
input bool     InpUseM5Trigger        = true;      // Require M5 confirmation candle
input double   InpMaxAtrVsAverage     = 2.5;       // Skip if ATR > X * its 100-bar average (extreme volatility)
input double   InpMinAtrVsAverage     = 0.5;       // Skip if ATR < X * its 100-bar average (dead market)

input group "=== Stop loss / take profit ==="
input ENUM_XTG_SL_MODE InpSLMode      = XTG_SL_STRUCTURE_ATR; // Stop-loss mode
input double   InpSLAtrMult           = 1.5;       // SL distance (x ATR)
input double   InpSLBufferATR         = 0.2;       // Buffer beyond swing high/low (x ATR)
input int      InpSwingLookback       = 10;        // Swing lookback (M15 bars)
input double   InpMinSLAtr            = 0.8;       // Minimum SL distance (x ATR)
input double   InpMaxSLAtr            = 3.0;       // Maximum SL distance (x ATR) - skip if wider
input double   InpRiskReward          = 2.0;       // Reward:Risk ratio (minimum enforced 2.0)
input bool     InpCheckRoomToTarget   = false;     // Skip if H1 swing high/low blocks the 1:2 target
input int      InpRoomLookbackH1      = 48;        // Bars for room-to-target check (H1)

input group "=== Risk management ==="
input double   InpRiskPercent         = 1.0;       // Risk per trade, % of equity (clamped 0.25-2.0)
input int      InpMaxPositions        = 3;         // Max simultaneous positions
input int      InpMaxTradesPerDay     = 4;         // Max new trades per day
input double   InpMaxDailyLossPct     = 3.0;       // Max daily loss % (stop trading for the day)
input double   InpMaxWeeklyDDPct      = 6.0;       // Max weekly drawdown % (stop trading for the week)
input double   InpMaxOpenRiskPct      = 3.0;       // Max total open risk across positions %
input bool     InpCloseOnDailyLimit   = true;      // Close open positions when daily limit is hit
input bool     InpCloseOnWeeklyLimit  = true;      // Close open positions when weekly limit is hit
input double   InpMaxLotCap           = 0.0;       // Absolute lot cap (0 = broker maximum)
input bool     InpRequireBEBeforeAdd  = true;      // Add 2nd/3rd position only if others are at breakeven

input group "=== Trade management ==="
input bool     InpUseBreakeven        = true;      // Move SL to breakeven
input double   InpBETriggerR          = 1.0;       // Breakeven trigger (profit in R)
input double   InpBELockR             = 0.05;      // Profit locked at breakeven (R) to cover costs
input bool     InpUseTrailing         = true;      // Use ATR trailing stop
input double   InpTrailStartR         = 1.5;       // Trailing starts at (profit in R)
input double   InpTrailAtrMult        = 2.0;       // Trailing distance (x ATR M15)
input ENUM_XTG_OPP_EXIT InpOppExitMode = XTG_OPP_ANY; // Exit on confirmed opposite signal
input bool     InpExitOnH1Flip        = false;     // Also exit when H1 EMA fast crosses EMA mid against position
input bool     InpCloseBeforeWeekend  = false;     // Close all positions on Friday evening
input string   InpWeekendCloseTime    = "21:30";   // Friday close time (Poland time)

input group "=== Execution & spread ==="
input double   InpMaxSpreadUsd        = 0.60;      // Max spread in price units (USD per oz)
input double   InpSpreadSpikeMult     = 2.5;       // Block if spread > X * average spread
input int      InpSlippagePoints      = 30;        // Max slippage / deviation (points)
input int      InpMaxRetries          = 3;         // Order send retries (requotes, price changes)
input int      InpMaxConsecErrors     = 3;         // Consecutive failures before cooldown
input int      InpErrorCooldownMin    = 15;        // Cooldown after repeated failures (minutes)

input group "=== Trading sessions (Poland local time, DST automatic) ==="
input ENUM_XTG_SERVER_TZ InpServerTZMode = XTG_TZ_AUTO; // Broker server time zone mode
input int      InpServerGMTOffset     = 2;         // Fixed server GMT offset (hours, FIXED mode only)
input bool     InpUseLondon           = true;      // Trade London session
input string   InpLondonStart         = "09:00";   // London start (PL time)
input string   InpLondonEnd           = "17:30";   // London end (PL time)
input bool     InpUseNewYork          = true;      // Trade New York session
input string   InpNewYorkStart        = "14:30";   // New York start (PL time)
input string   InpNewYorkEnd          = "21:30";   // New York end (PL time)
input bool     InpUseOverlap          = true;      // Trade London/NY overlap
input string   InpOverlapStart        = "14:30";   // Overlap start (PL time)
input string   InpOverlapEnd          = "17:30";   // Overlap end (PL time)
input int      InpRolloverBeforeMin   = 20;        // No entries X min before server midnight (rollover)
input int      InpRolloverAfterMin    = 40;        // No entries X min after server midnight
input string   InpFridayCutoff        = "20:00";   // No new entries on Friday after (PL time)

input group "=== Economic news filter ==="
input bool     InpUseNewsFilter       = true;      // Use news filter
input int      InpNewsBeforeMin       = 30;        // Block minutes BEFORE high-impact USD news
input int      InpNewsAfterMin        = 30;        // Block minutes AFTER high-impact USD news
input bool     InpNewsOnlyKeyEvents   = false;     // Only CPI/NFP/FOMC/Fed rate/PCE (false = all high-impact USD)
input bool     InpNewsBlockIfOffline  = false;     // Block all entries if no news data is available
input string   InpNewsCsvFile         = "";        // Optional CSV in Common\Files (for backtests)

input group "=== Dashboard ==="
input bool     InpShowDashboard       = true;      // Show on-chart dashboard
input int      InpDashX               = 10;        // Dashboard X offset (px)
input int      InpDashY               = 25;        // Dashboard Y offset (px)
input int      InpDashFontSize        = 9;         // Dashboard font size

input group "=== Testing, optimisation & logging ==="
input ENUM_XTG_OPT_CRITERION InpOptCriterion = XTG_CRIT_COMPOSITE; // Optimisation criterion (OnTester)
input int      InpOptMinTrades        = 30;        // Min trades for a valid optimisation pass
input bool     InpWriteReport         = true;      // Write CSV performance report at the end of a test
input ENUM_XTG_LOG_LEVEL InpLogLevel  = XTG_LOG_INFO; // Log level
input bool     InpLogToFile           = false;     // Also write log to MQL5\Files\XauTrendGuard.log

#endif // XTG_INPUTS_MQH
//+------------------------------------------------------------------+
