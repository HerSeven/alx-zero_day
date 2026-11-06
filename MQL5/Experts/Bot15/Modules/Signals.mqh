//+------------------------------------------------------------------+
//|                                                  Signals.mqh     |
//|  Multi-timeframe trend-pullback signal engine.                   |
//|   H4  : overall direction (EMA mid/slow)                         |
//|   H1  : trend confirmation (EMA fast/mid/slow or clear slope)    |
//|   M15 : setup - EMA stack, pullback to EMA20/50, RSI, candle     |
//|   M5  : entry timing - confirmation candle above/below EMA20     |
//|  All values are read from CLOSED bars (shift >= 1): no repaint,  |
//|  no look-ahead.                                                  |
//+------------------------------------------------------------------+
#ifndef XTG_SIGNALS_MQH
#define XTG_SIGNALS_MQH

struct SXtgSignal
  {
   int               dir;        // +1 buy, -1 sell
   datetime          setupBar;   // open time of the M15 setup bar
   double            entry;
   double            sl;
   double            tp;
   double            atr;
   double            slDist;
   double            rr;
   string            text;
  };

void XtgResetSignal(SXtgSignal &s)
  {
   s.dir=0; s.setupBar=0; s.entry=0; s.sl=0; s.tp=0; s.atr=0; s.slDist=0; s.rr=0; s.text="";
  }

