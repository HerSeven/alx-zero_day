//+------------------------------------------------------------------+
//|                                              XauTrendGuard.mq5   |
//|  Risk-controlled, fully automated GOLD (XAUUSD) Expert Advisor.  |
//|                                                                  |
//|  Strategy : multi-timeframe EMA trend + pullback + RSI + candle  |
//|             confirmation (H4 bias / H1 trend / M15 setup / M5    |
//|             entry), ATR-based SL/TP with minimum 1:2 R:R.        |
//|  Risk     : % equity sizing, daily/weekly loss limits, max       |
//|             positions & trades, no martingale/grid/averaging.    |
//|                                                                  |
//|  This is NOT a profit guarantee. Backtest, forward test on demo  |
//|  and validate out-of-sample before risking real capital.         |
//+------------------------------------------------------------------+
#property copyright   "XauTrendGuard"
#property link        ""
#property version     "1.00"
#property description "Gold-only (XAUUSD) multi-timeframe trend-pullback EA with strict risk management,"
#property description "session & news filters and an on-chart dashboard. Not a profit guarantee."

#include "Modules\Inputs.mqh"
#include "Modules\Logger.mqh"
#include "Modules\SymbolGuard.mqh"
#include "Modules\TimeUtils.mqh"
#include "Modules\NewsFilter.mqh"
#include "Modules\Signals.mqh"
#include "Modules\RiskManager.mqh"
#include "Modules\Execution.mqh"
#include "Modules\TradeManager.mqh"
#include "Modules\Dashboard.mqh"
#include "Modules\Stats.mqh"

//--- hard limits from the risk policy (cannot be exceeded via inputs)
#define XTG_HARD_MAX_POSITIONS     3
#define XTG_HARD_MAX_TRADES_DAY    4
#define XTG_HARD_MAX_DAILY_LOSS    3.0
#define XTG_HARD_MAX_WEEKLY_DD     6.0

//--- runtime state
string   g_sym              = "";
bool     g_ready            = false;
bool     g_paused           = false;
string   g_lastSignal       = "none yet";
string   g_noTrade          = "Initialising";
datetime g_lastM5           = 0;
datetime g_lastM15          = 0;
datetime g_lastTradedSetup  = 0;
long     g_lastTickMsc      = 0;
double   g_avgSpread        = 0;
long     g_spreadSamples    = 0;
double   g_atr              = 0;
uint     g_lastDashMs       = 0;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool NewBar(const ENUM_TIMEFRAMES tf,datetime &last)
  {
   datetime t=iTime(g_sym,tf,0);
   if(t==0)
      return false;
   if(t!=last)
     {
      last=t;
      return true;
     }
   return false;
  }

string TfName(const ENUM_TIMEFRAMES tf)
  {
   string s=EnumToString(tf);
   StringReplace(s,"PERIOD_","");
   return s;
  }

string Money(const double v)
  {
   return DoubleToString(v,2)+" "+AccountInfoString(ACCOUNT_CURRENCY);
  }

//--- setup bar of the most recent entry of this EA (prevents re-entry after a restart)
datetime LastEntrySetupBar(void)
  {
   datetime last=0;
   if(!HistorySelect(TimeCurrent()-3*86400,TimeCurrent()+86400))
      return 0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      if(HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic) continue;
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=g_sym) continue;
      if(HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      datetime t=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
      if(t>last) last=t;
     }
   if(last==0)
      return 0;
   int sh=iBarShift(g_sym,PERIOD_M15,last,false);
   if(sh<0)
      return 0;
   return iTime(g_sym,PERIOD_M15,sh+1);
  }

void UpdateSpread(const MqlTick &tk)
  {
   double sp=tk.ask-tk.bid;
   if(sp<=0)
      return;
   if(g_spreadSamples==0)
      g_avgSpread=sp;
   else
      g_avgSpread+=0.01*(sp-g_avgSpread);
   g_spreadSamples++;
  }

bool SpreadOk(string &why)
  {
   MqlTick tk;
   if(!SymbolInfoTick(g_sym,tk))
     { why="No quote"; return false; }
   double sp=tk.ask-tk.bid;
   if(sp>InpMaxSpreadUsd)
     { why="Spread too high ("+DoubleToString(sp,2)+" > "+DoubleToString(InpMaxSpreadUsd,2)+")"; return false; }
   if(g_spreadSamples>=200 && g_avgSpread>0 && sp>InpSpreadSpikeMult*g_avgSpread)
     { why="Abnormal spread ("+DoubleToString(sp/g_avgSpread,1)+"x average)"; return false; }
   return true;
  }

