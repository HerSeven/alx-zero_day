//+------------------------------------------------------------------+
//|                                                    Stats.mqh     |
//|  Performance statistics computed from the deal history of this   |
//|  EA (magic + symbol): win rate, profit factor, expected payoff,  |
//|  average R, payoff ratio, consecutive wins/losses, drawdowns.    |
//|  Used by OnTester() (optimisation criterion) and for the report. |
//+------------------------------------------------------------------+
#ifndef XTG_STATS_MQH
#define XTG_STATS_MQH

struct SXtgStats
  {
   int               trades,wins,losses;
   double            grossProfit,grossLoss,net;
   double            winRate,profitFactor,expectedPayoff;
   double            avgWin,avgLoss,payoffRatio;
   double            avgR,sumR;
   int               rCount;
   int               maxConsecLosses,maxConsecWins;
   double            maxBalanceDD,maxBalanceDDPct;
   double            equityDDPct,equityDD;
   double            initialDeposit;
  };

class CXtgStats
  {
private:
   //--- per-position accumulation
   long              m_pid[];
   int               m_dir[];
   double            m_inPrice[],m_inVol[],m_outPV[],m_outVol[],m_pl[],m_sl[];
   datetime          m_closeTime[];

   int               Find(const long pid)
     {
      for(int i=ArraySize(m_pid)-1;i>=0;i--)
         if(m_pid[i]==pid)
            return i;
      return -1;
     }

   int               Add(const long pid)
     {
      int n=ArraySize(m_pid);
      ArrayResize(m_pid,n+1);      ArrayResize(m_dir,n+1);
      ArrayResize(m_inPrice,n+1);  ArrayResize(m_inVol,n+1);
      ArrayResize(m_outPV,n+1);    ArrayResize(m_outVol,n+1);
      ArrayResize(m_pl,n+1);       ArrayResize(m_sl,n+1);
      ArrayResize(m_closeTime,n+1);
      m_pid[n]=pid; m_dir[n]=0; m_inPrice[n]=0; m_inVol[n]=0; m_outPV[n]=0; m_outVol[n]=0;
      m_pl[n]=0; m_sl[n]=0; m_closeTime[n]=0;
      return n;
     }

public:
   void              Compute(const string sym,const long magic,SXtgStats &st)
     {
      st.trades=0; st.wins=0; st.losses=0;
      st.grossProfit=0; st.grossLoss=0; st.net=0;
      st.winRate=0; st.profitFactor=0; st.expectedPayoff=0;
      st.avgWin=0; st.avgLoss=0; st.payoffRatio=0;
      st.avgR=0; st.sumR=0; st.rCount=0;
      st.maxConsecLosses=0; st.maxConsecWins=0;
      st.maxBalanceDD=0; st.maxBalanceDDPct=0; st.equityDDPct=0; st.equityDD=0;
      st.initialDeposit=0;

      ArrayResize(m_pid,0); ArrayResize(m_dir,0); ArrayResize(m_inPrice,0); ArrayResize(m_inVol,0);
      ArrayResize(m_outPV,0); ArrayResize(m_outVol,0); ArrayResize(m_pl,0); ArrayResize(m_sl,0);
      ArrayResize(m_closeTime,0);

      if(!HistorySelect(0,TimeCurrent()+86400))
         return;

      double allFlow=0;
      int nd=HistoryDealsTotal();
      for(int i=0;i<nd;i++)
        {
         ulong d=HistoryDealGetTicket(i);
         if(d==0) continue;
         double cash=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)
                     +HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
         allFlow+=cash;
         if(HistoryDealGetInteger(d,DEAL_MAGIC)!=magic) continue;
         if(HistoryDealGetString(d,DEAL_SYMBOL)!=sym) continue;
         long type=HistoryDealGetInteger(d,DEAL_TYPE);
         if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
         long pid=HistoryDealGetInteger(d,DEAL_POSITION_ID);
         long entry=HistoryDealGetInteger(d,DEAL_ENTRY);
         double vol=HistoryDealGetDouble(d,DEAL_VOLUME);
         double price=HistoryDealGetDouble(d,DEAL_PRICE);
         int k=Find(pid);
         if(k<0) k=Add(pid);
         m_pl[k]+=cash;
         if(entry==DEAL_ENTRY_IN)
           {
            m_dir[k]=(type==DEAL_TYPE_BUY ? 1 : -1);
            m_inPrice[k]=(m_inVol[k]*m_inPrice[k]+vol*price)/MathMax(1e-12,m_inVol[k]+vol);
            m_inVol[k]+=vol;
           }
         else
           {
            m_outPV[k]+=vol*price;
            m_outVol[k]+=vol;
            m_closeTime[k]=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
           }
        }

      //--- initial SL from the first order of each position
      int no=HistoryOrdersTotal();
      for(int i=0;i<no;i++)
        {
         ulong o=HistoryOrderGetTicket(i);
         if(o==0) continue;
         if(HistoryOrderGetInteger(o,ORDER_MAGIC)!=magic) continue;
         long pid=HistoryOrderGetInteger(o,ORDER_POSITION_ID);
         int k=Find(pid);
         if(k<0 || m_sl[k]!=0) continue;
         m_sl[k]=HistoryOrderGetDouble(o,ORDER_SL);
        }

      //--- order closed positions by close time (insertion sort of indices)
      int n=ArraySize(m_pid);
      int idx[];
      ArrayResize(idx,0);
      for(int i=0;i<n;i++)
        {
         if(m_inVol[i]<=0 || m_outVol[i]<m_inVol[i]*0.999) continue;   // still open
         int c=ArraySize(idx);
         ArrayResize(idx,c+1);
         int j=c;
         while(j>0 && m_closeTime[idx[j-1]]>m_closeTime[i])
           {
            idx[j]=idx[j-1];
            j--;
           }
         idx[j]=i;
        }

      double startBal=AccountInfoDouble(ACCOUNT_BALANCE)-allFlow;
      if(MQLInfoInteger(MQL_TESTER)!=0)
         startBal=TesterStatistics(STAT_INITIAL_DEPOSIT);
      st.initialDeposit=startBal;
      double bal=startBal,peak=startBal;
      int cw=0,cl=0;
      for(int q=0;q<ArraySize(idx);q++)
        {
         int i=idx[q];
         double pl=m_pl[i];
         st.trades++;
         st.net+=pl;
         if(pl>0) { st.wins++; st.grossProfit+=pl; cw++; cl=0; }
         else     { st.losses++; st.grossLoss+=-pl; cl++; cw=0; }
         st.maxConsecWins=MathMax(st.maxConsecWins,cw);
         st.maxConsecLosses=MathMax(st.maxConsecLosses,cl);
         //--- R multiple from prices
         if(m_sl[i]>0 && m_inPrice[i]>0)
           {
            double risk=MathAbs(m_inPrice[i]-m_sl[i]);
            double exitPx=m_outPV[i]/m_outVol[i];
            if(risk>0)
              {
               st.sumR+=(exitPx-m_inPrice[i])*m_dir[i]/risk;
               st.rCount++;
              }
           }
         bal+=pl;
         if(bal>peak) peak=bal;
         double dd=peak-bal;
         if(dd>st.maxBalanceDD)
           {
            st.maxBalanceDD=dd;
            st.maxBalanceDDPct=(peak>0 ? 100.0*dd/peak : 0);
           }
        }
      if(st.trades>0)
        {
         st.winRate=100.0*st.wins/st.trades;
         st.expectedPayoff=st.net/st.trades;
        }
      st.profitFactor=(st.grossLoss>0 ? st.grossProfit/st.grossLoss : (st.grossProfit>0 ? 99.0 : 0));
      st.avgWin=(st.wins>0 ? st.grossProfit/st.wins : 0);
      st.avgLoss=(st.losses>0 ? st.grossLoss/st.losses : 0);
      st.payoffRatio=(st.avgLoss>0 ? st.avgWin/st.avgLoss : 0);
      st.avgR=(st.rCount>0 ? st.sumR/st.rCount : 0);
      if(MQLInfoInteger(MQL_TESTER)!=0)
        {
         st.equityDDPct=TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
         st.equityDD=TesterStatistics(STAT_EQUITY_DD);
        }
      else
        {
         st.equityDDPct=st.maxBalanceDDPct;
         st.equityDD=st.maxBalanceDD;
        }
     }

   string            ToText(const SXtgStats &st)
     {
      string s="";
      s+="Total trades            : "+IntegerToString(st.trades)+"\n";
      s+="Wins / losses           : "+IntegerToString(st.wins)+" / "+IntegerToString(st.losses)+"\n";
      s+="Win rate                : "+DoubleToString(st.winRate,2)+" %\n";
      s+="Net profit              : "+DoubleToString(st.net,2)+"\n";
      s+="Gross profit / loss     : "+DoubleToString(st.grossProfit,2)+" / "+DoubleToString(st.grossLoss,2)+"\n";
      s+="Profit factor           : "+DoubleToString(st.profitFactor,2)+"\n";
      s+="Expected payoff / trade : "+DoubleToString(st.expectedPayoff,2)+"\n";
      s+="Average win / loss      : "+DoubleToString(st.avgWin,2)+" / "+DoubleToString(st.avgLoss,2)+"\n";
      s+="Realised reward:risk    : 1:"+DoubleToString(st.payoffRatio,2)+"\n";
      s+="Average R per trade     : "+DoubleToString(st.avgR,3)+" R\n";
      s+="Max consecutive losses  : "+IntegerToString(st.maxConsecLosses)+"\n";
      s+="Max consecutive wins    : "+IntegerToString(st.maxConsecWins)+"\n";
      s+="Max balance drawdown    : "+DoubleToString(st.maxBalanceDD,2)+" ("+DoubleToString(st.maxBalanceDDPct,2)+" %)\n";
      s+="Max equity drawdown     : "+DoubleToString(st.equityDD,2)+" ("+DoubleToString(st.equityDDPct,2)+" %)\n";
      return s;
     }

   void              WriteCsv(const string file,const string sym,const SXtgStats &st)
     {
      int h=FileOpen(file,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
      if(h==INVALID_HANDLE)
        {
         g_log.Warn("Cannot write report "+file+" (err "+IntegerToString(GetLastError())+")");
         return;
        }
      FileWrite(h,"metric","value");
      FileWrite(h,"symbol",sym);
      FileWrite(h,"initial_deposit",DoubleToString(st.initialDeposit,2));
      FileWrite(h,"total_trades",IntegerToString(st.trades));
      FileWrite(h,"wins",IntegerToString(st.wins));
      FileWrite(h,"losses",IntegerToString(st.losses));
      FileWrite(h,"win_rate_pct",DoubleToString(st.winRate,2));
      FileWrite(h,"net_profit",DoubleToString(st.net,2));
      FileWrite(h,"gross_profit",DoubleToString(st.grossProfit,2));
      FileWrite(h,"gross_loss",DoubleToString(st.grossLoss,2));
      FileWrite(h,"profit_factor",DoubleToString(st.profitFactor,3));
      FileWrite(h,"expected_payoff",DoubleToString(st.expectedPayoff,2));
      FileWrite(h,"avg_win",DoubleToString(st.avgWin,2));
      FileWrite(h,"avg_loss",DoubleToString(st.avgLoss,2));
      FileWrite(h,"payoff_ratio",DoubleToString(st.payoffRatio,3));
      FileWrite(h,"avg_r_multiple",DoubleToString(st.avgR,3));
      FileWrite(h,"max_consecutive_losses",IntegerToString(st.maxConsecLosses));
      FileWrite(h,"max_consecutive_wins",IntegerToString(st.maxConsecWins));
      FileWrite(h,"max_balance_dd",DoubleToString(st.maxBalanceDD,2));
      FileWrite(h,"max_balance_dd_pct",DoubleToString(st.maxBalanceDDPct,2));
      FileWrite(h,"max_equity_dd",DoubleToString(st.equityDD,2));
      FileWrite(h,"max_equity_dd_pct",DoubleToString(st.equityDDPct,2));
      FileClose(h);
      g_log.Info("Performance report written to Common\\Files\\"+file);
     }

   double            Criterion(const SXtgStats &st)
     {
      if(st.trades<InpOptMinTrades)
         return 0.0;
      switch(InpOptCriterion)
        {
         case XTG_CRIT_NET_PROFIT:
            return st.net;
         case XTG_CRIT_PROFIT_FACTOR:
            return st.profitFactor;
         case XTG_CRIT_RECOVERY:
            return (st.equityDD>0 ? st.net/st.equityDD : st.net);
         case XTG_CRIT_EXPECTANCY_R:
            return st.avgR;
         default:
           {
            if(st.net<=0)
               return 0.0;
            double pf=MathMin(st.profitFactor,5.0);
            double dd=MathMin(st.equityDDPct,99.0)/100.0;
            return pf*MathSqrt((double)st.trades)*(1.0-dd);
           }
        }
      return 0.0;
     }
  };

CXtgStats g_stats;

#endif // XTG_STATS_MQH
//+------------------------------------------------------------------+
