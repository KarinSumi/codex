//+------------------------------------------------------------------+
//|                                  SuperTrend_2TF_MultiAsset_EA.mq5 |
//|                                  Multi-Asset SuperTrend Strategy |
//|                                      Version 2.10 (Compile Fix)   |
//+------------------------------------------------------------------+
#property copyright "SuperTrend 2-TF Strategy (Full Code)"
#property link      ""
#property version   "2.10" // Compilation Fixes & Robust Close Logic
#property strict

#include <Trade/Trade.mqh> // Include the Standard Trade Library

#define EA_VERSION "2.10"

//--- Input parameters
input group "=== Asset List ==="
input string InpSymbolList = "XAUUSDm";                // Symbol List (comma-separated)
input int    InpBaseMagicNumber = 100000;              // Base Magic Number

input group "=== Debug Settings ==="
input bool   InpDebugMode = true;                      // Enable Debug Logging
input bool   InpShowSTValues = true;                   // Show SuperTrend Values in Journal

input group "=== Phase 1: Signal Types ==="
input bool   InpUsePullbackSignal = true;              // Use Pullback Signal (Primary Signal)

input group "=== Trade Management: Breakeven ==="
input bool   InpUseBreakeven = true;                   // Enable Breakeven
input double InpBreakevenATRTrigger = 0.3;             // Breakeven Trigger (x M15 ATR)
input double InpBreakevenOffsetPips = 3.0;             // Breakeven Offset (Pips)

input group "=== Trade Management: Spread & News Filter ==="
input bool   InpUseSpreadFilter = true;                // Enable Spread Filter
input double InpMaxSpreadPips = 4.0;                   // Max Spread (Pips)
input bool   InpUseNewsFilter = false;                 // Enable News Filter (Default Off)
input int    InpNewsBufferMinutes = 30;                // Avoid trading X mins before/after news
input string InpNewsImportance = "HIGH";               // Importance to avoid (HIGH,MEDIUM,LOW)

input group "=== Risk Management ==="
input double InpRiskPerTrade = 1.0;                    // Risk Per Trade (%)
input double InpMaxAccountRisk = 3.0;                  // Max Total Account Risk (%)
input int    InpMaxPositionsPerAsset = 3;              // Max Positions Per Asset
input string InpLotInfo = "Min/Max Lot auto-calculated per $1000";  // Lot Size Info

input group "=== SuperTrend Settings - Symbol 1 ==="
input int    InpATRPeriod_1 = 10;                      // ATR Period
input double InpSTMultiplier_1 = 3.0;                  // SuperTrend Multiplier
input ENUM_TIMEFRAMES InpHigherTF_1 = PERIOD_H1;       // Higher TF (Flag)
input ENUM_TIMEFRAMES InpLowerTF_1 = PERIOD_M15;       // Lower TF (Entry)

input group "=== SuperTrend Settings - Symbol 2 ==="
input int    InpATRPeriod_2 = 10;                      // ATR Period
input double InpSTMultiplier_2 = 3.0;                  // SuperTrend Multiplier
input ENUM_TIMEFRAMES InpHigherTF_2 = PERIOD_H1;       // Higher TF (Flag)
input ENUM_TIMEFRAMES InpLowerTF_2 = PERIOD_M15;       // Lower TF (Entry)

input group "=== SuperTrend Settings - Symbol 3 ==="
input int    InpATRPeriod_3 = 10;                      // ATR Period
input double InpSTMultiplier_3 = 3.0;                  // SuperTrend Multiplier
input ENUM_TIMEFRAMES InpHigherTF_3 = PERIOD_H1;       // Higher TF (Flag)
input ENUM_TIMEFRAMES InpLowerTF_3 = PERIOD_M15;       // Lower TF (Entry)

input group "=== Trade Settings (New Trailing Logic) ==="
input double InpInitialRiskRewardRatio = 2.0;          // Initial Risk:Reward Ratio

input group "=== Display Settings ==="
input bool   InpShowDashboard = true;                  // Show Dashboard
input int    InpDashboardFontSize = 8;                 // Dashboard Font Size
input bool   InpShowVisualIndicator = true;            // Show Visual Indicator on Chart
input int    InpVisualBarsBack = 500;                  // Visual History (bars)

//--- Global variables
struct AssetConfig
{
   string   symbol;
   int      magicNumber;
   int      atrPeriod;
   double   stMultiplier;
   ENUM_TIMEFRAMES higherTF;
   ENUM_TIMEFRAMES lowerTF;
   int      flagDirection;      // 0=none, 1=bullish, -1=bearish
   datetime lastFlagTime;
   datetime lastCheckTime;
   datetime lastHigherTFCheck;  // Track higher TF separately
   int      lastHigherTFDir;    // Previous higher TF direction
};

