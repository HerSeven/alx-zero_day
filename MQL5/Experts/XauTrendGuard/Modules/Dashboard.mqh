//+------------------------------------------------------------------+
//|                                                Dashboard.mqh     |
//|  On-chart status panel with a PAUSE / RESUME button.             |
//+------------------------------------------------------------------+
#ifndef XTG_DASHBOARD_MQH
#define XTG_DASHBOARD_MQH

#define XTG_DASH_PREFIX "XTG_DASH_"
#define XTG_DASH_BUTTON "XTG_DASH_BTN_PAUSE"

class CXtgDashboard
  {
private:
   bool              m_enabled;
   int               m_rows;
   int               m_lineH;
   int               m_width;
   string            m_keys[];
   color             m_bg,m_border,m_label,m_value,m_good,m_bad,m_warn,m_title;

   void              MakeLabel(const string name,const int x,const int y,const string text,
                               const color clr,const int size,const string font)
     {
      if(ObjectFind(0,name)<0)
        {
         ObjectCreate(0,name,OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
         ObjectSetInteger(0,name,OBJPROP_BACK,false);
        }
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetString(0,name,OBJPROP_TEXT,text);
      ObjectSetString(0,name,OBJPROP_FONT,font);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
     }

   int               KeyIndex(const string key)
     {
      for(int i=0;i<ArraySize(m_keys);i++)
         if(m_keys[i]==key)
            return i;
      return -1;
     }

public:
                     CXtgDashboard(void) : m_enabled(false), m_rows(0), m_lineH(16), m_width(360) {}

   void              Init(void)
     {
      m_enabled=InpShowDashboard &&
                (MQLInfoInteger(MQL_TESTER)==0 || MQLInfoInteger(MQL_VISUAL_MODE)!=0);
      if(!m_enabled)
         return;
      m_bg=C'18,22,30'; m_border=C'60,70,90'; m_label=C'150,160,180'; m_value=clrWhite;
      m_good=C'60,200,120'; m_bad=C'235,80,80'; m_warn=C'240,180,60'; m_title=C'255,200,60';
      m_lineH=InpDashFontSize+8;
      m_width=InpDashFontSize*50;

      string keys[]={"Status","Symbol","Price","Trend","Timeframe","Session","Balance","Equity",
                     "Daily P/L","Drawdown","Weekly DD","Trades today","Open positions","Risk/trade",
                     "Spread","News filter","Next news","Last signal","No-trade reason"};
      m_rows=ArraySize(keys);
      ArrayResize(m_keys,m_rows);
      for(int i=0;i<m_rows;i++)
         m_keys[i]=keys[i];

      int h=m_lineH*(m_rows+2)+12;
      string bg=XTG_DASH_PREFIX+"BG";
      if(ObjectFind(0,bg)<0)
         ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,InpDashX);
      ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,InpDashY);
      ObjectSetInteger(0,bg,OBJPROP_XSIZE,m_width);
      ObjectSetInteger(0,bg,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,m_bg);
      ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,bg,OBJPROP_COLOR,m_border);
      ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,bg,OBJPROP_BACK,false);

      MakeLabel(XTG_DASH_PREFIX+"TITLE",InpDashX+10,InpDashY+6,"XauTrendGuard  |  Gold EA",m_title,InpDashFontSize+1,"Arial Bold");
      for(int i=0;i<m_rows;i++)
        {
         int y=InpDashY+8+m_lineH*(i+1)+4;
         MakeLabel(XTG_DASH_PREFIX+"K"+IntegerToString(i),InpDashX+10,y,m_keys[i]+":",m_label,InpDashFontSize,"Consolas");
         MakeLabel(XTG_DASH_PREFIX+"V"+IntegerToString(i),InpDashX+10+InpDashFontSize*13,y,"-",m_value,InpDashFontSize,"Consolas");
        }

      //--- pause / resume button
      if(ObjectFind(0,XTG_DASH_BUTTON)<0)
         ObjectCreate(0,XTG_DASH_BUTTON,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,XTG_DASH_BUTTON,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,XTG_DASH_BUTTON,OBJPROP_XDISTANCE,InpDashX+m_width-90);
      ObjectSetInteger(0,XTG_DASH_BUTTON,OBJPROP_YDISTANCE,InpDashY+4);
      ObjectSetInteger(0,XTG_DASH_BUTTON,OBJPROP_XSIZE,80);
      ObjectSetInteger(0,XTG_DASH_BUTTON,OBJPROP_YSIZE,m_lineH+2);
      ObjectSetInteger(0,XTG_DASH_BUTTON,OBJPROP_FONTSIZE,InpDashFontSize-1);
      ObjectSetInteger(0,XTG_DASH_BUTTON,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,XTG_DASH_BUTTON,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,XTG_DASH_BUTTON,OBJPROP_STATE,false);
      SetButton(false);
      ChartRedraw(0);
     }

   void              SetButton(const bool paused)
     {
      if(!m_enabled)
         return;
      ObjectSetString(0,XTG_DASH_BUTTON,OBJPROP_TEXT,paused ? "RESUME" : "PAUSE");
      ObjectSetInteger(0,XTG_DASH_BUTTON,OBJPROP_BGCOLOR,paused ? C'30,120,70' : C'150,50,50');
      ObjectSetInteger(0,XTG_DASH_BUTTON,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,XTG_DASH_BUTTON,OBJPROP_STATE,false);
     }

   bool              Enabled(void) const { return m_enabled; }

   //--- tone: 0 neutral, 1 good, -1 bad, 2 warning
   void              Set(const string key,const string value,const int tone=0)
     {
      if(!m_enabled)
         return;
      int i=KeyIndex(key);
      if(i<0)
         return;
      string v=value;
      if(StringLen(v)>44)
         v=StringSubstr(v,0,43)+"~";
      color c=m_value;
      if(tone==1) c=m_good;
      else if(tone==-1) c=m_bad;
      else if(tone==2) c=m_warn;
      string name=XTG_DASH_PREFIX+"V"+IntegerToString(i);
      ObjectSetString(0,name,OBJPROP_TEXT,v);
      ObjectSetInteger(0,name,OBJPROP_COLOR,c);
     }

   void              Redraw(void)
     {
      if(m_enabled)
         ChartRedraw(0);
     }

   void              Destroy(void)
     {
      ObjectsDeleteAll(0,XTG_DASH_PREFIX);
      ChartRedraw(0);
     }
  };

CXtgDashboard g_dash;

#endif // XTG_DASHBOARD_MQH
//+------------------------------------------------------------------+
