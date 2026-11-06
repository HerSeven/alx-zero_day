//+------------------------------------------------------------------+
//|                                              RiskManager.mqh     |
//|  Position sizing, daily / weekly loss limits, exposure limits.   |
//|  - Lot size is derived ONLY from SL distance and % risk.         |
//|  - No martingale, no grid, no averaging down, no loss recovery.  |
//+------------------------------------------------------------------+
#ifndef XTG_RISKMANAGER_MQH
#define XTG_RISKMANAGER_MQH

class CXtgRisk
  {
private:
   string            m_sym;
   long              m_magic;
   bool              m_hedging;
   //--- account snapshot
   double            m_balance,m_equity;
   double            m_dayStartBal,m_weekStartBal;
   double            m_peakEquity,m_weekPeakEquity;
   datetime          m_dayStart,m_weekStart;
   int               m_tradesToday;
   double            m_closedToday;
   bool              m_dirty;
   bool              m_dailyHalt,m_weeklyHalt;
   string            m_haltReason;
   string            m_gvPeak;

   datetime          WeekStart(const datetime t)
     {
      datetime d=XtgDayStart(t);
      int dow=XtgDayOfWeek(d);           // 0 = Sunday
      int back=(dow==0 ? 6 : dow-1);     // week starts Monday 00:00 server time
      return d-back*86400;
     }

   //--- sum of every balance-affecting deal since 'from' (whole account)
   double            AccountFlowSince(const datetime from)
     {
      double sum=0;
      if(!HistorySelect(from,TimeCurrent()+86400))
         return 0;
      int n=HistoryDealsTotal();
      for(int i=0;i<n;i++)
        {
         ulong d=HistoryDealGetTicket(i);
         if(d==0) continue;
         sum+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)
              +HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
        }
      return sum;
     }

   void              RecalcHistory(void)
     {
      datetime now=TimeCurrent();
      m_dayStart=XtgDayStart(now);
      m_weekStart=WeekStart(now);
      m_dayStartBal=m_balance-AccountFlowSince(m_dayStart);
      m_weekStartBal=m_balance-AccountFlowSince(m_weekStart);

      //--- our own trades today (entries) and our closed P/L today
      m_tradesToday=0;
      m_closedToday=0;
      if(HistorySelect(m_dayStart,now+86400))
        {
         int n=HistoryDealsTotal();
         for(int i=0;i<n;i++)
           {
            ulong d=HistoryDealGetTicket(i);
            if(d==0) continue;
            if(HistoryDealGetInteger(d,DEAL_MAGIC)!=m_magic) continue;
            if(HistoryDealGetString(d,DEAL_SYMBOL)!=m_sym) continue;
            long entry=HistoryDealGetInteger(d,DEAL_ENTRY);
            if(entry==DEAL_ENTRY_IN)
               m_tradesToday++;
            m_closedToday+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)
                           +HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
           }
        }
      m_dirty=false;
     }

