//+------------------------------------------------------------------+
//|                                                   Logger.mqh     |
//|  Levelled logging to the Experts journal and (optionally) a file |
//+------------------------------------------------------------------+
#ifndef XTG_LOGGER_MQH
#define XTG_LOGGER_MQH

class CXtgLogger
  {
private:
   int               m_level;
   bool              m_toFile;
   string            m_file;

   void              Write(const int lvl,const string tag,const string msg)
     {
      if(lvl>m_level)
         return;
      string line="[XTG]["+tag+"] "+msg;
      Print(line);
      if(!m_toFile)
         return;
      int h=FileOpen(m_file,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
      if(h==INVALID_HANDLE)
         return;
      FileSeek(h,0,SEEK_END);
      FileWriteString(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+" "+line+"\r\n");
      FileClose(h);
     }

public:
                     CXtgLogger(void) : m_level(XTG_LOG_INFO), m_toFile(false), m_file("XauTrendGuard.log") {}

   void              Init(const int level,const bool toFile,const string file)
     {
      m_level=level;
      m_toFile=toFile;
      m_file=file;
     }

   void              Error(const string msg) { Write(XTG_LOG_ERROR,"ERROR",msg); }
   void              Warn(const string msg)  { Write(XTG_LOG_WARN,"WARN",msg);   }
   void              Info(const string msg)  { Write(XTG_LOG_INFO,"INFO",msg);   }
   void              Debug(const string msg) { Write(XTG_LOG_DEBUG,"DEBUG",msg); }
  };

CXtgLogger g_log;

#endif // XTG_LOGGER_MQH
//+------------------------------------------------------------------+
