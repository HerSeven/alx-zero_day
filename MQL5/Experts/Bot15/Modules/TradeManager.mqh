//+------------------------------------------------------------------+
//|                                             TradeManager.mqh     |
//|  Breakeven at 1R, ATR trailing stop, opposite-signal exits,      |
//|  emergency / weekend closes. Stops are only ever tightened.      |
//+------------------------------------------------------------------+
#ifndef XTG_TRADEMANAGER_MQH
#define XTG_TRADEMANAGER_MQH

class CXtgTradeManager
  {
private:
   string            m_sym;
   long              m_magic;
   ulong             m_ids[];     // position identifiers
   double            m_risk[];    // initial SL distance (price units) = 1R

   int               FindCache(const ulong id)
     {
      for(int i=0;i<ArraySize(m_ids);i++)
         if(m_ids[i]==id)
            return i;
      return -1;
     }

   //--- 1R = distance between entry and the SL of the opening order
   double            InitialRisk(const ulong posId,const double open,const double curSL,const double tp)
     {
      int idx=FindCache(posId);
      if(idx>=0)
         return m_risk[idx];
      double sl=0;
      if(HistorySelectByPosition((long)posId))
        {
         datetime best=0;
         int n=HistoryOrdersTotal();
         for(int i=0;i<n;i++)
           {
            ulong o=HistoryOrderGetTicket(i);
            if(o==0) continue;
            datetime t=(datetime)HistoryOrderGetInteger(o,ORDER_TIME_SETUP);
            if(best==0 || t<best)
              {
               best=t;
               sl=HistoryOrderGetDouble(o,ORDER_SL);
              }
           }
        }
      double r=(sl>0 ? MathAbs(open-sl) : 0);
      if(r<=0 && curSL>0)
         r=MathAbs(open-curSL);
      if(r<=0 && tp>0)
         r=MathAbs(tp-open)/MathMax(2.0,InpRiskReward);
      //--- after a restart, a breakeven SL would give r~0: fall back to TP/RR
      if(tp>0 && r<MathAbs(tp-open)/(MathMax(2.0,InpRiskReward)*4.0))
         r=MathAbs(tp-open)/MathMax(2.0,InpRiskReward);
      if(r>0)
        {
         int n=ArraySize(m_ids);
         ArrayResize(m_ids,n+1);
         ArrayResize(m_risk,n+1);
         m_ids[n]=posId;
         m_risk[n]=r;
        }
      return r;
     }

   double            Norm(const double p)
     {
      double t=SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_SIZE);
      if(t<=0) t=SymbolInfoDouble(m_sym,SYMBOL_POINT);
      return NormalizeDouble(MathRound(p/t)*t,(int)SymbolInfoInteger(m_sym,SYMBOL_DIGITS));
     }

public:
   void              Init(const string sym,const long magic)
     {
      m_sym=sym;
      m_magic=magic;
      ArrayResize(m_ids,0);
      ArrayResize(m_risk,0);
     }

   //--- remember 1R for a freshly opened position (avoids history lookups)
   void              Remember(const ulong posId,const double risk)
     {
      if(posId==0 || risk<=0 || FindCache(posId)>=0)
         return;
      int n=ArraySize(m_ids);
      ArrayResize(m_ids,n+1);
      ArrayResize(m_risk,n+1);
      m_ids[n]=posId;
      m_risk[n]=risk;
     }

   //--- breakeven + trailing; call on every tick
   void              Manage(const double atr)
     {
      MqlTick t;
      if(!SymbolInfoTick(m_sym,t))
         return;
      double point=SymbolInfoDouble(m_sym,SYMBOL_POINT);
      double stopLvl=(double)SymbolInfoInteger(m_sym,SYMBOL_TRADE_STOPS_LEVEL)*point;
      double freeze=(double)SymbolInfoInteger(m_sym,SYMBOL_TRADE_FREEZE_LEVEL)*point;
      double tick=SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_SIZE);
      if(tick<=0) tick=point;

      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym || PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
         double open=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL);
         double tp=PositionGetDouble(POSITION_TP);
         ulong  pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         double r=InitialRisk(pid,open,sl,tp);
         if(r<=0) continue;

         double price=(buy ? t.bid : t.ask);           // price at which the position would close
         double gain=(buy ? price-open : open-price);   // favourable move
         double newSL=sl;

         //--- 1) breakeven at InpBETriggerR
         if(InpUseBreakeven && gain>=InpBETriggerR*r)
           {
            double be=(buy ? open+InpBELockR*r : open-InpBELockR*r);
            if(buy ? (sl<be-tick/2 || sl==0) : (sl>be+tick/2 || sl==0))
               newSL=be;
           }
         //--- 2) ATR trailing after InpTrailStartR
         if(InpUseTrailing && atr>0 && gain>=InpTrailStartR*r)
           {
            double tr=(buy ? price-InpTrailAtrMult*atr : price+InpTrailAtrMult*atr);
            if(buy ? tr>newSL : (tr<newSL || newSL==0))
               newSL=tr;
           }
         if(newSL==sl)
            continue;
         newSL=Norm(newSL);
         //--- only tighten, respect stop & freeze levels, need at least one tick improvement
         if(buy)
           {
            if(sl>0 && newSL<=sl+tick/2) continue;
            if(price-newSL<=stopLvl) continue;
            if(sl>0 && price-sl<=freeze) continue;
           }
         else
           {
            if(sl>0 && newSL>=sl-tick/2) continue;
            if(newSL-price<=stopLvl) continue;
            if(sl>0 && sl-price<=freeze) continue;
           }
         if(g_exec.Modify(ticket,newSL,tp))
            g_log.Info(StringFormat("SL #%I64u %.2f -> %.2f (gain %.2fR)",ticket,sl,newSL,gain/r));
        }
     }

   //--- close positions of direction posDir according to the opposite-exit rule
   void              CloseOnOpposite(const int posDir,const string reason)
     {
      if(InpOppExitMode==XTG_OPP_OFF)
         return;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym || PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         int dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
         if(dir!=posDir) continue;
         double pl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
         bool doClose=(InpOppExitMode==XTG_OPP_ANY) ||
                      (InpOppExitMode==XTG_OPP_IF_PROFIT && pl>0) ||
                      (InpOppExitMode==XTG_OPP_IF_LOSS && pl<0);
         if(doClose)
            g_exec.Close(ticket,reason);
        }
     }

   //--- unconditional close of this direction (H1 flip exit) or all (dir=0)
   int               CloseAll(const int onlyDir,const string reason)
     {
      int closed=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym || PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         int dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
         if(onlyDir!=0 && dir!=onlyDir) continue;
         if(g_exec.Close(ticket,reason))
            closed++;
        }
      return closed;
     }

   int               OpenDirection(void)
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym || PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         return (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
        }
      return 0;
     }

   double            FloatingPL(void)
     {
      double s=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym || PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         s+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
        }
      return s;
     }
  };

CXtgTradeManager g_tm;

#endif // XTG_TRADEMANAGER_MQH
//+------------------------------------------------------------------+