struct PositionInfo
{
   ulong    ticket;
   string   symbol;
   int      type;              // 0=buy, 1=sell
   double   entryPrice;
   double   stopLoss;
   double   takeProfit;
   double   slDistance;         // The initial risk distance
   bool     breakevenActivated;
   int      trailingStage;     // 0=initial, 1=BE, 2=1R, 3=1.8R, etc.
   datetime openTime;
};

AssetConfig g_assets[];
PositionInfo g_positions[];
string g_dashboardName = "ST2TF_Dashboard";
CTrade trade; // Global Trade object

// News Filter Globals
bool g_isNewsPeriod = false;
string g_newsReason = "";
datetime g_newsBlockUntil = 0;
datetime g_nextNewsCheckTime = 0;

// Visual Indicator Globals
datetime g_lastVisualUpdate = 0;
string g_objectPrefix = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== SuperTrend 2-TF Multi-Asset EA Starting (v2.10) ===");
   g_objectPrefix = "ST2TF_" + _Symbol + "_" + IntegerToString(GetTickCount());
   CleanupVisualObjects();
   if(!ParseAndValidateSymbols()) return(INIT_FAILED);
   LoadExistingPositions();
   if(InpShowDashboard) CreateDashboard();
   Print("=== EA Initialized Successfully ===");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, g_dashboardName);
   CleanupVisualObjects();
   ChartRedraw();
   Print("=== EA Stopped. Reason: ", reason, " ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   for(int i = 0; i < ArraySize(g_assets); i++)
   {
      CheckAssetSignals(g_assets[i]);
      ManageAssetPositions(g_assets[i]);
   }
   if(InpShowVisualIndicator) UpdateVisualIndicator();
   if(InpShowDashboard) UpdateDashboard();
}

// --- CORE LOGIC FUNCTIONS ---