public:
                     CXtgRisk(void) : m_sym(""), m_magic(0), m_hedging(true), m_balance(0), m_equity(0),
                                   m_dayStartBal(0), m_weekStartBal(0), m_peakEquity(0), m_weekPeakEquity(0),
                                   m_dayStart(0), m_weekStart(0), m_tradesToday(0), m_closedToday(0),
                                   m_dirty(true), m_dailyHalt(false), m_weeklyHalt(false), m_haltReason(""), m_gvPeak("") {}

   void              Init(const string sym,const long magic)
     {
      m_sym=sym;
      m_magic=magic;
      m_hedging=(AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
      m_balance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_gvPeak="XTG_PEAK_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+IntegerToString(magic);
      m_peakEquity=m_equity;
      if(MQLInfoInteger(MQL_TESTER)==0 && GlobalVariableCheck(m_gvPeak))
         m_peakEquity=MathMax(m_equity,GlobalVariableGet(m_gvPeak));
      m_dirty=true;
      m_dayStart=0;
      m_weekStart=0;
      Update();
      m_weekPeakEquity=MathMax(m_weekStartBal,m_equity);
     }

   bool              IsHedging(void) const { return m_hedging; }
   void              MarkDirty(void)       { m_dirty=true; }

   double            RiskPercent(void) const
     {
      return MathMax(0.25,MathMin(2.0,InpRiskPercent));
     }

   //--- call on every tick
   void              Update(void)
     {
      m_balance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      datetime now=TimeCurrent();
      bool newDay=(XtgDayStart(now)!=m_dayStart);
      bool newWeek=(WeekStart(now)!=m_weekStart);
      if(newDay || newWeek || m_dirty)
         RecalcHistory();
      if(newDay)
         m_dailyHalt=false;
      if(newWeek)
        {
         m_weeklyHalt=false;
         m_weekPeakEquity=MathMax(m_weekStartBal,m_equity);
        }
      if(m_equity>m_peakEquity)
        {
         m_peakEquity=m_equity;
         if(MQLInfoInteger(MQL_TESTER)==0)
            GlobalVariableSet(m_gvPeak,m_peakEquity);
        }
      if(m_equity>m_weekPeakEquity)
         m_weekPeakEquity=m_equity;

      //--- limit checks
      if(!m_dailyHalt && DailyPLPct()<=-InpMaxDailyLossPct)
        {
         m_dailyHalt=true;
         m_haltReason="Daily loss limit "+DoubleToString(InpMaxDailyLossPct,1)+"% reached";
         g_log.Warn(m_haltReason+" - no new trades until next day");
        }
      if(!m_weeklyHalt && WeeklyDDPct()>=InpMaxWeeklyDDPct)
        {
         m_weeklyHalt=true;
         m_haltReason="Weekly drawdown limit "+DoubleToString(InpMaxWeeklyDDPct,1)+"% reached";
         g_log.Warn(m_haltReason+" - no new trades until next week");
        }
     }

   double            Balance(void) const     { return m_balance; }
   double            Equity(void) const      { return m_equity; }
   int               TradesToday(void) const { return m_tradesToday; }
   bool              DailyHalt(void) const   { return m_dailyHalt; }
   bool              WeeklyHalt(void) const  { return m_weeklyHalt; }
   string            HaltReason(void) const  { return m_haltReason; }

   //--- account-level daily P/L incl. floating, in % of start-of-day balance
   double            DailyPL(void) const     { return m_equity-m_dayStartBal; }
   double            DailyPLPct(void) const  { return (m_dayStartBal>0 ? 100.0*(m_equity-m_dayStartBal)/m_dayStartBal : 0); }
   //--- weekly drawdown = worst of (drop from week-start balance, drop from this week's equity peak)
   double            WeeklyDDPct(void) const
     {
      double a=(m_weekStartBal>0 ? 100.0*(m_weekStartBal-m_equity)/m_weekStartBal : 0);
      double b=(m_weekPeakEquity>0 ? 100.0*(m_weekPeakEquity-m_equity)/m_weekPeakEquity : 0);
      return MathMax(0.0,MathMax(a,b));
     }
   double            DrawdownPct(void) const { return (m_peakEquity>0 ? MathMax(0.0,100.0*(m_peakEquity-m_equity)/m_peakEquity) : 0); }

   //--- positions belonging to this EA on this symbol
   int               CountPositions(int &buys,int &sells,int &foreign)
     {
      buys=0; sells=0; foreign=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(t==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic) { foreign++; continue; }
         if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) buys++; else sells++;
        }
      return buys+sells;
     }

   //--- money at risk in open positions (only those whose SL is still behind entry)
   double            OpenRiskMoney(void)
     {
      double risk=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(t==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym || PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         double open=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL);
         double vol=PositionGetDouble(POSITION_VOLUME);
         bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
         if(sl<=0)
           {
            risk+=m_equity;   // unprotected position: treat as unlimited risk
            continue;
           }
         if((buy && sl>=open) || (!buy && sl<=open))
            continue;          // risk-free
         double pl=0;
         if(OrderCalcProfit(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,m_sym,vol,open,sl,pl))
            risk+=MathAbs(pl);
        }
      return risk;
     }

   //--- general permission to open a new position (limits + exposure)
   bool              CanOpen(const int dir,string &why)
     {
      if(m_weeklyHalt) { why=m_haltReason; return false; }
      if(m_dailyHalt)  { why=m_haltReason; return false; }
      if(m_tradesToday>=InpMaxTradesPerDay)
        { why="Max trades per day reached ("+IntegerToString(InpMaxTradesPerDay)+")"; return false; }
      int b,s,f;
      int total=CountPositions(b,s,f);
      if(total>=InpMaxPositions)
        { why="Max open positions reached ("+IntegerToString(InpMaxPositions)+")"; return false; }
      if(!m_hedging)
        {
         //--- netting: one position per symbol; never merge with or reverse another position
         if(total>0 || f>0)
           { why="Netting account: position already open on "+m_sym; return false; }
        }
      if((dir>0 && s>0) || (dir<0 && b>0))
        { why="Opposite position open - no hedging"; return false; }

      //--- never average down; optionally only add when existing positions are risk-free
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(t==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym || PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         double open=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL);
         double profit=PositionGetDouble(POSITION_PROFIT);
         bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
         if(profit<0)
           { why="Existing position in loss - no averaging down"; return false; }
         if(InpRequireBEBeforeAdd)
           {
            bool riskFree=(sl>0 && ((buy && sl>=open) || (!buy && sl<=open)));
            if(!riskFree)
              { why="Existing position not yet at breakeven"; return false; }
           }
        }
      return true;
     }

   //--- lot size from SL distance and % risk of equity. Returns 0 if not tradable.
   double            CalcLots(const int dir,const double entry,const double sl,string &why)
     {
      double riskPct=RiskPercent();
      double riskMoney=m_equity*riskPct/100.0;

      //--- respect the total open-risk ceiling
      double openRisk=OpenRiskMoney();
      double maxTotal=m_equity*InpMaxOpenRiskPct/100.0;
      if(openRisk+riskMoney>maxTotal)
        {
         riskMoney=maxTotal-openRisk;
         if(riskMoney<=0)
           { why="Total open risk limit reached"; return 0; }
        }

      ENUM_ORDER_TYPE type=(dir>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double pl=0;
      double lossPerLot=0;
      if(OrderCalcProfit(type,m_sym,1.0,entry,sl,pl))
         lossPerLot=MathAbs(pl);
      if(lossPerLot<=0)
        {
         double tickSize=SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_SIZE);
         double tickVal=SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
         if(tickVal<=0) tickVal=SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_VALUE);
         if(tickSize>0)
            lossPerLot=MathAbs(entry-sl)/tickSize*tickVal;
        }
      if(lossPerLot<=0)
        { why="Cannot compute loss per lot"; return 0; }

      double minLot=SymbolInfoDouble(m_sym,SYMBOL_VOLUME_MIN);
      double maxLot=SymbolInfoDouble(m_sym,SYMBOL_VOLUME_MAX);
      double step=SymbolInfoDouble(m_sym,SYMBOL_VOLUME_STEP);
      if(step<=0) step=minLot;
      if(InpMaxLotCap>0) maxLot=MathMin(maxLot,InpMaxLotCap);

      double lots=riskMoney/lossPerLot;
      lots=MathFloor(lots/step+1e-9)*step;            // always round DOWN: never exceed risk
      if(lots>maxLot) lots=MathFloor(maxLot/step+1e-9)*step;
      if(lots<minLot-1e-9)
        {
         why="Risk too small for min lot ("+DoubleToString(minLot,2)+" lot = "+
             DoubleToString(100.0*lossPerLot*minLot/m_equity,2)+"% risk)";
         return 0;
        }

      //--- margin check (keep 10% of free margin spare)
      double price=entry;
      double margin=0;
      double free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(OrderCalcMargin(type,m_sym,lots,price,margin) && margin>free*0.9)
        {
         double perLot=margin/lots;
         lots=(perLot>0 ? MathFloor((free*0.9/perLot)/step+1e-9)*step : 0);
         if(lots<minLot-1e-9)
           { why="Insufficient free margin"; return 0; }
        }
      int vd=(int)MathMax(0,MathCeil(-MathLog10(step)-1e-9));
      return NormalizeDouble(lots,vd);
     }
  };

CXtgRisk g_risk;

#endif // XTG_RISKMANAGER_MQH
//+------------------------------------------------------------------+
