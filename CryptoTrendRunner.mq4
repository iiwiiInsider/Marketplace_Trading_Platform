//+------------------------------------------------------------------+
//| CryptoTrendRunner.mq4 (Auto, robust, broker-safe)                |
//| Universal Crypto Trend EA (MT4)                                  |
//| Improved version + Telegram notifications (Jan 2026)             |
//| Built By Kyle Blackburn 27 January 2026                          |
//+------------------------------------------------------------------+
#property strict

//==================== INPUTS ======================================
input double RiskPercent        = 1.0;   // Risk per trade (% balance)
input int    MagicNumber        = 777777;
input int    MaxTrades          = 3;
input bool   LimitTradesPerSymbol = true;   // If true: MaxTrades applies per-symbol; else: MaxTrades total across all scanned symbols
input bool   OneTradePerSymbol    = true;   // If true: only 1 open trade per symbol at a time

input int    EMAFast            = 21;
input int    EMASlow            = 55;
input int    RSIPeriod          = 14;
input double BuyRSILevel        = 55.0;
input double SellRSILevel       = 45.0;

input int    ATRPeriod          = 14;
input double SL_ATR_Mult        = 1.5;
input double TrailSL_ATR_Mult   = 0.6;
input double MinATR             = 0.0001;

input int    MaxSpreadPoints    = 300;      // Spread filter (POINTS)
input int    Slippage           = 3;

// Multi-symbol scanning
input bool   ScanMarketWatch    = true;     // If true: scan all Market Watch symbols; else: only chart symbol
input int    SignalTimeframe    = PERIOD_M1;
input int    MaxSymbolsToScan   = 60;       // Safety cap

// Fallback order placement logic and logging:
input double MinimumFreeMarginPercent = 100; // Minimum % free margin left after new trade (vs balance)
input int    ErrorNotifyIntervalMinutes = 5; // Notify only every X minutes for repeated errors
input bool   AllowNoSLTPFallback  = true;    // If SL/TP cannot be made valid, allow fallback to trade without SL/TP and modify after

// Telegram
input bool   EnableTelegram     = true;
input string TELEGRAM_BOT_TOKEN = "8409309288:AAFX6cVp1RT-OJmUnBD1jN8VbKkFegNrxNM";
input string TELEGRAM_CHAT_ID   = "8181897048";
input int    TelegramTimeoutMs  = 5000;

//==================== GLOBALS =====================================
double emaFast, emaSlow, rsi, atr;
datetime lastInvalidSLWarn = 0;
datetime lastTelegramErrorWarn = 0;

// Multi-symbol state
string   scanSymbols[];
datetime lastBarTime[];
datetime lastNotifiedCloseTime[];

//+------------------------------------------------------------------+
//| Symbol type detection: returns recommended SL/TP buffer points   |
//+------------------------------------------------------------------+
int GetSymbolSLTPBufferPoints(string symb)
{
   if(StringFind(symb,"BTC")>=0 || StringFind(symb,"ETH")>=0 || StringFind(symb,"XRP")>=0 || StringFind(symb,"USDT")>=0 ||
      StringFind(symb,"DOGE")>=0 || StringFind(symb,"ADA")>=0 || StringFind(symb,"DOT")>=0 || StringFind(symb,"SOL")>=0 ||
      StringFind(symb,"LTC")>=0 || StringFind(symb,"BNB")>=0)
      return 0;

   if(StringFind(symb,"100")>=0 || StringFind(symb,"500")>=0 || StringFind(symb,"40")>=0 || StringFind(symb,"DE")>=0 ||
      StringFind(symb,"NAS")>=0)
      return 10;

   if(StringFind(symb,"USD")>=0 && (StringFind(symb,"JPY")>=0 || StringFind(symb,"EUR")>=0 || StringFind(symb,"GBP")>=0 ||
      StringFind(symb,"CHF")>=0 || StringFind(symb,"CAD")>=0 || StringFind(symb,"AUD")>=0 || StringFind(symb,"NZD")>=0))
      return 20;

   if(StringFind(symb,"XAU")>=0 || StringFind(symb,"XAG")>=0)
      return 10;

   return 5;
}