//+------------------------------------------------------------------+
//| Parameter validation                                             |
//+------------------------------------------------------------------+
bool ValidateInputs(void)
  {
   bool ok=true;
   if(InpEmaFast<=0 || InpEmaMid<=InpEmaFast || InpEmaSlow<=InpEmaMid)
     { g_log.Error("EMA periods must satisfy 0 < fast < mid < slow"); ok=false; }
   if(InpRsiPeriod<2 || InpAtrPeriod<2)
     { g_log.Error("RSI / ATR period too small"); ok=false; }
   if(InpRsiBuyMin>=InpRsiBuyMax || InpRsiSellMin>=InpRsiSellMax)
     { g_log.Error("RSI ranges invalid (min must be < max)"); ok=false; }
   if(InpSLAtrMult<=0 || InpMinSLAtr<=0 || InpMaxSLAtr<=InpMinSLAtr)
     { g_log.Error("SL ATR settings invalid"); ok=false; }
   if(InpMaxPositions<1 || InpMaxPositions>XTG_HARD_MAX_POSITIONS)
     { g_log.Error("Max positions must be 1.."+IntegerToString(XTG_HARD_MAX_POSITIONS)); ok=false; }
   if(InpMaxTradesPerDay<1 || InpMaxTradesPerDay>XTG_HARD_MAX_TRADES_DAY)
     { g_log.Error("Max trades/day must be 1.."+IntegerToString(XTG_HARD_MAX_TRADES_DAY)); ok=false; }
   if(InpMaxDailyLossPct<=0 || InpMaxDailyLossPct>XTG_HARD_MAX_DAILY_LOSS)
     { g_log.Error("Max daily loss must be >0 and <= "+DoubleToString(XTG_HARD_MAX_DAILY_LOSS,1)+"%"); ok=false; }
   if(InpMaxWeeklyDDPct<=0 || InpMaxWeeklyDDPct>XTG_HARD_MAX_WEEKLY_DD)
     { g_log.Error("Max weekly DD must be >0 and <= "+DoubleToString(XTG_HARD_MAX_WEEKLY_DD,1)+"%"); ok=false; }
   if(InpMaxOpenRiskPct<=0)
     { g_log.Error("Max open risk must be > 0"); ok=false; }
   if(InpRiskPercent<0.25 || InpRiskPercent>2.0)
      g_log.Warn("Risk per trade "+DoubleToString(InpRiskPercent,2)+"% outside 0.25-2.0 -> clamped to "+
                 DoubleToString(MathMax(0.25,MathMin(2.0,InpRiskPercent)),2)+"%");
   if(InpRiskReward<2.0)
      g_log.Warn("Reward:risk "+DoubleToString(InpRiskReward,2)+" < 2.0 -> 2.0 enforced");
   return ok;
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_log.Init((int)InpLogLevel,InpLogToFile,"XauTrendGuard.log");
   g_ready=false;

   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   //--- 1) resolve and verify the Gold symbol
   string why="";
   if(InpSymbolOverride!="")
      g_sym=InpSymbolOverride;
   else if(XtgIsGoldSymbol(_Symbol,why))
      g_sym=_Symbol;
   else if(InpAutoDetectGold)
     {
      g_log.Warn("Chart symbol "+_Symbol+" is not Gold ("+why+"). Searching for a Gold symbol...");
      g_sym=XtgFindGoldSymbol();
     }
   else
      g_sym="";

   if(g_sym=="" || !XtgIsGoldSymbol(g_sym,why))
     {
      string msg="XauTrendGuard trades GOLD ONLY. No verified Gold symbol ("+
                 (g_sym=="" ? _Symbol : g_sym)+": "+why+"). EA will not trade.";
      g_log.Error(msg);
      if(MQLInfoInteger(MQL_TESTER)==0)
         Alert(msg);
      return INIT_FAILED;
     }
   SymbolSelect(g_sym,true);
   g_log.Info("Gold symbol: "+g_sym+" - "+why);
   if(g_sym!=_Symbol)
      g_log.Warn("EA attached to "+_Symbol+" but trades "+g_sym+" (driven by timer). Prefer attaching to the "+g_sym+" chart.");

   //--- 2) modules
   g_time.Init();
   g_sessions.Init();
   g_news.Init();
   if(!g_signals.Init(g_sym))
     {
      g_log.Error("Indicator initialisation failed");
      return INIT_FAILED;
     }
   g_risk.Init(g_sym,InpMagic);
   g_exec.Init(g_sym,InpMagic);
   g_tm.Init(g_sym,InpMagic);
   g_dash.Init();
   g_dash.SetButton(g_paused);

   datetime lastSetup=LastEntrySetupBar();
   if(lastSetup>g_lastTradedSetup)
      g_lastTradedSetup=lastSetup;
   g_lastTickMsc=0;

   EventSetTimer(1);

   g_log.Info(StringFormat("Started on %s | account %s | %s | risk %.2f%% | news filter: %s",
                           g_sym,
                           IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)),
                           g_risk.IsHedging() ? "HEDGING" : "NETTING",
                           g_risk.RiskPercent(),
                           g_news.Status()));
   if(InpUseNewsFilter && !g_news.IsActive())
      g_log.Warn("NEWS FILTER IS INACTIVE: "+g_news.Status()+". Entries are NOT protected against news"+
                 (InpNewsBlockIfOffline ? " (blocking all entries by setting)." : "."));
   g_ready=true;
   g_noTrade="Waiting for next M5 candle";
   UpdateDashboard(true);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_signals.Release();
   g_dash.Destroy();
   g_log.Info("Stopped (reason "+IntegerToString(reason)+")");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   Engine(false);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   if(g_ready && g_sym!=_Symbol)
      Engine(true);
   UpdateDashboard(false);
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
      g_risk.MarkDirty();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==XTG_DASH_BUTTON)
     {
      g_paused=!g_paused;
      g_dash.SetButton(g_paused);
      g_log.Info(g_paused ? "Paused by user (open positions are still managed)" : "Resumed by user");
      UpdateDashboard(true);
     }
  }

