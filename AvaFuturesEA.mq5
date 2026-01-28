//+------------------------------------------------------------------+
//|                                                AvaFuturesEA.mq5 |
//|     Unique EA for AvaTrade Futures, by Kyle Backburn(2026)      |
//+------------------------------------------------------------------+
#property copyright "Copilot 2026"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//--- Telegram settings (fill in your details)
input bool   EnableTelegram     = true;
input string TELEGRAM_BOT_TOKEN = "8409309288:AAFX6cVp1RT-OJmUnBD1jN8VbKkFegNrxNM";
input string TELEGRAM_CHAT_ID   = "8181897048";

//--- Trading settings
input double Lots = 0.01;
input int    Slippage = 5;
input int    FastMAPeriod = 5;
input int    SlowMAPeriod = 20;
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_M1;
input double MinBalance = 70;
input double MaxBalance = 100;
input long   MagicNumber = 27012026;

//--- Global variables
string   symbols[];
int      fastMAHandles[];
int      slowMAHandles[];
datetime lastBarTime[];

//+------------------------------------------------------------------+
//| Helpers                                                         |
//+------------------------------------------------------------------+
bool   IsNewBarByIndex(const int idx);
bool   GetMAValue(const int handle,const int shift,double &value);
double NormalizeVolumeForSymbol(const string symbol,const double volume);
string UrlEncode(const string text);
bool   TelegramSend(const string text);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Get all symbols in Market Watch
   int total=SymbolsTotal(true);
   ArrayResize(symbols,total);
  ArrayResize(fastMAHandles,total);
  ArrayResize(slowMAHandles,total);
  ArrayResize(lastBarTime,total);

   for(int i=0;i<total;i++)
    {
    symbols[i]=SymbolName(i,true);
    SymbolSelect(symbols[i],true);

    fastMAHandles[i]=iMA(symbols[i],SignalTimeframe,FastMAPeriod,0,MODE_SMA,PRICE_CLOSE);
    slowMAHandles[i]=iMA(symbols[i],SignalTimeframe,SlowMAPeriod,0,MODE_SMA,PRICE_CLOSE);

    if(fastMAHandles[i]==INVALID_HANDLE || slowMAHandles[i]==INVALID_HANDLE)
      Print("Failed to create MA handles for ",symbols[i],". Error=",GetLastError());

    lastBarTime[i]=0;
    }
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   for(int i=0;i<ArraySize(symbols);i++)
     {
      if(fastMAHandles[i]!=INVALID_HANDLE) IndicatorRelease(fastMAHandles[i]);
      if(slowMAHandles[i]!=INVALID_HANDLE) IndicatorRelease(slowMAHandles[i]);
     }
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance<MinBalance || balance>MaxBalance)
      return;
   for(int i=0;i<ArraySize(symbols);i++)
     {
      string sym=symbols[i];

    if(!IsNewBarByIndex(i))
      continue;

    if(fastMAHandles[i]==INVALID_HANDLE || slowMAHandles[i]==INVALID_HANDLE)
      continue;

    double fast=0.0,slow=0.0,fastPrev=0.0,slowPrev=0.0;
    if(!GetMAValue(fastMAHandles[i],0,fast) || !GetMAValue(slowMAHandles[i],0,slow) ||
      !GetMAValue(fastMAHandles[i],1,fastPrev) || !GetMAValue(slowMAHandles[i],1,slowPrev))
      continue;

    if(PositionSelect(sym))
      continue;

    double volume=NormalizeVolumeForSymbol(sym,Lots);
    if(volume<=0.0)
      continue;
      //--- Buy signal
      if(fastPrev<slowPrev && fast>slow)
        {
      if(OrderSendMarket(sym,ORDER_TYPE_BUY,volume))
        TelegramSend("BUY "+sym+" Lot: "+DoubleToString(volume,2));
        }
      //--- Sell signal
      if(fastPrev>slowPrev && fast<slow)
        {
      if(OrderSendMarket(sym,ORDER_TYPE_SELL,volume))
        TelegramSend("SELL "+sym+" Lot: "+DoubleToString(volume,2));
        }
     }
  }
//+------------------------------------------------------------------+
//| Market order send helper                                         |
//+------------------------------------------------------------------+
bool OrderSendMarket(string symbol,ENUM_ORDER_TYPE type,double lot)
  {
   double price=type==ORDER_TYPE_BUY?SymbolInfoDouble(symbol,SYMBOL_ASK):SymbolInfoDouble(symbol,SYMBOL_BID);
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   bool result=trade.PositionOpen(symbol,type,lot,price,0,0);
   return result;
  }