//+------------------------------------------------------------------+
//| Check signals for an asset                                       |
//+------------------------------------------------------------------+
void CheckAssetSignals(AssetConfig &asset)
{
   datetime currentBarTime = iTime(asset.symbol, asset.lowerTF, 1);
   if(currentBarTime == asset.lastCheckTime) return;
   asset.lastCheckTime = currentBarTime;

   if(InpDebugMode)
      Print("=== ", asset.symbol, " | Checking signals at ", TimeToString(currentBarTime), " ===");

   double stHigher[], stLower[];
   int dirHigher[], dirLower[];
   CalculateSuperTrend(asset.symbol, asset.higherTF, asset.atrPeriod, asset.stMultiplier, 20, stHigher, dirHigher);
   CalculateSuperTrend(asset.symbol, asset.lowerTF, asset.atrPeriod, asset.stMultiplier, 20, stLower, dirLower);

   if(ArraySize(dirHigher) < 3 || ArraySize(dirLower) < 3) return;

   datetime higherTFBarTime = iTime(asset.symbol, asset.higherTF, 1);
   if(higherTFBarTime != asset.lastHigherTFCheck)
   {
      asset.lastHigherTFCheck = higherTFBarTime;
      bool higherFlipBullish = (dirHigher[1] == 1 && asset.lastHigherTFDir == -1);
      bool higherFlipBearish = (dirHigher[1] == -1 && asset.lastHigherTFDir == 1);
      if(higherFlipBullish) { asset.flagDirection = 1; Print("🚩 ", asset.symbol, " | H-TF BULLISH FLAG SET"); }
      if(higherFlipBearish) { asset.flagDirection = -1; Print("🚩 ", asset.symbol, " | H-TF BEARISH FLAG SET"); }
      asset.lastHigherTFDir = dirHigher[1];
   }

   bool pullbackBuy = InpUsePullbackSignal && asset.flagDirection == 1 && dirLower[1] == 1 && dirLower[2] == -1;
   bool pullbackSell = InpUsePullbackSignal && asset.flagDirection == -1 && dirLower[1] == -1 && dirLower[2] == 1;

   if(pullbackBuy || pullbackSell)
   {
      if(!IsSpreadOK(asset.symbol) || IsNewsPeriod())
      {
         Print(asset.symbol, " | Signal ignored due to filter (Spread or News)");
         return;
      }
   }

   if(pullbackBuy)
   {
      Print("🟢 ", asset.symbol, " | PULLBACK BUY SIGNAL DETECTED!");
      if(CanOpenNewPosition(asset))
      {
         OpenPosition(asset, ORDER_TYPE_BUY, "PULLBACK");
         asset.flagDirection = 0;
      }
   }
   if(pullbackSell)
   {
      Print("🔴 ", asset.symbol, " | PULLBACK SELL SIGNAL DETECTED!");
      if(CanOpenNewPosition(asset))
      {
         OpenPosition(asset, ORDER_TYPE_SELL, "PULLBACK");
         asset.flagDirection = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Open position with Swing Low/High SL placement                   |
//+------------------------------------------------------------------+
void OpenPosition(AssetConfig &asset, ENUM_ORDER_TYPE orderType, string signalType)
{
    double entryPrice = SymbolInfoDouble(asset.symbol, (orderType == ORDER_TYPE_BUY) ? SYMBOL_ASK : SYMBOL_BID);

    double sl = 0;
    int barsToScan = 200;
    int stDirs[];
    double stValues[];

    CalculateSuperTrend(asset.symbol, asset.lowerTF, asset.atrPeriod, asset.stMultiplier, barsToScan, stValues, stDirs);

    if(orderType == ORDER_TYPE_BUY)
    {
        double lowData[];
        CopyLow(asset.symbol, asset.lowerTF, 1, barsToScan - 1, lowData);
        double lowestLow = entryPrice;
        for(int i = 0; i < ArraySize(lowData) && i < ArraySize(stDirs) - 1; i++)
        {
            if(stDirs[i + 1] == -1)
            {
                if(lowData[i] < lowestLow) lowestLow = lowData[i];
            }
            else break;
        }
        sl = lowestLow;
    }
    else
    {
        double highData[];
        CopyHigh(asset.symbol, asset.lowerTF, 1, barsToScan - 1, highData);
        double highestHigh = 0;
        for(int i = 0; i < ArraySize(highData) && i < ArraySize(stDirs) - 1; i++)
        {
            if(stDirs[i + 1] == 1)
            {
                if(highData[i] > highestHigh) highestHigh = highData[i];
            }
            else break;
        }
        sl = highestHigh;
    }

    if(sl == 0 || sl == entryPrice)
    {
       Print("ERROR: Could not determine valid Swing SL for ", asset.symbol, ". Aborting trade.");
       return;
    }

    double slDistance = (orderType == ORDER_TYPE_BUY) ? entryPrice - sl : sl - entryPrice;
    if(slDistance <= SymbolInfoDouble(asset.symbol, SYMBOL_POINT) * 2)
    {
       Print("ERROR: Calculated SL is too close to entry price for ", asset.symbol, ". Aborting trade.");
       return;
    }

    double tp = (orderType == ORDER_TYPE_BUY) ? entryPrice + (slDistance * InpInitialRiskRewardRatio) : entryPrice - (slDistance * InpInitialRiskRewardRatio);

    double lotSize = CalculateLotSize(asset.symbol, slDistance, InpRiskPerTrade);
    if(lotSize <= 0) return;

    trade.SetExpertMagicNumber(asset.magicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFillingBySymbol(asset.symbol);

    if(!trade.PositionOpen(asset.symbol, orderType, lotSize, entryPrice, sl, tp, "ST2TF_" + signalType))
    {
       Print("ERROR: OrderSend failed for ", asset.symbol, " | Code: ", trade.ResultRetcode(), ", ", trade.ResultComment());
       return;
    }

    ulong ticket = trade.ResultOrder();
    Print("SUCCESS: ", signalType, " ", EnumToString(orderType), " opened for ", asset.symbol);
    Print("         Ticket: ", ticket, " | Entry: ", entryPrice, " | SL: ", sl, " | TP: ", tp, " | Lot: ", lotSize);

    int idx = ArraySize(g_positions);
    ArrayResize(g_positions, idx + 1);
    g_positions[idx].ticket = ticket;
    g_positions[idx].symbol = asset.symbol;
    g_positions[idx].type = (orderType == ORDER_TYPE_BUY) ? 0 : 1;
    g_positions[idx].entryPrice = entryPrice;
    g_positions[idx].stopLoss = sl;
    g_positions[idx].takeProfit = tp;
    g_positions[idx].slDistance = slDistance;
    g_positions[idx].breakevenActivated = false;
    g_positions[idx].trailingStage = 0;
    g_positions[idx].openTime = TimeCurrent();
}


//+------------------------------------------------------------------+
//| Manage positions with robust close logic                         |
//+------------------------------------------------------------------+
void ManageAssetPositions(AssetConfig &asset)
{
   static datetime lastManageTime = 0;
   if(TimeCurrent() - lastManageTime < 5) return;
   lastManageTime = TimeCurrent();

   double stLower[], stHigher[];
   int dirLower[], dirHigher[];
   CalculateSuperTrend(asset.symbol, asset.lowerTF, asset.atrPeriod, asset.stMultiplier, 10, stLower, dirLower);
   CalculateSuperTrend(asset.symbol, asset.higherTF, asset.atrPeriod, asset.stMultiplier, 2, stHigher, dirHigher);
   if(ArraySize(stLower) == 0 || ArraySize(dirHigher) == 0) return;

   for(int i = ArraySize(g_positions) - 1; i >= 0; i--)
   {
      if(g_positions[i].symbol != asset.symbol) continue;

      if(!PositionSelectByTicket(g_positions[i].ticket))
      {
         Print("Position ", g_positions[i].ticket, " closed. Removing from management.");
         ArrayRemove(g_positions, i, 1);
         continue;
      }

      //--- RULE 1: MASTER H1 EXIT ---
      bool closeForH1Flip = (g_positions[i].type == 0 && dirHigher[0] == -1) ||
                            (g_positions[i].type == 1 && dirHigher[0] == 1);
      if(closeForH1Flip)
      {
         Print("MASTER EXIT: H1 SuperTrend flipped against position ", g_positions[i].ticket, ". Closing now.");
         if(!trade.PositionClose(g_positions[i].ticket))
         {
            Print("ERROR closing position ", g_positions[i].ticket, ": ", trade.ResultRetcode(), " - ", trade.ResultComment());
         }
         continue;
      }

      //--- Prepare data for trailing logic ---
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double profit = PositionGetDouble(POSITION_PROFIT);
      double profitRatio = (g_positions[i].slDistance > 0) ? profit / g_positions[i].slDistance : 0.0;

      double point = SymbolInfoDouble(asset.symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(asset.symbol, SYMBOL_DIGITS);
      double pipValue = (digits == 3 || digits == 5) ? point * 10 : point;

      double newSL = g_positions[i].stopLoss;
      double newTP = g_positions[i].takeProfit;
      bool needsModification = false;

      //--- RULE 2: ADVANCED TRAILING SL & TP ---
      if(InpUseBreakeven && !g_positions[i].breakevenActivated)
      {
         double atrM15[];
         int atrHandle = iATR(asset.symbol, asset.lowerTF, asset.atrPeriod);
         if(CopyBuffer(atrHandle, 0, 1, 1, atrM15) > 0 && atrM15[0] > 0)
         {
            if(profit > (InpBreakevenATRTrigger * atrM15[0]))
            {
               double beLevel = (g_positions[i].type == 0) ?
                                g_positions[i].entryPrice + (InpBreakevenOffsetPips * pipValue) :
                                g_positions[i].entryPrice - (InpBreakevenOffsetPips * pipValue);

               if((g_positions[i].type == 0 && beLevel > newSL) || (g_positions[i].type == 1 && beLevel < newSL))
               {
                   newSL = beLevel;
                   needsModification = true;
                   g_positions[i].breakevenActivated = true;
                   Print("🛡️ BE by ATR for Ticket ", g_positions[i].ticket, ". SL moved to ", DoubleToString(newSL, digits));
               }
            }
         }
         IndicatorRelease(atrHandle);
      }

      if (profitRatio >= 1.0)
      {
          int stage = (int)floor(profitRatio - 0.8) + 2;
          if (stage < 2) stage = 2;

          if (stage > g_positions[i].trailingStage)
          {
              double slMultiplier = stage - 2;
              double tpMultiplier = stage;

              if (stage == 2)
              {
                  double beLevel = (g_positions[i].type == 0) ?
                          g_positions[i].entryPrice + (InpBreakevenOffsetPips * pipValue) :
                          g_positions[i].entryPrice - (InpBreakevenOffsetPips * pipValue);
                  if((g_positions[i].type == 0 && beLevel > newSL) || (g_positions[i].type == 1 && beLevel < newSL)) newSL = beLevel;
              }
              else
              {
                  double tempSL = (g_positions[i].type == 0) ?
                          g_positions[i].entryPrice + (slMultiplier * g_positions[i].slDistance) :
                          g_positions[i].entryPrice - (slMultiplier * g_positions[i].slDistance);
                  if((g_positions[i].type == 0 && tempSL > newSL) || (g_positions[i].type == 1 && tempSL < newSL)) newSL = tempSL;
              }

              newTP = (g_positions[i].type == 0) ?
                      g_positions[i].entryPrice + (tpMultiplier * g_positions[i].slDistance) :
                      g_positions[i].entryPrice - (tpMultiplier * g_positions[i].slDistance);

              needsModification = true;
              g_positions[i].trailingStage = stage;
              Print("🚀 Profit Stage ", stage, " reached for Ticket ", g_positions[i].ticket);
          }
      }

      //--- RULE 3: M15 SUPER TREND TRAILING ---
      double st_sl = stLower[0];
      if((g_positions[i].type == 0 && st_sl > newSL) || (g_positions[i].type == 1 && st_sl < newSL))
      {
         newSL = st_sl;
         needsModification = true;
         if(InpDebugMode) Print("🛤️ ST Trail is tighter for Ticket ", g_positions[i].ticket);
      }

      //--- EXECUTE MODIFICATION ---
      if(needsModification)
      {
         newSL = NormalizeDouble(newSL, digits);
         newTP = NormalizeDouble(newTP, digits);

         if(newSL != g_positions[i].stopLoss || newTP != g_positions[i].takeProfit)
         {
            if(trade.PositionModify(g_positions[i].ticket, newSL, newTP))
            {
               Print("MODIFY Ticket ", g_positions[i].ticket, ": SL -> ", DoubleToString(newSL, digits), ", TP -> ", DoubleToString(newTP, digits));
               g_positions[i].stopLoss = newSL;
               g_positions[i].takeProfit = newTP;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate SuperTrend for Trading Logic                           |
//+------------------------------------------------------------------+
void CalculateSuperTrend(string symbol, ENUM_TIMEFRAMES tf, int atrPeriod,
                        double multiplier, int bars, double &st[], int &dir[])
{
   if(bars <= 0) return;
   ArrayResize(st, bars);
   ArrayResize(dir, bars);

   double atr[], high[], low[], close[];
   ArraySetAsSeries(atr, true); ArraySetAsSeries(high, true); ArraySetAsSeries(low, true); ArraySetAsSeries(close, true);

   int atr_handle = iATR(symbol, tf, atrPeriod);
   if(CopyBuffer(atr_handle, 0, 0, bars, atr) < bars || CopyHigh(symbol, tf, 0, bars, high) < bars ||
      CopyLow(symbol, tf, 0, bars, low) < bars || CopyClose(symbol, tf, 0, bars, close) < bars)
   {
      IndicatorRelease(atr_handle); return;
   }
   IndicatorRelease(atr_handle);

   for(int i = bars - 1; i >= 0; i--)
   {
      double hl2 = (high[i] + low[i]) / 2.0;
      double upperBand = hl2 + (multiplier * atr[i]);
      double lowerBand = hl2 - (multiplier * atr[i]);

      if(i == bars - 1) { st[i] = lowerBand; dir[i] = 1; }
      else
      {
         double prevST = st[i + 1]; int prevDir = dir[i + 1];
         if(prevDir == 1)
         {
            st[i] = (lowerBand > prevST) ? lowerBand : prevST;
            dir[i] = (close[i] < st[i]) ? -1 : 1;
         }
         else
         {
            st[i] = (upperBand < prevST) ? upperBand : prevST;
            dir[i] = (close[i] > st[i]) ? 1 : -1;
         }
      }
   }
}


// --- UTILITY, HELPER, and VISUAL FUNCTIONS ---

//+------------------------------------------------------------------+
//| Can open new position                                            |
//+------------------------------------------------------------------+
bool CanOpenNewPosition(AssetConfig &asset)
{
   if(CountAssetPositions(asset.symbol) >= InpMaxPositionsPerAsset)
   {
      Print(asset.symbol, " | Max positions (", InpMaxPositionsPerAsset, ") reached.");
      return false;
   }
   if(CalculateTotalAccountRisk() + InpRiskPerTrade > InpMaxAccountRisk)
   {
      Print(asset.symbol, " | Max account risk exceeded.");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Count positions for specific asset                               |
//+------------------------------------------------------------------+
int CountAssetPositions(string symbol)
{
   int count = 0;
   for(int i = 0; i < ArraySize(g_positions); i++)
   {
      if(g_positions[i].symbol == symbol) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Calculate total account risk                                     |
//+------------------------------------------------------------------+
double CalculateTotalAccountRisk()
{
   return ArraySize(g_positions) * InpRiskPerTrade;
}


//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double slDistance, double riskPercent)
{
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = accountEquity * (riskPercent / 100.0);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double brokerMinLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double brokerMaxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(slDistance <= 0 || tickValue <= 0 || tickSize <= 0) return 0.0;

   double riskPerLot = (slDistance / tickSize) * tickValue;
   if (riskPerLot <= 0) return 0.0;

   double lots = riskAmount / riskPerLot;
   lots = MathFloor(lots / lotStep) * lotStep;

   lots = MathMax(brokerMinLot, lots);
   lots = MathMin(brokerMaxLot, lots);

   return NormalizeDouble(lots, 2);
}


//+------------------------------------------------------------------+
//| Load existing positions (recovery mode)                          |
//+------------------------------------------------------------------+
void LoadExistingPositions()
{
   ArrayResize(g_positions, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      bool belongsToEA = false;
      for(int j = 0; j < ArraySize(g_assets); j++)
      {
         if(magic == g_assets[j].magicNumber) { belongsToEA = true; break; }
      }
      if(!belongsToEA) continue;

      int idx = ArraySize(g_positions);
      ArrayResize(g_positions, idx + 1);
      g_positions[idx].ticket = ticket;
      g_positions[idx].symbol = PositionGetString(POSITION_SYMBOL);
      g_positions[idx].type = (int)PositionGetInteger(POSITION_TYPE);
      g_positions[idx].entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      g_positions[idx].stopLoss = PositionGetDouble(POSITION_SL);
      g_positions[idx].takeProfit = PositionGetDouble(POSITION_TP);
      if(g_positions[idx].type == POSITION_TYPE_BUY)
         g_positions[idx].slDistance = g_positions[idx].entryPrice - g_positions[idx].stopLoss;
      else
         g_positions[idx].slDistance = g_positions[idx].stopLoss - g_positions[idx].entryPrice;

      g_positions[idx].breakevenActivated = (g_positions[idx].type == 0 && g_positions[idx].stopLoss > g_positions[idx].entryPrice) ||
                                            (g_positions[idx].type == 1 && g_positions[idx].stopLoss < g_positions[idx].entryPrice);
      g_positions[idx].trailingStage = 0;

      Print("Recovered position: ", g_positions[idx].symbol, " | Ticket: ", ticket);
   }
}

//+------------------------------------------------------------------+
//| Draw SuperTrend lines for Visuals                                |
//+------------------------------------------------------------------+
void DrawSuperTrendLines(AssetConfig &asset)
{
   int barsToDraw = MathMin(InpVisualBarsBack, (int)Bars(_Symbol, asset.lowerTF));
   if(barsToDraw <= 1) return;

   double stH1[], stM15[];
   int dirH1[], dirM15[];
   datetime timeM15[];

   CalculateSuperTrend(asset.symbol, asset.higherTF, asset.atrPeriod, asset.stMultiplier, barsToDraw + 200, stH1, dirH1);
   CalculateSuperTrend(asset.symbol, asset.lowerTF, asset.atrPeriod, asset.stMultiplier, barsToDraw + 2, stM15, dirM15);

   if(ArraySize(stH1) < 1 || ArraySize(stM15) < barsToDraw) return;

   ArrayResize(timeM15, barsToDraw);
   CopyTime(asset.symbol, asset.lowerTF, 0, barsToDraw, timeM15);
   ArraySetAsSeries(timeM15, true);

   for(int i = barsToDraw - 2; i >= 0; i--)
   {
      int shiftH1 = iBarShift(asset.symbol, asset.higherTF, timeM15[i], true);
      int shiftH1_prev = iBarShift(asset.symbol, asset.higherTF, timeM15[i + 1], true);
      if(shiftH1 < 0 || shiftH1_prev < 0) continue;

      string objNameH1 = g_objectPrefix + "H1_" + IntegerToString(i);
      ObjectCreate(0, objNameH1, OBJ_TREND, 0, timeM15[i + 1], stH1[shiftH1_prev], timeM15[i], stH1[shiftH1]);
      ObjectSetInteger(0, objNameH1, OBJPROP_COLOR, (dirH1[shiftH1] == 1) ? clrLime : clrRed);
      ObjectSetInteger(0, objNameH1, OBJPROP_WIDTH, 3);
      ObjectSetInteger(0, objNameH1, OBJPROP_BACK, true);

      string objNameM15 = g_objectPrefix + "M15_" + IntegerToString(i);
      ObjectCreate(0, objNameM15, OBJ_TREND, 0, timeM15[i + 1], stM15[i + 1], timeM15[i], stM15[i]);
      ObjectSetInteger(0, objNameM15, OBJPROP_COLOR, (dirM15[i] == 1) ? clrDodgerBlue : clrOrange);
      ObjectSetInteger(0, objNameM15, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, objNameM15, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, objNameM15, OBJPROP_BACK, true);

      if(dirH1[shiftH1] != dirH1[shiftH1_prev])
      {
         string flagName = g_objectPrefix + "Flag_" + IntegerToString(i);
         ObjectCreate(0, flagName, OBJ_ARROW, 0, timeM15[i], (dirH1[shiftH1] == 1) ? iLow(_Symbol, asset.lowerTF, i) : iHigh(_Symbol, asset.lowerTF, i));
         ObjectSetInteger(0, flagName, OBJPROP_ARROWCODE, (dirH1[shiftH1] == 1) ? 217 : 218);
         ObjectSetInteger(0, flagName, OBJPROP_COLOR, clrGold);
         ObjectSetInteger(0, flagName, OBJPROP_WIDTH, 2);
      }
   }
}

//+------------------------------------------------------------------+
//| Update visual indicator on chart                                 |
//+------------------------------------------------------------------+
void UpdateVisualIndicator()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBarTime == g_lastVisualUpdate) return;
   g_lastVisualUpdate = currentBarTime;

   int assetIdx = -1;
   for(int i = 0; i < ArraySize(g_assets); i++)
   {
      if(g_assets[i].symbol == _Symbol) { assetIdx = i; break; }
   }
   if(assetIdx < 0) return;

   CleanupVisualObjects();
   DrawSuperTrendLines(g_assets[assetIdx]);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Create/Update dashboard                                          |
//+------------------------------------------------------------------+
void CreateDashboard() {}

void UpdateDashboard()
{
   static datetime lastDashboardUpdate = 0;
   if(TimeCurrent() - lastDashboardUpdate < 2) return;
   lastDashboardUpdate = TimeCurrent();

   string text = StringFormat("=== SuperTrend 2-TF [v%s] ===\n", EA_VERSION);
   text += StringFormat("Equity: %.2f | Balance: %.2f\n", AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoDouble(ACCOUNT_BALANCE));
   text += StringFormat("Total Risk: %.1f%% / %.1f%%\n\n", CalculateTotalAccountRisk(), InpMaxAccountRisk);

   for(int i = 0; i < ArraySize(g_assets); i++)
   {
      string symbol = g_assets[i].symbol;
      text += "--- " + symbol + " ---\n";
      string flagText = "Flag: ";
      if(g_assets[i].flagDirection == 1) flagText += "LONG";
      else if(g_assets[i].flagDirection == -1) flagText += "SHORT";
      else flagText += "None";
      text += flagText + "\n";
      text += StringFormat("Positions: %d / %d\n", CountAssetPositions(symbol), InpMaxPositionsPerAsset);

      for(int j = 0; j < ArraySize(g_positions); j++)
      {
         if(g_positions[j].symbol != symbol) continue;
         string posType = (g_positions[j].type == 0) ? "BUY" : "SELL";
         string beStatus = g_positions[j].breakevenActivated ? "[BE]" : "";
         string trailStatus = (g_positions[j].trailingStage > 1) ? StringFormat("[S%d]", g_positions[j].trailingStage) : "";
         double profit = 0.0;
         if(PositionSelectByTicket(g_positions[j].ticket)) profit = PositionGetDouble(POSITION_PROFIT);
         text += StringFormat("  %s %.2f %s%s | P/L: %.2f\n", posType, g_positions[j].entryPrice, beStatus, trailStatus, profit);
      }
   }

   ObjectCreate(0, g_dashboardName, OBJ_LABEL, 0, 10, 20);
   ObjectSetInteger(0, g_dashboardName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, g_dashboardName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, g_dashboardName, OBJPROP_FONTSIZE, InpDashboardFontSize);
   ObjectSetString(0, g_dashboardName, OBJPROP_FONT, "Courier New");
   ObjectSetInteger(0, g_dashboardName, OBJPROP_COLOR, clrWhite);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Clean up visual objects created by EA                            |
//+------------------------------------------------------------------+
void CleanupVisualObjects() { ObjectsDeleteAll(0, g_objectPrefix); }

//+------------------------------------------------------------------+
//| Parse and validate symbol list                                   |
//+------------------------------------------------------------------+
bool ParseAndValidateSymbols()
{
   string symbols[];
   int count = StringSplit(InpSymbolList, ',', symbols);

   if(count == 0)
   {
      Print("ERROR: No symbols provided in symbol list!");
      return false;
   }

   if(count > 3)
   {
      Print("WARNING: More than 3 symbols provided. Only first 3 will be used.");
      count = 3;
   }

   ArrayResize(g_assets, count);

   for(int i = 0; i < count; i++)
   {
      StringTrimLeft(symbols[i]);
      StringTrimRight(symbols[i]);

      if(!SymbolSelect(symbols[i], true))
      {
         Print("ERROR: Symbol '", symbols[i], "' not found!");
         Print("       Please add it to Market Watch.");
         Print("       Similar symbols: ", FindSimilarSymbols(symbols[i]));
         return false;
      }

      if(SymbolInfoInteger(symbols[i], SYMBOL_SELECT) == false)
      {
         Print("ERROR: Symbol '", symbols[i], "' has no data!");
         Print("       Fix: Right-click symbol in Market Watch -> Chart Window");
         return false;
      }

      g_assets[i].symbol = symbols[i];
      g_assets[i].magicNumber = InpBaseMagicNumber + i + 1;
      g_assets[i].flagDirection = 0;
      g_assets[i].lastFlagTime = 0;
      g_assets[i].lastCheckTime = 0;
      g_assets[i].lastHigherTFCheck = 0;
      g_assets[i].lastHigherTFDir = 0;

      switch(i)
      {
         case 0:
            g_assets[i].atrPeriod = InpATRPeriod_1;
            g_assets[i].stMultiplier = InpSTMultiplier_1;
            g_assets[i].higherTF = InpHigherTF_1;
            g_assets[i].lowerTF = InpLowerTF_1;
            break;
         case 1:
            g_assets[i].atrPeriod = InpATRPeriod_2;
            g_assets[i].stMultiplier = InpSTMultiplier_2;
            g_assets[i].higherTF = InpHigherTF_2;
            g_assets[i].lowerTF = InpLowerTF_2;
            break;
         case 2:
            g_assets[i].atrPeriod = InpATRPeriod_3;
            g_assets[i].stMultiplier = InpSTMultiplier_3;
            g_assets[i].higherTF = InpHigherTF_3;
            g_assets[i].lowerTF = InpLowerTF_3;
            break;
      }

      Print("Symbol ", i + 1, ": ", symbols[i], " | Magic: ", g_assets[i].magicNumber,
            " | ATR: ", g_assets[i].atrPeriod, " | Mult: ", g_assets[i].stMultiplier,
            " | TF: ", EnumToString(g_assets[i].higherTF), "/", EnumToString(g_assets[i].lowerTF));
   }

   return true;
}

//+------------------------------------------------------------------+
//| Find similar symbols in Market Watch                             |
//+------------------------------------------------------------------+
string FindSimilarSymbols(string searchSymbol)
{
   string result = "";
   int total = SymbolsTotal(true);
   int found = 0;

   StringToUpper(searchSymbol);

   for(int i = 0; i < total && found < 3; i++)
   {
      string sym = SymbolName(i, true);
      string symUpper = sym;
      StringToUpper(symUpper);

      if(StringFind(symUpper, searchSymbol) >= 0 || StringFind(searchSymbol, symUpper) >= 0)
      {
         if(result != "") result += ", ";
         result += sym;
         found++;
      }
   }

   return (result == "") ? "None found" : result;
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                    |
//+------------------------------------------------------------------+
bool IsSpreadOK(string symbol)
{
   if(!InpUseSpreadFilter) return true;

   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   double spreadPoints = (ask - bid) / point;
   double spreadPips = spreadPoints;
   if(digits == 5 || digits == 3) spreadPips /= 10.0;

   if(spreadPips > InpMaxSpreadPips)
   {
      if(InpDebugMode)
         Print(symbol, " | Spread too wide: ", DoubleToString(spreadPips, 1),
               " pips (Max: ", DoubleToString(InpMaxSpreadPips, 1), ")");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check if we should avoid trading due to news                     |
//+------------------------------------------------------------------+
bool IsNewsPeriod()
{
    if (!InpUseNewsFilter)
        return false;

    datetime currentTime = TimeCurrent();

    if (currentTime < g_newsBlockUntil)
    {
        if (InpDebugMode && currentTime > g_nextNewsCheckTime)
        {
            Print("📰 News Period Active: ", g_newsReason);
            Print("   Blocked until: ", TimeToString(g_newsBlockUntil));
            g_nextNewsCheckTime = currentTime + 300;
        }
        return true;
    }

    static datetime lastCheckTime = 0;
    if (currentTime - lastCheckTime < 60)
    {
        return g_isNewsPeriod;
    }
    lastCheckTime = currentTime;

    datetime startTime = currentTime - (InpNewsBufferMinutes * 60);
    datetime endTime = currentTime + (InpNewsBufferMinutes * 60);

    MqlCalendarValue values[];
    if (CalendarValueHistory(values, startTime, endTime) <= 0)
    {
        g_isNewsPeriod = false;
        return false;
    }

    string importanceLevels[];
    StringSplit(InpNewsImportance, ',', importanceLevels);

    for (int i = 0; i < ArraySize(values); i++)
    {
        MqlCalendarEvent event;
        if (!CalendarEventById(values[i].event_id, event)) continue;

        string eventImportance = GetImportanceString(event.importance);
        bool importanceMatch = false;
        for (int j = 0; j < ArraySize(importanceLevels); j++)
        {
            string checkLevel = importanceLevels[j];
            StringTrimLeft(checkLevel);
            StringTrimRight(checkLevel);
            if (eventImportance == checkLevel)
            {
                importanceMatch = true;
                break;
            }
        }
        if (!importanceMatch) continue;

        g_isNewsPeriod = true;
        g_newsBlockUntil = endTime;
        g_newsReason = StringFormat("%s News: %s", eventImportance, event.name);

        Print("📰📰📰 NEWS FILTER ACTIVE 📰📰📰");
        Print("   Event: ", event.name);
        Print("   Blocked until: ", TimeToString(g_newsBlockUntil, TIME_DATE|TIME_MINUTES));
        return true;
    }

    g_isNewsPeriod = false;
    return false;
}

//+------------------------------------------------------------------+
//| Convert importance enum to string                                |
//+------------------------------------------------------------------+
string GetImportanceString(ENUM_CALENDAR_EVENT_IMPORTANCE importance)
{
   switch(importance)
   {
      case CALENDAR_IMPORTANCE_NONE:      return "NONE";
      case CALENDAR_IMPORTANCE_LOW:       return "LOW";
      case CALENDAR_IMPORTANCE_MODERATE:  return "MEDIUM";
      case CALENDAR_IMPORTANCE_HIGH:      return "HIGH";
      default:                            return "UNKNOWN";
   }
}
//+------------------------------------------------------------------+
