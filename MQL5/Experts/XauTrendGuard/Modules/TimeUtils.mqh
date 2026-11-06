//+------------------------------------------------------------------+
//|                                                TimeUtils.mqh     |
//|  UTC / broker / Poland (Europe/Warsaw) time conversion with      |
//|  automatic EU and US daylight-saving rules, and session filter.  |
//+------------------------------------------------------------------+
#ifndef XTG_TIMEUTILS_MQH
#define XTG_TIMEUTILS_MQH

datetime XtgMakeTime(const int y,const int m,const int d,const int h,const int mi)
  {
   MqlDateTime t;
   ZeroMemory(t);
   t.year=y; t.mon=m; t.day=d; t.hour=h; t.min=mi; t.sec=0;
   return StructToTime(t);
  }

int XtgDayOfWeek(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t,s);
   return s.day_of_week;
  }

int XtgMinuteOfDay(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t,s);
   return s.hour*60+s.min;
  }

datetime XtgDayStart(const datetime t)
  {
   return (datetime)(((long)t/86400)*86400);
  }

//--- n-th (1-based) Sunday of a month, 00:00
datetime XtgNthSunday(const int y,const int m,const int n)
  {
   datetime first=XtgMakeTime(y,m,1,0,0);
   int dow=XtgDayOfWeek(first);
   int day=1+((7-dow)%7)+7*(n-1);
   return XtgMakeTime(y,m,day,0,0);
  }

//--- last Sunday of a month, 00:00
datetime XtgLastSunday(const int y,const int m)
  {
   int ny=y,nm=m+1;
   if(nm>12) { nm=1; ny++; }
   datetime last=XtgMakeTime(ny,nm,1,0,0)-86400;
   int dow=XtgDayOfWeek(last);
   return last-dow*86400;
  }

//--- EU summer time: last Sunday of March 01:00 UTC -> last Sunday of October 01:00 UTC
bool XtgIsEUDst(const datetime utc)
  {
   MqlDateTime s;
   TimeToStruct(utc,s);
   datetime st=XtgLastSunday(s.year,3)+3600;
   datetime en=XtgLastSunday(s.year,10)+3600;
   return (utc>=st && utc<en);
  }

//--- US DST: 2nd Sunday of March 02:00 EST (07:00 UTC) -> 1st Sunday of November 02:00 EDT (06:00 UTC)
bool XtgIsUSDst(const datetime utc)
  {
   MqlDateTime s;
   TimeToStruct(utc,s);
   datetime st=XtgNthSunday(s.year,3,2)+7*3600;
   datetime en=XtgNthSunday(s.year,11,1)+6*3600;
   return (utc>=st && utc<en);
  }

//--- "HH:MM" -> minutes of day
int XtgParseHHMM(const string s,const int def)
  {
   string parts[];
   ushort sep=StringGetCharacter(":",0);
   if(StringSplit(s,sep,parts)!=2)
      return def;
   int h=(int)StringToInteger(parts[0]);
   int m=(int)StringToInteger(parts[1]);
   if(h<0 || h>23 || m<0 || m>59)
      return def;
   return h*60+m;
  }

//--- [start,end) window in minutes-of-day; supports windows across midnight
bool XtgInWindow(const int now,const int st,const int en)
  {
   if(st==en)
      return false;
   if(st<en)
      return (now>=st && now<en);
   return (now>=st || now<en);
  }

string XtgHHMM(const datetime t)
  {
   return TimeToString(t,TIME_MINUTES);
  }