//+------------------------------------------------------------------+
//| Trade event handler                                              |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &req,const MqlTradeResult &res)
  {
  if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0)
    return;

  if(!HistoryDealSelect(trans.deal))
    return;

  long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
  if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY)
    return;

  long dealType=HistoryDealGetInteger(trans.deal,DEAL_TYPE);
  string sym=HistoryDealGetString(trans.deal,DEAL_SYMBOL);
  double vol=HistoryDealGetDouble(trans.deal,DEAL_VOLUME);
  double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);

  string side="DEAL";
  if(dealType==DEAL_TYPE_BUY)  side="BUY";
  if(dealType==DEAL_TYPE_SELL) side="SELL";

  TelegramSend(side+" CLOSED "+sym+" Lot: "+DoubleToString(vol,2)+" P/L: "+DoubleToString(profit,2));
  }

//+------------------------------------------------------------------+
//| New bar detection per symbol/timeframe                          |
//+------------------------------------------------------------------+
bool IsNewBarByIndex(const int idx)
  {
  if(idx<0 || idx>=ArraySize(symbols))
    return false;

  datetime t=iTime(symbols[idx],SignalTimeframe,0);
  if(t<=0)
    return false;

  if(t!=lastBarTime[idx])
    {
    lastBarTime[idx]=t;
    return true;
    }
  return false;
  }

//+------------------------------------------------------------------+
//| Read MA value from handle                                       |
//+------------------------------------------------------------------+
bool GetMAValue(const int handle,const int shift,double &value)
  {
  if(handle==INVALID_HANDLE)
    return false;
  double buf[];
  ArraySetAsSeries(buf,true);
  int copied=CopyBuffer(handle,0,shift,1,buf);
  if(copied!=1)
    return false;
  value=buf[0];
  return true;
  }

//+------------------------------------------------------------------+
//| Normalize volume to symbol constraints                          |
//+------------------------------------------------------------------+
double NormalizeVolumeForSymbol(const string symbol,const double volume)
  {
  double vmin=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
  double vmax=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
  double vstep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
  if(vmin<=0.0 || vstep<=0.0)
    return 0.0;

  double v=MathMax(vmin,MathMin(volume,vmax));
  double steps=MathFloor((v - vmin)/vstep + 0.5);
  double normalized=vmin + steps*vstep;
  int digits=(int)MathRound(-MathLog10(vstep));
  if(digits<0) digits=0;
  return NormalizeDouble(normalized,digits);
  }

//+------------------------------------------------------------------+
//| URL-encode (UTF-8)                                              |
//+------------------------------------------------------------------+
string UrlEncode(const string text)
  {
  uchar bytes[];
  StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8);
  string out="";
  for(int i=0;i<ArraySize(bytes);i++)
    {
    int c=(int)bytes[i];
    if((c>='a' && c<='z') || (c>='A' && c<='Z') || (c>='0' && c<='9') || c=='-' || c=='_' || c=='.' || c=='~')
      {
      out += CharToString((ushort)c);
      }
    else if(c==' ')
      {
      out += "+";
      }
    else
      {
      out += StringFormat("%%%02X",c);
      }
    }
  return out;
  }

//+------------------------------------------------------------------+
//| Telegram send via WebRequest (POST form)                        |
//+------------------------------------------------------------------+
bool TelegramSend(const string text)
  {
  if(!EnableTelegram)
    return true;
  if(TELEGRAM_BOT_TOKEN=="" || TELEGRAM_CHAT_ID=="")
    return false;

  string url="https://api.telegram.org/bot"+TELEGRAM_BOT_TOKEN+"/sendMessage";
  string body="chat_id="+UrlEncode(TELEGRAM_CHAT_ID)+"&text="+UrlEncode(text);

  uchar data[];
  StringToCharArray(body,data,0,WHOLE_ARRAY,CP_UTF8);

  uchar result[];
  string result_headers="";
  ResetLastError();
  int timeout=5000;
  int status=WebRequest(
    "POST",
    url,
    "Content-Type: application/x-www-form-urlencoded\r\n",
    timeout,
    data,
    result,
    result_headers
  );

  if(status==-1)
    {
    Print("Telegram WebRequest failed. Error=",GetLastError()," (Remember to allow https://api.telegram.org in MT5 Options -> Expert Advisors)");
    return false;
    }
  return (status==200);
  }
//+------------------------------------------------------------------+