//+------------------------------------------------------------------+
//| URL Encode helper (UTF-8-ish safe for ASCII messages)            |
//+------------------------------------------------------------------+
string UrlEncode(const string text)
{
   string out="";
   for(int i=0;i<StringLen(text);i++)
   {
      int c=StringGetChar(text,i);
      bool safe = (c>='a' && c<='z') || (c>='A' && c<='Z') || (c>='0' && c<='9') || c=='-' || c=='_' || c=='.' || c=='~';
      if(safe)
         out += CharToStr(c);
      else if(c==' ')
         out += "+";
      else
         out += StringFormat("%%%02X",c);
   }
   return out;
}

//+------------------------------------------------------------------+
//| Telegram send (requires MT4 Options -> Expert Advisors URLs)     |
//+------------------------------------------------------------------+
bool TelegramSend(const string text)
{
   if(!EnableTelegram)
      return true;
   if(TELEGRAM_BOT_TOKEN=="" || TELEGRAM_CHAT_ID=="")
      return false;

   string url = "https://api.telegram.org/bot" + TELEGRAM_BOT_TOKEN + "/sendMessage";
   string body = "chat_id=" + UrlEncode(TELEGRAM_CHAT_ID) + "&text=" + UrlEncode(text);

   char data[];
   StringToCharArray(body, data, 0, WHOLE_ARRAY);

   char result[];
   string result_headers="";
   ResetLastError();

   int status = WebRequest(
      "POST",
      url,
      "Content-Type: application/x-www-form-urlencoded\r\n",
      TelegramTimeoutMs,
      data,
      result,
      result_headers
   );

   if(status == -1)
   {
      int err=GetLastError();
      if(TimeCurrent() - lastTelegramErrorWarn > 60 * ErrorNotifyIntervalMinutes)
      {
         lastTelegramErrorWarn = TimeCurrent();
         Print("Telegram WebRequest failed. Error=",err,
               " (Allow URL in MT4: https://api.telegram.org)");
      }
      return false;
   }

   return (status == 200);
}

//+------------------------------------------------------------------+
//| Symbol list & indexing                                           |
//+------------------------------------------------------------------+
int FindSymbolIndex(const string sym)
{
   for(int i=0;i<ArraySize(scanSymbols);i++)
      if(scanSymbols[i]==sym) return i;
   return -1;
}

void BuildSymbolList()
{
   if(!ScanMarketWatch)
   {
      ArrayResize(scanSymbols,1);
      scanSymbols[0]=Symbol();
      ArrayResize(lastBarTime,1);
      ArrayResize(lastNotifiedCloseTime,1);
      lastBarTime[0]=0;
      lastNotifiedCloseTime[0]=0;
      return;
   }

   int total = SymbolsTotal(true);
   if(total < 1) total = 1;
   int cap = MathMin(total, MaxSymbolsToScan);

   ArrayResize(scanSymbols,0);
   ArrayResize(lastBarTime,0);
   ArrayResize(lastNotifiedCloseTime,0);

   // Ensure chart symbol included
   string chartSym = Symbol();
   ArrayResize(scanSymbols,1);
   scanSymbols[0]=chartSym;
   ArrayResize(lastBarTime,1);
   ArrayResize(lastNotifiedCloseTime,1);
   lastBarTime[0]=0;
   lastNotifiedCloseTime[0]=0;

   for(int i=0;i<cap;i++)
   {
      string s = SymbolName(i,true);
      if(s=="" || s==chartSym) continue;
      int n = ArraySize(scanSymbols);
      ArrayResize(scanSymbols,n+1);
      ArrayResize(lastBarTime,n+1);
      ArrayResize(lastNotifiedCloseTime,n+1);
      scanSymbols[n]=s;
      lastBarTime[n]=0;
      lastNotifiedCloseTime[n]=0;
   }
}