class CXtgSignals
  {
private:
   string            m_sym;
   int               m_h4f,m_h4m,m_h4s;
   int               m_h1f,m_h1m,m_h1s;
   int               m_m15f,m_m15m,m_m15s,m_rsi,m_atr;
   int               m_m5f;
   int               m_trendH4,m_trendH1,m_trendM15;
   double            m_tick;
   int               m_digits;

   bool              Copy(const int h,const int shift,const int count,double &arr[])
     {
      ArraySetAsSeries(arr,true);
      return (CopyBuffer(h,0,shift,count,arr)==count);
     }

   int               CreateMA(const ENUM_TIMEFRAMES tf,const int period)
     {
      int h=iMA(m_sym,tf,period,0,MODE_EMA,PRICE_CLOSE);
      if(h==INVALID_HANDLE)
         g_log.Error("iMA("+EnumToString(tf)+","+IntegerToString(period)+") failed, err "+IntegerToString(GetLastError()));
      return h;
     }

   //--- trend of a higher timeframe from closed bar #1
   int               TrendOf(const ENUM_TIMEFRAMES tf,const int hf,const int hm,const int hs,
                             const bool needFastMid,const bool allowSlopeAlt,const bool needCloseVsMid)
     {
      int n=InpSlopeBars+1;
      double f[],m[],s[];
      if(!Copy(hf,1,n,f) || !Copy(hm,1,n,m) || !Copy(hs,1,n,s))
         return 0;
      double c=iClose(m_sym,tf,1);
      if(c<=0)
         return 0;
      int sb=InpSlopeBars;
      //--- bullish
      bool upStack = (m[0]>s[0] && c>s[0]);
      bool upSlope = allowSlopeAlt && (m[0]>m[sb] && f[0]>f[sb] && c>m[0]);
      bool up = (upStack || upSlope)
                && (!needFastMid || f[0]>m[0])
                && (!needCloseVsMid || c>m[0]);
      //--- bearish
      bool dnStack = (m[0]<s[0] && c<s[0]);
      bool dnSlope = allowSlopeAlt && (m[0]<m[sb] && f[0]<f[sb] && c<m[0]);
      bool dn = (dnStack || dnSlope)
                && (!needFastMid || f[0]<m[0])
                && (!needCloseVsMid || c<m[0]);
      if(up && !dn) return 1;
      if(dn && !up) return -1;
      return 0;
     }

   bool              BullCandle(const MqlRates &c,const MqlRates &p,string &name)
     {
      double range=c.high-c.low;
      if(range<=0 || c.close<=c.open)
         return false;
      double body=c.close-c.open;
      double lowerWick=c.open-c.low;
      if(p.close<p.open && c.close>=p.open && c.open<=p.close)
        { name="Bullish engulfing"; return true; }
      if(lowerWick>=2.0*body && lowerWick>=0.5*range && (c.close-c.low)>=0.6*range)
        { name="Bullish pin bar"; return true; }
      if(body>=0.5*range && (c.high-c.close)<=0.3*range)
        { name="Strong bullish close"; return true; }
      return false;
     }

   bool              BearCandle(const MqlRates &c,const MqlRates &p,string &name)
     {
      double range=c.high-c.low;
      if(range<=0 || c.close>=c.open)
         return false;
      double body=c.open-c.close;
      double upperWick=c.high-c.open;
      if(p.close>p.open && c.close<=p.open && c.open>=p.close)
        { name="Bearish engulfing"; return true; }
      if(upperWick>=2.0*body && upperWick>=0.5*range && (c.high-c.close)>=0.6*range)
        { name="Bearish pin bar"; return true; }
      if(body>=0.5*range && (c.close-c.low)<=0.3*range)
        { name="Strong bearish close"; return true; }
      return false;
     }

   double            RoundToTick(const double price,const int mode) // mode: -1 down, 0 nearest, +1 up
     {
      double t=(m_tick>0 ? m_tick : SymbolInfoDouble(m_sym,SYMBOL_POINT));
      double v=price/t;
      if(mode<0)      v=MathFloor(v+1e-9);
      else if(mode>0) v=MathCeil(v-1e-9);
      else            v=MathRound(v);
      return NormalizeDouble(v*t,m_digits);
     }

   void              Handles(int &hs[])
     {
      ArrayResize(hs,12);
      hs[0]=m_h4f;  hs[1]=m_h4m;  hs[2]=m_h4s;
      hs[3]=m_h1f;  hs[4]=m_h1m;  hs[5]=m_h1s;
      hs[6]=m_m15f; hs[7]=m_m15m; hs[8]=m_m15s;
      hs[9]=m_m5f;  hs[10]=m_rsi; hs[11]=m_atr;
     }

public:
                     CXtgSignals(void) : m_sym(""), m_h4f(INVALID_HANDLE), m_h4m(INVALID_HANDLE), m_h4s(INVALID_HANDLE),
                                      m_h1f(INVALID_HANDLE), m_h1m(INVALID_HANDLE), m_h1s(INVALID_HANDLE),
                                      m_m15f(INVALID_HANDLE), m_m15m(INVALID_HANDLE), m_m15s(INVALID_HANDLE),
                                      m_rsi(INVALID_HANDLE), m_atr(INVALID_HANDLE), m_m5f(INVALID_HANDLE),
                                      m_trendH4(0), m_trendH1(0), m_trendM15(0), m_tick(0), m_digits(2) {}

   bool              Init(const string sym)
     {
      m_sym=sym;
      m_tick=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
      m_digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
      m_h4f=CreateMA(PERIOD_H4,InpEmaFast);
      m_h4m=CreateMA(PERIOD_H4,InpEmaMid);
      m_h4s=CreateMA(PERIOD_H4,InpEmaSlow);
      m_h1f=CreateMA(PERIOD_H1,InpEmaFast);
      m_h1m=CreateMA(PERIOD_H1,InpEmaMid);
      m_h1s=CreateMA(PERIOD_H1,InpEmaSlow);
      m_m15f=CreateMA(PERIOD_M15,InpEmaFast);
      m_m15m=CreateMA(PERIOD_M15,InpEmaMid);
      m_m15s=CreateMA(PERIOD_M15,InpEmaSlow);
      m_m5f=CreateMA(PERIOD_M5,InpEmaFast);
      m_rsi=iRSI(sym,PERIOD_M15,InpRsiPeriod,PRICE_CLOSE);
      m_atr=iATR(sym,PERIOD_M15,InpAtrPeriod);
      if(m_rsi==INVALID_HANDLE || m_atr==INVALID_HANDLE)
         g_log.Error("iRSI/iATR creation failed, err "+IntegerToString(GetLastError()));
      return (m_h4f!=INVALID_HANDLE && m_h4m!=INVALID_HANDLE && m_h4s!=INVALID_HANDLE &&
              m_h1f!=INVALID_HANDLE && m_h1m!=INVALID_HANDLE && m_h1s!=INVALID_HANDLE &&
              m_m15f!=INVALID_HANDLE && m_m15m!=INVALID_HANDLE && m_m15s!=INVALID_HANDLE &&
              m_m5f!=INVALID_HANDLE && m_rsi!=INVALID_HANDLE && m_atr!=INVALID_HANDLE);
     }

   void              Release(void)
     {
      int hs[];
      Handles(hs);
      for(int i=0;i<ArraySize(hs);i++)
         if(hs[i]!=INVALID_HANDLE)
            IndicatorRelease(hs[i]);
      m_h4f=INVALID_HANDLE;  m_h4m=INVALID_HANDLE;  m_h4s=INVALID_HANDLE;
      m_h1f=INVALID_HANDLE;  m_h1m=INVALID_HANDLE;  m_h1s=INVALID_HANDLE;
      m_m15f=INVALID_HANDLE; m_m15m=INVALID_HANDLE; m_m15s=INVALID_HANDLE;
      m_m5f=INVALID_HANDLE;  m_rsi=INVALID_HANDLE;  m_atr=INVALID_HANDLE;
     }

   //--- indicator buffers calculated far enough back?
   bool              Ready(string &why)
     {
      int need=InpEmaSlow+InpSlopeBars+5;
      int hs[];
      Handles(hs);
      for(int i=0;i<ArraySize(hs);i++)
        {
         int bc=BarsCalculated(hs[i]);
         //--- slow-EMA handles (0..8) need EMA200 history; M5 EMA / RSI / ATR (9..11) need ~110 bars
         int req=(i<9 ? need : 110);
         if(bc<req)
           {
            why="Loading indicator history ("+IntegerToString(bc)+"/"+IntegerToString(req)+")";
            return false;
           }
        }
      return true;
     }

   //--- refresh cached trend states (call on each new M5 bar)
   void              UpdateTrends(void)
     {
      m_trendH4 =TrendOf(PERIOD_H4,m_h4f,m_h4m,m_h4s,InpStrictH4Stack,false,false);
      m_trendH1 =TrendOf(PERIOD_H1,m_h1f,m_h1m,m_h1s,true,true,true);
      m_trendM15=TrendOf(PERIOD_M15,m_m15f,m_m15m,m_m15s,true,true,false);
     }

   int               TrendH4(void)  const { return m_trendH4;  }
   int               TrendH1(void)  const { return m_trendH1;  }
   int               TrendM15(void) const { return m_trendM15; }

   string            TrendText(void)
     {
      string a=(m_trendH4>0 ? "UP" : (m_trendH4<0 ? "DOWN" : "FLAT"));
      string b=(m_trendH1>0 ? "UP" : (m_trendH1<0 ? "DOWN" : "FLAT"));
      string c=(m_trendM15>0 ? "UP" : (m_trendM15<0 ? "DOWN" : "FLAT"));
      string overall="RANGING / MIXED";
      if(m_trendH4>0 && m_trendH1>0) overall="BULLISH";
      if(m_trendH4<0 && m_trendH1<0) overall="BEARISH";
      return overall+"  (H4 "+a+" | H1 "+b+" | M15 "+c+")";
     }

   //--- H1 fast EMA vs mid EMA on the last closed bar: +1 above, -1 below
   int               H1FastVsMid(void)
     {
      double f[],m[];
      if(!Copy(m_h1f,1,1,f) || !Copy(m_h1m,1,1,m))
         return 0;
      return (f[0]>m[0] ? 1 : (f[0]<m[0] ? -1 : 0));
     }

   double            AtrM15(void)
     {
      double a[];
      if(!Copy(m_atr,1,1,a))
         return 0;
      return a[0];
     }

   //--- Evaluate a full setup in direction dir. forExit=true skips the M5 trigger
   //    (used to detect a confirmed opposite signal for exits).
   bool              EvaluateSetup(const int dir,const bool forExit,SXtgSignal &sig,string &why)
     {
      XtgResetSignal(sig);
      string side=(dir>0 ? "BUY" : "SELL");
      if(InpRequireH4Bias && m_trendH4!=dir)
        { why=side+": H4 bias not aligned"; return false; }
      if(m_trendH1!=dir)
        { why=side+": H1 trend not confirmed"; return false; }

      int pb=MathMax(1,InpPullbackBars);
      int n=MathMax(pb,InpSlopeBars)+2;
      double f[],m[],s[],rsi[],atr[];
      MqlRates r[];
      ArraySetAsSeries(r,true);
      if(!Copy(m_m15f,1,n,f) || !Copy(m_m15m,1,n,m) || !Copy(m_m15s,1,n,s) ||
         !Copy(m_rsi,1,2,rsi) || !Copy(m_atr,1,100,atr) || CopyRates(m_sym,PERIOD_M15,1,n,r)!=n)
        { why="M15 data not ready"; return false; }

      double a=atr[0];
      if(a<=0)
        { why="ATR not available"; return false; }
      //--- volatility regime
      double avg=0;
      for(int i=0;i<100;i++) avg+=atr[i];
      avg/=100.0;
      if(avg>0 && a>InpMaxAtrVsAverage*avg)
        { why=side+": volatility too high (ATR "+DoubleToString(a/avg,1)+"x avg)"; return false; }
      if(avg>0 && a<InpMinAtrVsAverage*avg)
        { why=side+": volatility too low (ATR "+DoubleToString(a/avg,1)+"x avg)"; return false; }

      int sb=InpSlopeBars;
      double tol=InpPullbackTolATR*a;
      //--- 1) EMA stack on M15 (EMA50 vs EMA200, or clearly defined trend via HTF + slope)
      if(dir>0)
        {
         if(!(f[0]>m[0]))
           { why="BUY: M15 EMA20 not above EMA50"; return false; }
         bool clear=(m_trendH4>0 && m[0]>m[sb] && f[0]>f[sb]);
         if(!(m[0]>s[0]) && !clear)
           { why="BUY: M15 EMA50 below EMA200 and no clear trend"; return false; }
        }
      else
        {
         if(!(f[0]<m[0]))
           { why="SELL: M15 EMA20 not below EMA50"; return false; }
         bool clear=(m_trendH4<0 && m[0]<m[sb] && f[0]<f[sb]);
         if(!(m[0]<s[0]) && !clear)
           { why="SELL: M15 EMA50 above EMA200 and no clear trend"; return false; }
        }

      //--- 2) pullback to EMA20 / EMA50 zone without breaking structure (close beyond EMA50)
      bool touched=false;
      for(int k=0;k<pb;k++)
        {
         if(dir>0)
           {
            if(r[k].low<=f[k]+tol) touched=true;
            if(r[k].close<m[k]-tol)
              { why="BUY: pullback closed below EMA50 (structure broken)"; return false; }
           }
         else
           {
            if(r[k].high>=f[k]-tol) touched=true;
            if(r[k].close>m[k]+tol)
              { why="SELL: pullback closed above EMA50 (structure broken)"; return false; }
           }
        }
      if(!touched)
        { why=side+": no pullback to EMA20/50 yet"; return false; }

      //--- 3) not over-extended from EMA20, and candle closed back on the trend side of EMA20
      double ext=(dir>0 ? r[0].close-f[0] : f[0]-r[0].close);
      if(ext<0)
        { why=side+": signal candle closed on wrong side of EMA20"; return false; }
      if(ext>InpMaxExtensionATR*a)
        { why=side+": price over-extended from EMA20"; return false; }

      //--- 4) candlestick confirmation on the last closed M15 bar
      string pattern="";
      bool candleOk=(dir>0 ? BullCandle(r[0],r[1],pattern) : BearCandle(r[0],r[1],pattern));
      if(!candleOk)
        { why=side+": no confirmation candle"; return false; }

      //--- 5) RSI momentum
      if(dir>0)
        {
         if(rsi[0]<InpRsiBuyMin || rsi[0]>InpRsiBuyMax || rsi[0]<=rsi[1])
           { why="BUY: RSI "+DoubleToString(rsi[0],1)+" not confirming"; return false; }
        }
      else
        {
         if(rsi[0]<InpRsiSellMin || rsi[0]>InpRsiSellMax || rsi[0]>=rsi[1])
           { why="SELL: RSI "+DoubleToString(rsi[0],1)+" not confirming"; return false; }
        }

      //--- 6) M5 entry timing
      if(!forExit && InpUseM5Trigger)
        {
         MqlRates r5[];
         ArraySetAsSeries(r5,true);
         double e5[];
         if(CopyRates(m_sym,PERIOD_M5,1,1,r5)!=1 || !Copy(m_m5f,1,1,e5))
           { why="M5 data not ready"; return false; }
         bool ok5=(dir>0 ? (r5[0].close>r5[0].open && r5[0].close>e5[0])
                         : (r5[0].close<r5[0].open && r5[0].close<e5[0]));
         if(!ok5)
           { why=side+": waiting for M5 confirmation"; return false; }
        }

      sig.dir=dir;
      sig.setupBar=r[0].time;
      sig.atr=a;
      sig.text=side+" | "+pattern+" | RSI "+DoubleToString(rsi[0],1);
      why="";
      return true;
     }

   //--- Turn a valid setup into concrete entry / SL / TP prices using the live quote
   bool              BuildOrder(SXtgSignal &sig,string &why)
     {
      MqlTick t;
      if(!SymbolInfoTick(m_sym,t))
        { why="No tick data"; return false; }
      int dir=sig.dir;
      double a=sig.atr;
      double entry=(dir>0 ? t.ask : t.bid);
      double sl=entry-dir*InpSLAtrMult*a;

      if(InpSLMode==XTG_SL_STRUCTURE_ATR)
        {
         int cnt=MathMax(2,InpSwingLookback);
         double swingSL;
         if(dir>0)
           {
            int idx=iLowest(m_sym,PERIOD_M15,MODE_LOW,cnt,1);
            if(idx<0) { why="Swing data not ready"; return false; }
            swingSL=iLow(m_sym,PERIOD_M15,idx)-InpSLBufferATR*a;
            sl=MathMin(sl,swingSL);
           }
         else
           {
            int idx=iHighest(m_sym,PERIOD_M15,MODE_HIGH,cnt,1);
            if(idx<0) { why="Swing data not ready"; return false; }
            swingSL=iHigh(m_sym,PERIOD_M15,idx)+InpSLBufferATR*a;
            sl=MathMax(sl,swingSL);
           }
        }

      double dist=MathAbs(entry-sl);
      if(dist<InpMinSLAtr*a)
        {
         dist=InpMinSLAtr*a;
         sl=entry-dir*dist;
        }
      if(dist>InpMaxSLAtr*a)
        { why="SL too wide ("+DoubleToString(dist/a,2)+" ATR > "+DoubleToString(InpMaxSLAtr,1)+")"; return false; }

      //--- broker minimum stop distance
      double point=SymbolInfoDouble(m_sym,SYMBOL_POINT);
      double stopLvl=(double)SymbolInfoInteger(m_sym,SYMBOL_TRADE_STOPS_LEVEL)*point;
      double spread=t.ask-t.bid;
      if(dist<=stopLvl+spread)
        { why="SL closer than broker stop level"; return false; }

      double rr=MathMax(InpRiskReward,2.0);
      double tp=entry+dir*rr*dist;

      //--- optional: make sure an obvious H1 swing does not block the 1:2 target
      if(InpCheckRoomToTarget)
        {
         int cnt=MathMax(5,InpRoomLookbackH1);
         if(dir>0)
           {
            int idx=iHighest(m_sym,PERIOD_H1,MODE_HIGH,cnt,1);
            double res=(idx>=0 ? iHigh(m_sym,PERIOD_H1,idx) : 0);
            if(res>entry && res-entry<rr*dist)
              { why="BUY: H1 resistance blocks 1:"+DoubleToString(rr,1)+" target"; return false; }
           }
         else
           {
            int idx=iLowest(m_sym,PERIOD_H1,MODE_LOW,cnt,1);
            double sup=(idx>=0 ? iLow(m_sym,PERIOD_H1,idx) : 0);
            if(sup>0 && sup<entry && entry-sup<rr*dist)
              { why="SELL: H1 support blocks 1:"+DoubleToString(rr,1)+" target"; return false; }
           }
        }

      //--- normalise: SL rounded away from entry first, then TP rebuilt from the final
      //    SL distance and rounded away from entry -> RR is never below the target
      sl=RoundToTick(sl,dir>0 ? -1 : 1);
      dist=MathAbs(entry-sl);
      tp=RoundToTick(entry+dir*rr*dist,dir>0 ? 1 : -1);
      double realRR=(dist>0 ? MathAbs(tp-entry)/dist : 0);
      if(realRR<2.0-1e-6)
        { why="Risk:reward below 1:2"; return false; }

      sig.entry=entry;
      sig.sl=sl;
      sig.tp=tp;
      sig.slDist=dist;
      sig.rr=realRR;
      return true;
     }
  };

CXtgSignals g_signals;

#endif // XTG_SIGNALS_MQH
//+------------------------------------------------------------------+
