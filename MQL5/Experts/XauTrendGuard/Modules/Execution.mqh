//+------------------------------------------------------------------+
//|                                                Execution.mqh     |
//|  Order execution through CTrade with retries, filling-mode       |
//|  fallback, permission checks and an error cooldown.              |
//+------------------------------------------------------------------+
#ifndef XTG_EXECUTION_MQH
#define XTG_EXECUTION_MQH

#include <Trade\Trade.mqh>

class CXtgExecution
  {
private:
   CTrade            m_trade;
   string            m_sym;
   int               m_consecErrors;
   datetime          m_cooldownUntil;
   string            m_lastError;

   bool              Retryable(const uint rc)
     {
      return (rc==TRADE_RETCODE_REQUOTE || rc==TRADE_RETCODE_PRICE_CHANGED ||
              rc==TRADE_RETCODE_PRICE_OFF || rc==TRADE_RETCODE_TIMEOUT ||
              rc==TRADE_RETCODE_CONNECTION || rc==TRADE_RETCODE_TOO_MANY_REQUESTS);
     }

   bool              Success(const uint rc)
     {
      return (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED);
     }

   void              RegisterFailure(const string what)
     {
      m_consecErrors++;
      m_lastError=what;
      g_log.Error(what);
      if(m_consecErrors>=InpMaxConsecErrors)
        {
         m_cooldownUntil=TimeCurrent()+InpErrorCooldownMin*60;
         g_log.Warn("Too many consecutive execution errors - trading paused until "+
                    TimeToString(m_cooldownUntil,TIME_DATE|TIME_MINUTES));
         m_consecErrors=0;
        }
     }

public:
                     CXtgExecution(void) : m_sym(""), m_consecErrors(0), m_cooldownUntil(0), m_lastError("") {}

   void              Init(const string sym,const long magic)
     {
      m_sym=sym;
      m_trade.SetExpertMagicNumber((ulong)magic);
      m_trade.SetDeviationInPoints((ulong)InpSlippagePoints);
      m_trade.SetTypeFillingBySymbol(sym);
      m_trade.SetMarginMode();
      m_trade.SetAsyncMode(false);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
     }

   string            LastError(void) const { return m_lastError; }

   bool              InCooldown(string &why)
     {
      if(TimeCurrent()<m_cooldownUntil)
        {
         why="Error cooldown until "+TimeToString(m_cooldownUntil,TIME_MINUTES);
         return true;
        }
      return false;
     }

   //--- terminal / account / symbol permissions
   bool              TradingPermitted(string &why)
     {
      if(MQLInfoInteger(MQL_TESTER)==0)
        {
         if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)==0)
           { why="AutoTrading disabled in terminal (Algo Trading button)"; return false; }
         if(MQLInfoInteger(MQL_TRADE_ALLOWED)==0)
           { why="'Allow Algo Trading' disabled in EA properties"; return false; }
         if(TerminalInfoInteger(TERMINAL_CONNECTED)==0)
           { why="No connection to trade server"; return false; }
        }
      if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)==0)
        { why="Trading not allowed for this account (investor password?)"; return false; }
      if(AccountInfoInteger(ACCOUNT_TRADE_EXPERT)==0)
        { why="Broker does not allow EA trading on this account"; return false; }
      long mode=SymbolInfoInteger(m_sym,SYMBOL_TRADE_MODE);
      if(mode!=SYMBOL_TRADE_MODE_FULL && mode!=SYMBOL_TRADE_MODE_LONGONLY && mode!=SYMBOL_TRADE_MODE_SHORTONLY)
        { why="Symbol trade mode does not allow new positions"; return false; }
      return true;
     }

   bool              DirectionAllowedBySymbol(const int dir)
     {
      long mode=SymbolInfoInteger(m_sym,SYMBOL_TRADE_MODE);
      if(mode==SYMBOL_TRADE_MODE_LONGONLY && dir<0) return false;
      if(mode==SYMBOL_TRADE_MODE_SHORTONLY && dir>0) return false;
      return true;
     }

   //--- open a market position; returns position ticket (0 on failure)
   ulong             Open(const int dir,const double lots,const double sl,const double tp,const string comment)
     {
      ENUM_ORDER_TYPE type=(dir>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      ENUM_ORDER_TYPE_FILLING fills[3]={ORDER_FILLING_FOK,ORDER_FILLING_IOC,ORDER_FILLING_RETURN};
      int fillIdx=-1;
      int retries=MathMax(1,InpMaxRetries);
      for(int attempt=0;attempt<retries;attempt++)
        {
         MqlTick t;
         if(!SymbolInfoTick(m_sym,t))
           { RegisterFailure("Open: no tick for "+m_sym); return 0; }
         double price=(dir>0 ? t.ask : t.bid);
         //--- SL/TP must still be on the correct side of the live price
         if((dir>0 && (sl>=t.bid || tp<=t.ask)) || (dir<0 && (sl<=t.ask || tp>=t.bid)))
           {
            g_log.Warn("Open aborted: price moved through SL/TP levels before execution");
            return 0;
           }
         ResetLastError();
         bool sent=m_trade.PositionOpen(m_sym,type,lots,price,sl,tp,comment);
         uint rc=m_trade.ResultRetcode();
         if(sent && Success(rc))
           {
            m_consecErrors=0;
            ulong deal=m_trade.ResultDeal();
            ulong pos=0;
            if(deal>0 && HistoryDealSelect(deal))
               pos=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
            g_log.Info(StringFormat("OPEN %s %.2f lots @%.2f SL %.2f TP %.2f (deal #%I64u)",
                                    dir>0 ? "BUY" : "SELL",lots,m_trade.ResultPrice(),sl,tp,deal));
            return (pos>0 ? pos : (deal>0 ? deal : 1));
           }
         string desc=m_trade.ResultRetcodeDescription();
         g_log.Warn("Open attempt "+IntegerToString(attempt+1)+" failed: "+IntegerToString(rc)+" "+desc);
         if(rc==TRADE_RETCODE_INVALID_FILL)
           {
            fillIdx++;
            if(fillIdx<3)
              {
               m_trade.SetTypeFilling(fills[fillIdx]);
               attempt--;   // filling change does not consume a retry
               continue;
              }
           }
         if(!Retryable(rc))
           {
            RegisterFailure("Order rejected: "+IntegerToString(rc)+" "+desc);
            return 0;
           }
         Sleep(300);
        }
      RegisterFailure("Order failed after "+IntegerToString(retries)+" attempts");
      return 0;
     }

   bool              Modify(const ulong ticket,const double sl,const double tp)
     {
      if(!m_trade.PositionModify(ticket,sl,tp))
        {
         uint rc=m_trade.ResultRetcode();
         if(rc!=TRADE_RETCODE_NO_CHANGES)
            g_log.Warn("Modify #"+IntegerToString((long)ticket)+" failed: "+IntegerToString(rc)+" "+m_trade.ResultRetcodeDescription());
         return false;
        }
      return Success(m_trade.ResultRetcode()) || m_trade.ResultRetcode()==TRADE_RETCODE_NO_CHANGES;
     }

   bool              Close(const ulong ticket,const string reason)
     {
      for(int attempt=0;attempt<MathMax(1,InpMaxRetries);attempt++)
        {
         if(m_trade.PositionClose(ticket,(ulong)InpSlippagePoints) && Success(m_trade.ResultRetcode()))
           {
            g_log.Info("CLOSE #"+IntegerToString((long)ticket)+" - "+reason);
            return true;
           }
         uint rc=m_trade.ResultRetcode();
         g_log.Warn("Close #"+IntegerToString((long)ticket)+" failed: "+IntegerToString(rc)+" "+m_trade.ResultRetcodeDescription());
         if(!Retryable(rc))
            break;
         Sleep(300);
        }
      return false;
     }
  };

CXtgExecution g_exec;

#endif // XTG_EXECUTION_MQH
//+------------------------------------------------------------------+