bool IsNewBarForIndex(const int idx)
{
   if(idx<0 || idx>=ArraySize(scanSymbols)) return false;
   datetime t = iTime(scanSymbols[idx], SignalTimeframe, 0);
   if(t<=0) return false;
   if(t!=lastBarTime[idx])
   {
      lastBarTime[idx]=t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Robust SL/TP validator and safer getter                          |
//+------------------------------------------------------------------+
bool GetValidStops(string symb, int direction, double atr_value, double &SafeSL, double &SafeTP, double &SafePrice)
{
   double PointSize    = MarketInfo(symb, MODE_POINT);
   int    symbolDigits = (int)MarketInfo(symb, MODE_DIGITS);
   int    StopLevel    = (int)MarketInfo(symb, MODE_STOPLEVEL);
   double Spread       = MarketInfo(symb, MODE_SPREAD);

   int    ExtraSLTPBufferPoints = GetSymbolSLTPBufferPoints(symb);

   double minDistance  = (StopLevel + Spread + ExtraSLTPBufferPoints) * PointSize;
   double sl_dist      = MathMax(atr_value * SL_ATR_Mult, minDistance);
   double tp_dist      = sl_dist;

   double AskPrice = MarketInfo(symb, MODE_ASK);
   double BidPrice = MarketInfo(symb, MODE_BID);

   if(direction == OP_BUY)
   {
      SafePrice = AskPrice;
      SafeSL = NormalizeDouble(SafePrice - sl_dist, symbolDigits);
      SafeTP = NormalizeDouble(SafePrice + tp_dist, symbolDigits);
      if((SafePrice - SafeSL) < minDistance || (SafeTP - SafePrice) < minDistance)
         return false;
   }
   else if(direction == OP_SELL)
   {
      SafePrice = BidPrice;
      SafeSL = NormalizeDouble(SafePrice + sl_dist, symbolDigits);
      SafeTP = NormalizeDouble(SafePrice - tp_dist, symbolDigits);
      if((SafeSL - SafePrice) < minDistance || (SafePrice - SafeTP) < minDistance)
         return false;
   }
   else
      return false;

   return true;
}

//+------------------------------------------------------------------+
int OnInit()
{
   BuildSymbolList();
   Print("CryptoTrendRunner started. ScanMarketWatch=",(ScanMarketWatch?"true":"false")," Symbols=",ArraySize(scanSymbols));

   // Load persistent last-close notifier per symbol
   for(int i=0;i<ArraySize(scanSymbols);i++)
   {
      string key = "CTR_LastClose_" + IntegerToString(AccountNumber()) + "_" + scanSymbols[i] + "_" + IntegerToString(MagicNumber);
      if(GlobalVariableCheck(key))
         lastNotifiedCloseTime[i] = (datetime)GlobalVariableGet(key);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i=0;i<ArraySize(scanSymbols);i++)
   {
      string key = "CTR_LastClose_" + IntegerToString(AccountNumber()) + "_" + scanSymbols[i] + "_" + IntegerToString(MagicNumber);
      GlobalVariableSet(key, (double)lastNotifiedCloseTime[i]);
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   ManageTrailingSL();
   NotifyClosedTrades();

   if(!IsTradeAllowed()) return;

   for(int i=0;i<ArraySize(scanSymbols);i++)
   {
      string sym = scanSymbols[i];
      if(!IsNewBarForIndex(i))
         continue;

      // Limit trades
      if(LimitTradesPerSymbol)
      {
         if(CountOpenTrades(sym) >= MaxTrades) continue;
      }
      else
      {
         if(CountOpenTrades("*") >= MaxTrades) continue;
      }
      if(OneTradePerSymbol && CountOpenTrades(sym) > 0) continue;

      // Spread filter
      if(!SpreadOK(sym)) continue;

      // Indicators per symbol
      double eFast = iMA(sym, SignalTimeframe, EMAFast, 0, MODE_EMA, PRICE_CLOSE, 0);
      double eSlow = iMA(sym, SignalTimeframe, EMASlow, 0, MODE_EMA, PRICE_CLOSE, 0);
      double r     = iRSI(sym, SignalTimeframe, RSIPeriod, PRICE_CLOSE, 0);
      double a     = iATR(sym, SignalTimeframe, ATRPeriod, 0);

      if(a < MinATR) continue;

      bool buySig  = (eFast > eSlow) && (r >= BuyRSILevel)  && (iClose(sym,SignalTimeframe,1) > iOpen(sym,SignalTimeframe,1));
      bool sellSig = (eFast < eSlow) && (r <= SellRSILevel) && (iClose(sym,SignalTimeframe,1) < iOpen(sym,SignalTimeframe,1));

      if(buySig)  OpenTrade(sym, OP_BUY, a);
      if(sellSig) OpenTrade(sym, OP_SELL, a);
   }
}

//+------------------------------------------------------------------+
void UpdateIndicators()
{
   emaFast = iMA(Symbol(), 0, EMAFast, 0, MODE_EMA, PRICE_CLOSE, 0);
   emaSlow = iMA(Symbol(), 0, EMASlow, 0, MODE_EMA, PRICE_CLOSE, 0);
   rsi     = iRSI(Symbol(), 0, RSIPeriod, PRICE_CLOSE, 0);
   atr     = iATR(Symbol(), 0, ATRPeriod, 0);
}

//+------------------------------------------------------------------+
bool SpreadOK(const string sym)
{
   double spreadPoints = MarketInfo(sym, MODE_SPREAD);
   if(spreadPoints <= 0)
   {
      double ask = MarketInfo(sym, MODE_ASK);
      double bid = MarketInfo(sym, MODE_BID);
      double pt  = MarketInfo(sym, MODE_POINT);
      if(pt<=0) pt=Point;
      spreadPoints = (ask - bid) / pt;
   }

   return (spreadPoints <= MaxSpreadPoints);
}

//+------------------------------------------------------------------+
bool BuySignal()
{
   if(emaFast <= emaSlow) return false;
   if(rsi < BuyRSILevel) return false;
   if(Close[1] <= Open[1]) return false;
   return true;
}

//+------------------------------------------------------------------+
bool SellSignal()
{
   if(emaFast >= emaSlow) return false;
   if(rsi > SellRSILevel) return false;
   if(Close[1] >= Open[1]) return false;
   return true;
}

//+------------------------------------------------------------------+
double GetMinStopDistance(const string sym)
{
   int ExtraSLTPBufferPoints = GetSymbolSLTPBufferPoints(sym);
   double pt = MarketInfo(sym, MODE_POINT);
   if(pt<=0) pt=Point;
   return (MarketInfo(sym, MODE_STOPLEVEL) + MarketInfo(sym, MODE_SPREAD) + ExtraSLTPBufferPoints) * pt;
}

//+------------------------------------------------------------------+
double NormalizeLot(const string sym, const double lot)
{
   double lotMin  = MarketInfo(sym, MODE_MINLOT);
   double lotMax  = MarketInfo(sym, MODE_MAXLOT);
   double lotStep = MarketInfo(sym, MODE_LOTSTEP);

   if(lotStep <= 0) lotStep = 0.01;

   double clipped = MathMax(lotMin, MathMin(lot, lotMax));
   double steps = MathFloor(clipped / lotStep);
   double normalized = steps * lotStep;

   // 2 decimals is typical, but keep safe for exotic lot steps
   int digits = 2;
   if(lotStep < 0.01) digits = 3;
   if(lotStep < 0.001) digits = 4;

   return NormalizeDouble(normalized, digits);
}

//+------------------------------------------------------------------+
double CalculateLotSize(const string sym, const int orderType, const double atr_value)
{
   double balance   = AccountBalance();
   double riskMoney = balance * RiskPercent / 100.0;

   double tickValue = MarketInfo(sym, MODE_TICKVALUE);
   double pt = MarketInfo(sym, MODE_POINT);
   if(pt<=0) pt=Point;
   double stopDist  = atr_value * SL_ATR_Mult;

   if(tickValue <= 0 || stopDist <= 0) return 0;

   double lot = riskMoney / ((stopDist / pt) * tickValue);
   lot = NormalizeLot(sym, lot);

   double lotMin  = MarketInfo(sym, MODE_MINLOT);
   double lotStep = MarketInfo(sym, MODE_LOTSTEP);

   // Margin + free margin policy
   double wantedLot = lot;
   while(wantedLot >= lotMin)
   {
      double freeAfter = AccountFreeMarginCheck(sym, orderType, wantedLot);
      if(freeAfter > 0)
      {
         double freePct = 0;
         if(balance > 0)
            freePct = (freeAfter / balance) * 100.0;

         if(freePct >= MinimumFreeMarginPercent)
            break;
      }
      wantedLot -= lotStep;
      wantedLot = NormalizeLot(sym, wantedLot);
   }

   if(wantedLot < lotMin)
      return 0.0;

   return wantedLot;
}

//+------------------------------------------------------------------+
bool SendOrderWithRetry(const string sym, const int type,const double lot,const double sl,const double tp,int &ticketOut)
{
   ticketOut = -1;
   int tries = 3;

   for(int attempt=0; attempt<tries; attempt++)
   {
      double ask = MarketInfo(sym, MODE_ASK);
      double bid = MarketInfo(sym, MODE_BID);
      double p = (type==OP_BUY) ? ask : bid;

      int ticket = OrderSend(sym, type, lot, p, Slippage, sl, tp, "CryptoTrendRunner", MagicNumber, 0, clrDodgerBlue);
      if(ticket > 0)
      {
         ticketOut = ticket;
         return true;
      }

      int err = GetLastError();
      if(err == ERR_TRADE_CONTEXT_BUSY || err == ERR_TRADE_TIMEOUT || err == ERR_SERVER_BUSY || err == ERR_OFF_QUOTES)
      {
         Sleep(500);
         continue;
      }
      break;
   }

   return false;
}

//+------------------------------------------------------------------+
void OpenTrade(const string sym, int type, const double atr_value)
{
   double lotSize = CalculateLotSize(sym, type, atr_value);
   if(lotSize <= 0)
      return;

   double price=0, sl=0, tp=0;
   bool stopsOK = GetValidStops(sym, type, atr_value, sl, tp, price);

   int ticket = -1;

   if(stopsOK)
   {
      if(!SendOrderWithRetry(sym, type, lotSize, sl, tp, ticket))
         ticket = -1;
   }
   else if(AllowNoSLTPFallback)
   {
      double ask = MarketInfo(sym, MODE_ASK);
      double bid = MarketInfo(sym, MODE_BID);
      double p = (type==OP_BUY) ? ask : bid;
      ticket = OrderSend(sym, type, lotSize, p, Slippage, 0, 0, "CryptoTrendRunner", MagicNumber, 0, clrOrangeRed);
      Print("FALLBACK: Trade placed without SL/TP for symbol:",sym);

      if(ticket > 0)
      {
         Sleep(750);
         if(OrderSelect(ticket, SELECT_BY_TICKET))
         {
            double modSL, modTP, modPrice;
            if(GetValidStops(sym, type, atr_value, modSL, modTP, modPrice))
            {
               bool success = OrderModify(ticket, OrderOpenPrice(), modSL, modTP, 0, clrLimeGreen);
               if(!success)
                  Print("ERROR: SL/TP modify failed, ticket=",ticket," err=",GetLastError());
            }
         }
      }
   }
   else
   {
      if(TimeCurrent() - lastInvalidSLWarn > 60 * ErrorNotifyIntervalMinutes)
      {
         lastInvalidSLWarn = TimeCurrent();
         Print("No trade: SL/TP could not be made valid.");
      }
      return;
   }

   if(ticket < 0)
   {
      int err = GetLastError();
      Print("OrderSend failed: Error ", err, ", Symbol=",sym,", Type=",type,", lotSize=",lotSize,
            ", SL=",sl,", TP=",tp);
      return;
   }

   // Telegram open notification
   string side = (type==OP_BUY) ? "BUY" : "SELL";
   TelegramSend(side + " OPEN " + sym + " Lot: " + DoubleToString(lotSize, 2));
}

//+------------------------------------------------------------------+
void ManageTrailingSL()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
   if(OrderMagicNumber() != MagicNumber) continue;

   string sym = OrderSymbol();
   // only manage symbols in scan list
   if(FindSymbolIndex(sym) < 0) continue;

   int digits = (int)MarketInfo(sym, MODE_DIGITS);
   double pt  = MarketInfo(sym, MODE_POINT);
   if(pt<=0) pt=Point;

   double ask = MarketInfo(sym, MODE_ASK);
   double bid = MarketInfo(sym, MODE_BID);

   double atrNow  = iATR(sym, SignalTimeframe, ATRPeriod, 0);
   double minStop = GetMinStopDistance(sym);

      double newSL;
      bool modified;

      if(OrderType() == OP_BUY)
      {
         newSL = bid - atrNow * TrailSL_ATR_Mult;
         if((bid - newSL) < minStop)
            newSL = bid - minStop;

         // keep TP intact
         double tp = OrderTakeProfit();

         if(OrderStopLoss() == 0 || newSL > OrderStopLoss())
         {
            modified = OrderModify(OrderTicket(), OrderOpenPrice(), NormalizeDouble(newSL, digits), tp, 0);
            if(!modified && (TimeCurrent() - lastInvalidSLWarn > 60 * ErrorNotifyIntervalMinutes))
            {
               lastInvalidSLWarn = TimeCurrent();
               Print("Buy SL modify failed. Error=", GetLastError());
            }
         }
      }
      else if(OrderType() == OP_SELL)
      {
         newSL = ask + atrNow * TrailSL_ATR_Mult;
         if((newSL - ask) < minStop)
            newSL = ask + minStop;

         // keep TP intact
         double tp = OrderTakeProfit();

         if(OrderStopLoss() == 0 || newSL < OrderStopLoss())
         {
            modified = OrderModify(OrderTicket(), OrderOpenPrice(), NormalizeDouble(newSL, digits), tp, 0);
            if(!modified && (TimeCurrent() - lastInvalidSLWarn > 60 * ErrorNotifyIntervalMinutes))
            {
               lastInvalidSLWarn = TimeCurrent();
               Print("Sell SL modify failed. Error=", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
int CountOpenTrades(const string sym)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderMagicNumber() == MagicNumber)
         {
            if(sym=="*" || OrderSymbol()==sym)
               count++;
         }
   return count;
}

//+------------------------------------------------------------------+
void NotifyClosedTrades()
{
   // Scan recent history and notify on newly closed trades
   int total = OrdersHistoryTotal();
   if(total <= 0)
      return;

   // iterate newest-first and notify per symbol
   for(int i = total - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderMagicNumber() != MagicNumber)
         continue;

      string sym = OrderSymbol();
      int idx = FindSymbolIndex(sym);
      if(idx < 0) continue;

      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL)
         continue;

      datetime ct = OrderCloseTime();
      if(ct <= 0) continue;
      if(ct <= lastNotifiedCloseTime[idx])
         continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      string side = (type == OP_BUY) ? "BUY" : "SELL";

      TelegramSend(side + " CLOSED " + sym +
                   " Lot: " + DoubleToString(OrderLots(), 2) +
                   " P/L: " + DoubleToString(profit, 2));

      // update per symbol
      if(ct > lastNotifiedCloseTime[idx])
      {
         lastNotifiedCloseTime[idx] = ct;
         string key = "CTR_LastClose_" + IntegerToString(AccountNumber()) + "_" + sym + "_" + IntegerToString(MagicNumber);
         GlobalVariableSet(key, (double)lastNotifiedCloseTime[idx]);
      }
   }
}

//+------------------------------------------------------------------+