//==================================================================
class CXtgTime
  {
private:
   bool              m_tester;
   int               m_offset;        // server - UTC, seconds
   datetime          m_lastCalc;
   bool              m_warned;

   int               RuleNYClose(const datetime serverTime)
     {
      //--- approximate UTC from winter offset to evaluate the US DST rule
      datetime approxUtc=serverTime-2*3600;
      return (XtgIsUSDst(approxUtc) ? 3 : 2)*3600;
     }

public:
                     CXtgTime(void) : m_tester(false), m_offset(2*3600), m_lastCalc(0), m_warned(false) {}

   void              Init(void)
     {
      m_tester=(MQLInfoInteger(MQL_TESTER)!=0);
      m_lastCalc=0;
      Update();
     }

   void              Update(void)
     {
      datetime srv=TimeCurrent();
      if(m_lastCalc!=0 && srv-m_lastCalc<60)
         return;
      m_lastCalc=srv;
      switch(InpServerTZMode)
        {
         case XTG_TZ_FIXED:
            m_offset=InpServerGMTOffset*3600;
            break;
         case XTG_TZ_NY_CLOSE:
            m_offset=RuleNYClose(srv);
            break;
         default:
            if(m_tester)
              {
               //--- TimeGMT() is not real in the tester; use the most common broker convention
               m_offset=RuleNYClose(srv);
               if(!m_warned)
                 {
                  g_log.Warn("Tester: server time zone AUTO -> using GMT+2/+3 (US DST) rule. Set FIXED if your broker differs.");
                  m_warned=true;
                 }
              }
            else
              {
               long diff=(long)(TimeTradeServer()-TimeGMT());
               m_offset=(int)(MathRound((double)diff/1800.0)*1800.0);
              }
            break;
        }
     }

   int               ServerOffset(void) const { return m_offset; }
   datetime          ServerNow(void) const    { return TimeCurrent(); }
   datetime          UtcNow(void) const       { return TimeCurrent()-m_offset; }
   datetime          ServerToUtc(const datetime srv) const { return srv-m_offset; }

   datetime          PolandFromUtc(const datetime utc) const
     {
      return utc+3600+(XtgIsEUDst(utc) ? 3600 : 0);
     }
   datetime          PolandNow(void) const { return PolandFromUtc(UtcNow()); }
   bool              PolandIsSummer(void) const { return XtgIsEUDst(UtcNow()); }
  };

CXtgTime g_time;

//==================================================================
class CXtgSessions
  {
private:
   int               m_lonS,m_lonE,m_nyS,m_nyE,m_ovS,m_ovE,m_friCut,m_wkClose;

public:
   void              Init(void)
     {
      m_lonS=XtgParseHHMM(InpLondonStart,9*60);
      m_lonE=XtgParseHHMM(InpLondonEnd,17*60+30);
      m_nyS =XtgParseHHMM(InpNewYorkStart,14*60+30);
      m_nyE =XtgParseHHMM(InpNewYorkEnd,21*60+30);
      m_ovS =XtgParseHHMM(InpOverlapStart,14*60+30);
      m_ovE =XtgParseHHMM(InpOverlapEnd,17*60+30);
      m_friCut=XtgParseHHMM(InpFridayCutoff,20*60);
      m_wkClose=XtgParseHHMM(InpWeekendCloseTime,21*60+30);
     }

   //--- name of the session(s) active right now (informational, ignores enable flags)
   string            CurrentName(void)
     {
      datetime pl=g_time.PolandNow();
      int dow=XtgDayOfWeek(pl);
      if(dow==0 || dow==6)
         return "Weekend";
      int m=XtgMinuteOfDay(pl);
      bool lon=XtgInWindow(m,m_lonS,m_lonE);
      bool ny =XtgInWindow(m,m_nyS,m_nyE);
      bool ov =XtgInWindow(m,m_ovS,m_ovE);
      if(ov || (lon && ny))
         return "London/NY overlap";
      if(lon)
         return "London";
      if(ny)
         return "New York";
      return "Off-session";
     }

   //--- true if new entries are allowed by the time filters
   bool              EntryAllowed(string &why)
     {
      datetime pl=g_time.PolandNow();
      int dow=XtgDayOfWeek(pl);
      if(dow==0 || dow==6)
        {
         why="Weekend";
         return false;
        }
      int m=XtgMinuteOfDay(pl);
      if(dow==5 && m>=m_friCut)
        {
         why="Friday cutoff ("+InpFridayCutoff+" PL)";
         return false;
        }
      //--- broker rollover around server midnight (swap / spread widening)
      int sm=XtgMinuteOfDay(g_time.ServerNow());
      if(sm>=1440-InpRolloverBeforeMin || sm<InpRolloverAfterMin)
        {
         why="Rollover window (server midnight)";
         return false;
        }
      bool ok=false;
      if(InpUseLondon  && XtgInWindow(m,m_lonS,m_lonE)) ok=true;
      if(InpUseNewYork && XtgInWindow(m,m_nyS,m_nyE))   ok=true;
      if(InpUseOverlap && XtgInWindow(m,m_ovS,m_ovE))   ok=true;
      if(!ok)
        {
         why="Outside enabled sessions (PL "+XtgHHMM(pl)+")";
         return false;
        }
      return true;
     }

   bool              IsWeekendCloseTime(void)
     {
      datetime pl=g_time.PolandNow();
      int dow=XtgDayOfWeek(pl);
      if(dow==6)
         return true;
      return (dow==5 && XtgMinuteOfDay(pl)>=m_wkClose);
     }
  };

CXtgSessions g_sessions;

#endif // XTG_TIMEUTILS_MQH
//+------------------------------------------------------------------+
