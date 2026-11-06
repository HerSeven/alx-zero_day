//+------------------------------------------------------------------+
//|                                               NewsFilter.mqh     |
//|  High-impact USD news filter based on the built-in MT5 economic  |
//|  calendar, with an optional CSV source for Strategy Tester runs. |
//|  The filter NEVER pretends to work: if no data source is         |
//|  available its status is reported as INACTIVE.                   |
//+------------------------------------------------------------------+
#ifndef XTG_NEWSFILTER_MQH
#define XTG_NEWSFILTER_MQH

struct SXtgNews
  {
   datetime          utc;      // event time in UTC
   string            title;
   bool              key;      // CPI / NFP / FOMC / Fed rate / PCE
  };

class CXtgNewsFilter
  {
private:
   SXtgNews          m_items[];
   bool              m_active;
   bool              m_calendarOk;
   bool              m_csvOk;
   string            m_status;
   datetime          m_lastRefresh;
   bool              m_tester;

   bool              IsKeyEvent(const string name)
     {
      string u=name;
      StringToUpper(u);
      string keys[]={"CPI","CONSUMER PRICE","NONFARM","NON-FARM","PAYROLL","FOMC",
                     "FEDERAL FUNDS","FED INTEREST RATE","INTEREST RATE DECISION",
                     "PCE","PERSONAL CONSUMPTION","FED CHAIR","POWELL"};
      for(int i=0;i<ArraySize(keys);i++)
         if(StringFind(u,keys[i])>=0)
            return true;
      return false;
     }

   void              Add(const datetime utc,const string title,const bool key)
     {
      int n=ArraySize(m_items);
      ArrayResize(m_items,n+1);
      m_items[n].utc=utc;
      m_items[n].title=title;
      m_items[n].key=key;
     }

   //--- CSV format (one event per line, times in UTC):
   //    2024.06.07 12:30,Nonfarm Payrolls
   //    Lines starting with '#' are ignored.
   bool              LoadCsv(void)
     {
      if(InpNewsCsvFile=="")
         return false;
      int h=FileOpen(InpNewsCsvFile,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
      if(h==INVALID_HANDLE)
        {
         g_log.Warn("News CSV '"+InpNewsCsvFile+"' not found in Common\\Files (err "+IntegerToString(GetLastError())+")");
         return false;
        }
      int count=0;
      ushort sep=StringGetCharacter(",",0);
      while(!FileIsEnding(h))
        {
         string line=FileReadString(h);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(line=="" || StringGetCharacter(line,0)=='#')
            continue;
         string p[];
         if(StringSplit(line,sep,p)<2)
            continue;
         datetime t=StringToTime(p[0]);
         if(t<=0)
            continue;
         bool key=IsKeyEvent(p[1]);
         if(InpNewsOnlyKeyEvents && !key)
            continue;
         Add(t,p[1],key);
         count++;
        }
      FileClose(h);
      g_log.Info("News CSV loaded: "+IntegerToString(count)+" events");
      return (count>0);
     }

   bool              LoadCalendar(void)
     {
      if(m_tester)
         return false;   // MT5 calendar functions are not available in the Strategy Tester
      MqlCalendarValue vals[];
      datetime srv=TimeTradeServer();
      ResetLastError();
      CalendarValueHistory(vals,srv-7*86400,srv+7*86400,"US","USD");
      int err=GetLastError();
      int n=ArraySize(vals);
      if(n<=0)
        {
         //--- USD always has events within +/- 7 days, so zero means "no data"
         g_log.Warn("MT5 economic calendar returned no USD data (err "+IntegerToString(err)+")");
         return false;
        }
      //--- keep CSV items, replace calendar items
      ArrayResize(m_items,0);
      int kept=0;
      for(int i=0;i<n;i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[i].event_id,ev))
            continue;
         bool key=IsKeyEvent(ev.name);
         bool high=(ev.importance==CALENDAR_IMPORTANCE_HIGH);
         if(InpNewsOnlyKeyEvents)
           {
            if(!key)
               continue;
           }
         else
           {
            if(!high && !key)
               continue;
           }
         Add(g_time.ServerToUtc(vals[i].time),ev.name,key);
         kept++;
        }
      g_log.Debug("Calendar refresh: "+IntegerToString(kept)+" relevant USD events");
      return true;
     }

public:
                     CXtgNewsFilter(void) : m_active(false), m_calendarOk(false), m_csvOk(false),
                                         m_status("INACTIVE"), m_lastRefresh(0), m_tester(false) {}

   void              Init(void)
     {
      m_tester=(MQLInfoInteger(MQL_TESTER)!=0);
      ArrayResize(m_items,0);
      m_lastRefresh=0;
      if(!InpUseNewsFilter)
        {
         m_active=false;
         m_status="DISABLED by user";
         return;
        }
      Refresh(true);
     }

   void              Refresh(const bool force)
     {
      if(!InpUseNewsFilter)
         return;
      datetime now=TimeCurrent();
      //--- refresh every 15 min; retry every 5 min while no data source is available
      int every=(m_active ? 15*60 : 5*60);
      if(!force && m_lastRefresh!=0 && now-m_lastRefresh<every)
         return;
      if(m_tester && !force)
         return;    // tester: CSV is loaded once, the calendar never exists
      m_lastRefresh=now;
      if(m_tester)
        {
         if(!m_csvOk && ArraySize(m_items)==0)
            m_csvOk=LoadCsv();
        }
      else
        {
         m_calendarOk=LoadCalendar();
         if(!m_calendarOk)
           {
            ArrayResize(m_items,0);
            m_csvOk=LoadCsv();
           }
        }
      m_active=(m_calendarOk || m_csvOk);
      if(m_calendarOk)
         m_status="ACTIVE (MT5 calendar)";
      else if(m_csvOk)
         m_status="ACTIVE (CSV file)";
      else if(m_tester)
         m_status="INACTIVE - no calendar in tester";
      else
         m_status="INACTIVE - calendar unavailable";
     }

   bool              IsActive(void) const { return m_active; }
   string            Status(void) const   { return m_status; }

   //--- true when new entries must be blocked
   bool              IsBlocked(string &why)
     {
      if(!InpUseNewsFilter)
         return false;
      Refresh(false);
      if(!m_active)
        {
         if(InpNewsBlockIfOffline)
           {
            why="News data unavailable (blocking by setting)";
            return true;
           }
         return false;
        }
      datetime now=g_time.UtcNow();
      for(int i=0;i<ArraySize(m_items);i++)
        {
         datetime t=m_items[i].utc;
         if(now>=t-InpNewsBeforeMin*60 && now<=t+InpNewsAfterMin*60)
           {
            why="News: "+m_items[i].title+" @"+XtgHHMM(g_time.PolandFromUtc(t))+" PL";
            return true;
           }
        }
      return false;
     }

   //--- next upcoming event (for the dashboard)
   string            NextEvent(void)
     {
      if(!m_active)
         return "-";
      datetime now=g_time.UtcNow();
      datetime best=0;
      string title="";
      for(int i=0;i<ArraySize(m_items);i++)
        {
         datetime t=m_items[i].utc;
         if(t+InpNewsAfterMin*60<now)
            continue;
         if(best==0 || t<best)
           {
            best=t;
            title=m_items[i].title;
           }
        }
      if(best==0)
         return "none in window";
      if(StringLen(title)>22)
         title=StringSubstr(title,0,22);
      return title+" "+TimeToString(g_time.PolandFromUtc(best),TIME_DATE|TIME_MINUTES);
     }
  };

CXtgNewsFilter g_news;

#endif // XTG_NEWSFILTER_MQH
//+------------------------------------------------------------------+
