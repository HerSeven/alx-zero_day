//+------------------------------------------------------------------+
//|                                              SymbolGuard.mqh     |
//|  Verifies that a symbol is Gold vs USD and finds broker variants |
//|  such as XAUUSD, XAUUSD.a, XAUUSDm, XAUUSD+, #XAUUSD, GOLD.      |
//+------------------------------------------------------------------+
#ifndef XTG_SYMBOLGUARD_MQH
#define XTG_SYMBOLGUARD_MQH

//--- Upper-case and strip everything that is not A-Z / 0-9
string XtgNormalizeName(const string s)
  {
   string u=s;
   StringToUpper(u);
   string out="";
   int len=StringLen(u);
   for(int i=0;i<len;i++)
     {
      ushort c=StringGetCharacter(u,i);
      if((c>='A' && c<='Z') || (c>='0' && c<='9'))
         out+=ShortToString(c);
     }
   return out;
  }

string XtgUpper(const string s)
  {
   string u=s;
   StringToUpper(u);
   return u;
  }

//--- Returns true only if the symbol is verified as Gold quoted in USD
bool XtgIsGoldSymbol(const string sym,string &why)
  {
   long digits=0;
   if(!SymbolInfoInteger(sym,SYMBOL_DIGITS,digits))
     {
      why="symbol '"+sym+"' does not exist on this server";
      return false;
     }
   string n     = XtgNormalizeName(sym);
   string base  = XtgUpper(SymbolInfoString(sym,SYMBOL_CURRENCY_BASE));
   string prof  = XtgUpper(SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT));
   string desc  = XtgUpper(SymbolInfoString(sym,SYMBOL_DESCRIPTION));

   //--- hard exclusions: silver, other metals, gold in other currencies, gold-related indices/ETFs
   string bad[]={"XAG","SILVER","XPT","XPD","PLATIN","PALLAD","MINER","ETF","GDX",
                 "XAUEUR","XAUGBP","XAUAUD","XAUJPY","XAUCHF","XAUCNH","XAUTRY","XAUXAG",
                 "GOLDEUR","GOLDGBP","GOLDAUD","GOLDJPY","GOLDCHF"};
   for(int i=0;i<ArraySize(bad);i++)
      if(StringFind(n,bad[i])>=0)
        {
         why="name contains '"+bad[i]+"' (not XAU/USD)";
         return false;
        }

   bool nameXau  = (StringFind(n,"XAUUSD")>=0);
   bool nameGold = (StringFind(n,"GOLD")>=0);
   if(!nameXau && !nameGold)
     {
      why="name is not XAUUSD/GOLD";
      return false;
     }
   if(prof!="USD")
     {
      why="profit currency is '"+prof+"', expected USD";
      return false;
     }
   //--- 'GOLD' names are ambiguous - require base currency or description to confirm
   if(!nameXau)
     {
      if(base!="XAU" && StringFind(desc,"GOLD")<0 && StringFind(desc,"XAU")<0)
        {
         why="'GOLD' name not confirmed by base currency / description";
         return false;
        }
     }
   //--- must be a tradable CFD/forex-style contract, not disabled
   long mode=SymbolInfoInteger(sym,SYMBOL_TRADE_MODE);
   if(mode==SYMBOL_TRADE_MODE_DISABLED)
     {
      why="trading disabled for this symbol by broker";
      return false;
     }
   why="verified Gold (base="+base+", profit="+prof+", digits="+IntegerToString(digits)+")";
   return true;
  }

//--- Search Market Watch first, then the full symbol list
string XtgFindGoldSymbol(void)
  {
   string why;
   for(int pass=0;pass<2;pass++)
     {
      bool selected=(pass==0);
      int total=SymbolsTotal(selected);
      string best="";
      for(int i=0;i<total;i++)
        {
         string s=SymbolName(i,selected);
         if(!XtgIsGoldSymbol(s,why))
            continue;
         if(SymbolInfoInteger(s,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL)
            continue;
         //--- prefer the shortest name (plain XAUUSD over exotic variants)
         if(best=="" || StringLen(s)<StringLen(best))
            best=s;
        }
      if(best!="")
         return best;
     }
   return "";
  }

#endif // XTG_SYMBOLGUARD_MQH
//+------------------------------------------------------------------+