//+------------------------------------------------------------------+
double OnTester()
  {
   SXtgStats st;
   g_stats.Compute(g_sym,InpMagic,st);
   double crit=g_stats.Criterion(st);
   if(MQLInfoInteger(MQL_OPTIMIZATION)==0)
     {
      Print("===== XauTrendGuard performance (",g_sym,") =====\n",g_stats.ToText(st));
      if(InpWriteReport)
         g_stats.WriteCsv("XauTrendGuard_Report_"+g_sym+".csv",g_sym,st);
     }
   return crit;
  }

//+------------------------------------------------------------------+
//| Core engine                                                      |
//+------------------------------------------------------------------+
void Engine(const bool fromTimer)
  {
   if(!g_ready)
      return;
   MqlTick tk;
   if(!SymbolInfoTick(g_sym,tk))
      return;
   if(tk.time_msc==g_lastTickMsc)
      return;                           // already processed this quote
   g_lastTickMsc=tk.time_msc;

   g_time.Update();
   g_risk.Update();
   UpdateSpread(tk);
   ProtectAccount();

   string why;
   if(!g_signals.Ready(why))
     {
      g_noTrade=why;
      UpdateDashboard(false);
      return;
     }
   if(g_atr<=0)
      g_atr=g_signals.AtrM15();

   //--- manage open positions on every tick
   g_tm.Manage(g_atr);

   //--- signal logic only on completed candles
   if(NewBar(PERIOD_M5,g_lastM5))
     {
      g_signals.UpdateTrends();
      g_atr=g_signals.AtrM15();
      if(NewBar(PERIOD_M15,g_lastM15))
         CheckExits();
      TryEntry();
     }
   UpdateDashboard(false);
  }

//--- account-level protection (limits, weekend)
void ProtectAccount(void)
  {
   if(g_risk.WeeklyHalt() && InpCloseOnWeeklyLimit)
      g_tm.CloseAll(0,g_risk.HaltReason());
   else if(g_risk.DailyHalt() && InpCloseOnDailyLimit)
      g_tm.CloseAll(0,g_risk.HaltReason());
   if(InpCloseBeforeWeekend && g_sessions.IsWeekendCloseTime())
      g_tm.CloseAll(0,"Weekend close");
  }

//--- exits on a confirmed opposite signal / H1 flip (evaluated on new M15 bars)
void CheckExits(void)
  {
   int pd=g_tm.OpenDirection();
   if(pd==0)
      return;
   if(InpOppExitMode!=XTG_OPP_OFF)
     {
      SXtgSignal s;
      string w;
      if(g_signals.EvaluateSetup(-pd,true,s,w))
        {
         g_lastSignal=s.text+" (exit) "+TimeToString(s.setupBar+PeriodSeconds(PERIOD_M15),TIME_MINUTES);
         g_tm.CloseOnOpposite(pd,"Confirmed opposite signal: "+s.text);
        }
     }
   if(InpExitOnH1Flip)
     {
      int fm=g_signals.H1FastVsMid();
      if(fm!=0 && fm==-pd)
         g_tm.CloseAll(pd,"H1 EMA flip against position");
     }
  }

//--- full entry pipeline; sets g_noTrade with the first blocking reason
void TryEntry(void)
  {
   string why="";
   if(g_paused)                             { g_noTrade="Paused by user"; return; }
   if(!g_exec.TradingPermitted(why))        { g_noTrade=why; return; }
   if(g_exec.InCooldown(why))               { g_noTrade=why; return; }
   if(g_risk.WeeklyHalt() || g_risk.DailyHalt()) { g_noTrade=g_risk.HaltReason(); return; }
   if(!g_sessions.EntryAllowed(why))        { g_noTrade=why; return; }
   if(g_news.IsBlocked(why))                { g_noTrade=why; return; }
   if(!SpreadOk(why))                       { g_noTrade=why; return; }

   //--- strategy
   SXtgSignal sig;
   string wb="",ws="";
   bool found=g_signals.EvaluateSetup(1,false,sig,wb);
   if(!found)
      found=g_signals.EvaluateSetup(-1,false,sig,ws);
   if(!found)
     {
      int t1=g_signals.TrendH1();
      if(t1>0)      g_noTrade=wb;
      else if(t1<0) g_noTrade=ws;
      else          g_noTrade="No clear H1 trend (ranging) - standing aside";
      return;
     }
   string side=(sig.dir>0 ? "BUY" : "SELL");
   g_lastSignal=sig.text+" "+TimeToString(sig.setupBar+PeriodSeconds(PERIOD_M15),TIME_DATE|TIME_MINUTES);

   if(sig.setupBar<=g_lastTradedSetup)
     { g_noTrade="Setup already traded (one entry per M15 candle)"; return; }
   if(!g_exec.DirectionAllowedBySymbol(sig.dir))
     { g_noTrade="Broker allows only one direction on "+g_sym; return; }
   if(!g_risk.CanOpen(sig.dir,why))
     { g_noTrade=why; return; }
   if(!g_signals.BuildOrder(sig,why))
     { g_noTrade=why; return; }
   double lots=g_risk.CalcLots(sig.dir,sig.entry,sig.sl,why);
   if(lots<=0)
     { g_noTrade=why; return; }

   string cmt=InpTradeComment+" "+side+" 1:"+DoubleToString(sig.rr,1);
   g_log.Info(StringFormat("SIGNAL %s | entry %.2f SL %.2f TP %.2f | SL %.2f (%.2f ATR) | RR 1:%.2f | %.2f lots | %s",
                           side,sig.entry,sig.sl,sig.tp,sig.slDist,sig.slDist/sig.atr,sig.rr,lots,sig.text));
   ulong pos=g_exec.Open(sig.dir,lots,sig.sl,sig.tp,cmt);
   g_lastTradedSetup=sig.setupBar;      // one attempt per setup candle, success or not
   if(pos>0)
     {
      g_tm.Remember(pos,sig.slDist);
      g_risk.MarkDirty();
      g_noTrade="Trade opened: "+side+" "+DoubleToString(lots,2)+" lots";
     }
   else
      g_noTrade="Execution failed: "+g_exec.LastError();
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void UpdateDashboard(const bool force)
  {
   if(!g_dash.Enabled())
      return;
   uint now=GetTickCount();
   if(!force && now-g_lastDashMs<500)
      return;
   g_lastDashMs=now;

   MqlTick tk;
   bool haveTick=(g_sym!="" && SymbolInfoTick(g_sym,tk));
   int digits=(g_sym!="" ? (int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS) : 2);

   //--- status
   string permWhy="";
   string status="ACTIVE";
   int tone=1;
   if(!g_ready)                                 { status="PAUSED - not initialised"; tone=-1; }
   else if(g_paused)                            { status="PAUSED - by user"; tone=2; }
   else if(g_risk.WeeklyHalt() || g_risk.DailyHalt()) { status="PAUSED - "+g_risk.HaltReason(); tone=-1; }
   else if(!g_exec.TradingPermitted(permWhy))   { status="PAUSED - "+permWhy; tone=-1; }
   g_dash.Set("Status",status,tone);

   string symTxt=g_sym+(g_sym!=_Symbol ? " (chart "+_Symbol+")" : "")+" | "+(g_risk.IsHedging() ? "Hedging" : "Netting");
   g_dash.Set("Symbol",symTxt);
   if(haveTick)
      g_dash.Set("Price","Bid "+DoubleToString(tk.bid,digits)+"  Ask "+DoubleToString(tk.ask,digits));

   int t4=g_signals.TrendH4(),t1=g_signals.TrendH1();
   g_dash.Set("Trend",g_signals.TrendText(),(t4>0 && t1>0) ? 1 : ((t4<0 && t1<0) ? -1 : 2));
   g_dash.Set("Timeframe","Chart "+TfName((ENUM_TIMEFRAMES)Period())+" | H4>H1>M15>M5");

   datetime pl=g_time.PolandNow();
   g_dash.Set("Session",g_sessions.CurrentName()+" | PL "+XtgHHMM(pl)+(g_time.PolandIsSummer() ? " CEST" : " CET"));

   g_dash.Set("Balance",Money(g_risk.Balance()));
   g_dash.Set("Equity",Money(g_risk.Equity()));
   double dpl=g_risk.DailyPL();
   g_dash.Set("Daily P/L",Money(dpl)+" ("+DoubleToString(g_risk.DailyPLPct(),2)+"% / limit -"+
              DoubleToString(InpMaxDailyLossPct,1)+"%)",dpl>=0 ? 1 : -1);
   double dd=g_risk.DrawdownPct();
   g_dash.Set("Drawdown",DoubleToString(dd,2)+"% from equity peak",dd<2 ? 0 : (dd<4 ? 2 : -1));
   double wdd=g_risk.WeeklyDDPct();
   g_dash.Set("Weekly DD",DoubleToString(wdd,2)+"% / limit "+DoubleToString(InpMaxWeeklyDDPct,1)+"%",
              wdd<InpMaxWeeklyDDPct*0.5 ? 0 : 2);

   g_dash.Set("Trades today",IntegerToString(g_risk.TradesToday())+" / "+IntegerToString(InpMaxTradesPerDay));
   int b,s,f;
   int n=g_risk.CountPositions(b,s,f);
   g_dash.Set("Open positions",IntegerToString(n)+" / "+IntegerToString(InpMaxPositions)+
              "  (B "+IntegerToString(b)+" S "+IntegerToString(s)+")  P/L "+DoubleToString(g_tm.FloatingPL(),2));
   double eq=g_risk.Equity();
   double openRisk=(eq>0 ? 100.0*g_risk.OpenRiskMoney()/eq : 0);
   g_dash.Set("Risk/trade",DoubleToString(g_risk.RiskPercent(),2)+"%  | open risk "+DoubleToString(openRisk,2)+"%");

   if(haveTick)
     {
      double sp=tk.ask-tk.bid;
      double pt=SymbolInfoDouble(g_sym,SYMBOL_POINT);
      g_dash.Set("Spread",DoubleToString(sp,digits)+" ("+DoubleToString(pt>0 ? sp/pt : 0,0)+" pts) avg "+
                 DoubleToString(g_avgSpread,digits),sp<=InpMaxSpreadUsd ? 0 : -1);
     }
   g_dash.Set("News filter",g_news.Status(),g_news.IsActive() ? 1 : 2);
   g_dash.Set("Next news",g_news.NextEvent());
   g_dash.Set("Last signal",g_lastSignal);
   g_dash.Set("No-trade reason",g_noTrade,2);
   g_dash.Redraw();
  }
//+------------------------------------------------------------------+
