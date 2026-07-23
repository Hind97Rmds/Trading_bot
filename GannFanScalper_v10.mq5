//+------------------------------------------------------------------+
//|                                         GannFanScalper_v10.mq5    |
//|         Native MQL5 port of the Python "Gold Scalper" bot         |
//|   Gann-fan level engine + EMA/VWAP trend filter + BE + Excel      |
//|                                                                  |
//|   Logic parity source: strategy.py / gann_monitor.py /           |
//|   execution.py / state.py / market_data.py                       |
//+------------------------------------------------------------------+
#property copyright "Gann Fan Scalper"
#property version   "10.1"
#property strict
#property description "محرك مستويات جان + مروحة + فلاتر EMA/VWAP + Break-Even + تقرير Excel تفصيلي ملوّن"

#include <Trade/Trade.mqh>

//====================================================================
//  ENUMERATIONS
//====================================================================
enum ENUM_GANN_FILTER
{
   GANN_STAR_ONLY = 0,   // ⭐ المستويات القوية فقط
   GANN_STAR_FAN  = 1,   // ⭐🌀 القوية + الموازية للمروحة
   GANN_ALL       = 2    // 📋 كل المستويات (مخاطرة)
};

enum ENUM_ENTRY_MODE
{
   ENTRY_TOUCH_TREND = 0, // لمس + فلتر ترند
   ENTRY_TOUCH_BLIND = 1  // لمس أعمى (بدون فلتر)
};

enum ENUM_EXEC_MODE
{
   EXEC_INSTANT        = 0, // مباشر (لمس فوري)
   EXEC_CLOSE          = 1, // إغلاق شمعة
   EXEC_HYBRID         = 2, // هجين (لمس + حماية القفزة)
   EXEC_ALL_CONCURRENT = 3  // كل القنوات معاً
};

enum ENUM_TREND_FILTER
{
   TREND_EMA  = 0, // EMA فقط
   TREND_VWAP = 1, // VWAP فقط
   TREND_BOTH = 2  // EMA + VWAP معاً
};

enum ENUM_TPSL_MODE
{
   TPSL_FIXED = 0, // نقاط ثابتة
   TPSL_ATR   = 1  // ATR ديناميكي
};

//====================================================================
//  INPUT PARAMETERS
//====================================================================
input group "=== إعدادات الحساب والإدارة العامة ==="
input ulong    InpMagicNumber         = 888999;   // الماجيك نمبر (Magic Number)
input double   InpLotSize             = 0.05;     // حجم اللوت الأساسي (Lot Size)
input double   InpDailyMaxLossUSD     = 200.0;    // أقصى تراجع يومي بالدولار (Daily DD Limit)
input double   InpDailyProfitTargetUSD= 150.0;    // هدف الربح اليومي بالدولار (Daily Profit Target)
input int      InpMaxConcurrentTrades = 4;        // أقصى عدد صفقات مفتوحة في نفس الوقت
input bool     InpLiveTrading         = true;     // تنفيذ حقيقي (إيقافه = مراقبة فقط)
input int      InpMaxSlippagePoints   = 50;       // أقصى انزلاق مسموح بالنقاط (Deviation)

input group "=== محرك مستويات جان والمروحة ==="
input ENUM_TIMEFRAMES InpAnchorTF     = PERIOD_H1;         // الإطار المرجعي للأنكر (Anchor TF)
input int      InpCycleHours          = 1;                 // مدة تجميد السلّم بالساعات (Monitoring Hours)
input ENUM_GANN_FILTER InpZoneFilter  = GANN_STAR_ONLY;    // فلتر المستويات
input ENUM_ENTRY_MODE  InpEntryMode   = ENTRY_TOUCH_TREND; // وضع الدخول
input ENUM_EXEC_MODE   InpExecMode    = EXEC_INSTANT;      // طريقة التنفيذ
input int      InpTouchMarginPoints   = 50;                // هامش اللمس بالنقاط (Points)
input int      InpSpikeLimitPoints    = 200;               // حد الانفجار السعري للوضع الهجين (Points)
input bool     InpSpikeFilter         = true;              // تفعيل فلتر القفزة السعرية
input bool     InpExecRevalidation    = true;              // إعادة التحقق من اللمس قبل التنفيذ
input bool     InpAllowMultiTF        = true;              // السماح بنفس المستوى على أكثر من فريم

input group "=== فريمات المراقبة والتنفيذ ==="
input bool     InpEnable_M1  = true;  // فريم الدقيقة (1m)
input bool     InpEnable_M2  = true;  // فريم دقيقتين (2m)
input bool     InpEnable_M3  = true;  // فريم 3 دقائق (3m)
input bool     InpEnable_M4  = true;  // فريم 4 دقائق (4m)
input bool     InpEnable_M5  = true;  // فريم 5 دقائق (5m)
input bool     InpEnable_M6  = true;  // فريم 6 دقائق (6m)
input bool     InpEnable_M10 = true;  // فريم 10 دقائق (10m)
input bool     InpEnable_M15 = true;  // فريم 15 دقيقة (15m)
input bool     InpEnable_M20 = true;  // فريم 20 دقيقة (20m)
input bool     InpEnable_M30 = true;  // فريم 30 دقيقة (30m)
input bool     InpEnable_H1  = true;  // فريم الساعة (1h)
input bool     InpEnable_H2  = true;  // فريم ساعتين (2h)

input group "=== فلاتر الاتجاه (EMA / VWAP) ==="
input ENUM_TREND_FILTER InpTrendFilterType = TREND_EMA;   // نوع فلتر الترند
input ENUM_TIMEFRAMES   InpTrendTF         = PERIOD_H1;    // فريم فلتر الترند
input int      InpEmaPeriod           = 60;               // فترة EMA
input int      InpVwapPeriod          = 100;              // فترة VWAP

input group "=== إدارة الأهداف والوقف (TP / SL / BE) ==="
input ENUM_TPSL_MODE InpTpSlMode      = TPSL_FIXED; // نظام الأهداف والوقف
input int      InpFixedTpPoints       = 700;        // الهدف بالنقاط (Take Profit)
input int      InpFixedSlPoints       = 1100;       // الوقف بالنقاط (Stop Loss)
input int      InpAtrPeriod           = 14;         // فترة ATR
input double   InpAtrTpMult           = 2.0;        // مضاعف الهدف ATR
input double   InpAtrSlMult           = 1.5;        // مضاعف الوقف ATR
input bool     InpBreakEvenEnabled    = false;      // تفعيل حماية الدخول (Break-Even)
input int      InpBeTriggerPoints     = 400;        // مسافة تفعيل Break-Even بالنقاط
input bool     InpTrueCostBe          = true;       // BE شامل التكلفة والسبريد

input group "=== فلاتر الأوقات والحماية ==="
input bool     InpDamTimeFilter       = true;   // فلتر أوقات دمشق (07-09 | 13-14)
input int      InpBrokerGmtOffset     = 3;      // فارق توقيت السيرفر عن UTC
input int      InpDamascusUtcOffset   = 3;      // فارق توقيت دمشق عن UTC
input bool     InpCycleInvalEnabled   = true;   // إلغاء الدورة عند تحرك السعر الحاد
input int      InpCycleInvalPoints    = 2000;   // مسافة إلغاء الدورة بالنقاط

input group "=== التقارير والتشخيص ==="
input string   InpReportFile          = "Gann_LiveTrades_Report.xls"; // اسم ملف تقرير الصفقات (Excel)
input bool     InpReportCommonFolder  = false;  // حفظ التقرير في مجلد Common المشترك
input bool     InpVerboseJournal      = true;   // تشخيص تفصيلي في سجل MT5

//====================================================================
//  GANN COEFFICIENTS (mirror of GANN_COEFS in strategy.py)
//====================================================================
const double   GANN_TFC_H1 = 0.02;

double  g_coef[]      = {0.0208, 0.0417, 0.0625, 0.0833, 0.125, 0.25, 0.333, 0.5, 1.0, 2.0, 4.0};
bool    g_coefStar[]  = {false,  false,  false,  true,   false, false,false, true,true,false,false};
bool    g_coefFan[]   = {false,  false,  false,  false,  true,  false,false, false,false,false,false};

//====================================================================
//  DATA STRUCTURES
//====================================================================
struct SGannLevel
{
   string   key;    // e.g. "up_3" / "dn_7"
   double   price;
   int      dir;    // 0 = up (resistance), 1 = dn (support), 2 = ref
   bool     star;
   bool     fan;
};

SGannLevel  g_levels[];        // full ladder (includes ref)
string      g_usedKeys[];      // combo keys already consumed this cycle
double      g_closeUsed = 0.0; // anchor close that produced current levels

// ── Anchor / cycle tracking ──
datetime    g_lastAnchorTime  = 0;   // open-time of the anchor bar used
datetime    g_cycleStartTime  = 0;
bool        g_cycleActive      = false;

// ── Daily accounting ──
datetime    g_dailyDate        = 0;
double      g_dailyRealized     = 0.0;
bool        g_dailyHit          = false;

// ── Open-trade registry (parallel arrays keyed by position id) ──
ulong       g_posId[];
string      g_posTF[];
double      g_posLevel[];
double      g_posEntry[];
double      g_posTP[];
double      g_posSL[];
string      g_posTrigger[];
bool        g_posIsBuy[];
bool        g_posReal[];
datetime    g_posOpen[];
bool        g_posBE[];

// ── Closed-trade history (drives the Excel report) ──
string      h_symbol[], h_tf[], h_dir[], h_real[], h_outcome[], h_trigger[], h_reason[];
datetime    h_open[], h_close[];
double      h_dur[], h_level[], h_entry[], h_exit[], h_tp[], h_sl[], h_pnl[];
bool        h_be[];

CTrade      g_trade;

//====================================================================
//  ENABLED TIMEFRAME TABLE
//====================================================================
ENUM_TIMEFRAMES g_tfList[];
string          g_tfName[];

void AddTF(bool enabled, ENUM_TIMEFRAMES tf, string name)
{
   if(!enabled) return;
   int n = ArraySize(g_tfList);
   ArrayResize(g_tfList, n+1);
   ArrayResize(g_tfName, n+1);
   g_tfList[n] = tf;
   g_tfName[n] = name;
}

void BuildEnabledTFs()
{
   ArrayResize(g_tfList,0);
   ArrayResize(g_tfName,0);
   AddTF(InpEnable_M1 , PERIOD_M1 , "1m");
   AddTF(InpEnable_M2 , PERIOD_M2 , "2m");
   AddTF(InpEnable_M3 , PERIOD_M3 , "3m");
   AddTF(InpEnable_M4 , PERIOD_M4 , "4m");
   AddTF(InpEnable_M5 , PERIOD_M5 , "5m");
   AddTF(InpEnable_M6 , PERIOD_M6 , "6m");
   AddTF(InpEnable_M10, PERIOD_M10, "10m");
   AddTF(InpEnable_M15, PERIOD_M15, "15m");
   AddTF(InpEnable_M20, PERIOD_M20, "20m");
   AddTF(InpEnable_M30, PERIOD_M30, "30m");
   AddTF(InpEnable_H1 , PERIOD_H1 , "1h");
   AddTF(InpEnable_H2 , PERIOD_H2 , "2h");
}

//====================================================================
//  HELPERS
//====================================================================
double PriceRound(double p)   { return NormalizeDouble(p, _Digits); }
double MarginPrice()          { return InpTouchMarginPoints * _Point; }
double SpikePrice()           { return InpSpikeLimitPoints  * _Point; }

// Gold-calibrated true-cost BE buffer (Python: atr_period*0.1*pip_value ; for
// gold pip_value=0.1 and _Point=0.01 this equals atr_period*_Point).
double BeCostMargin()         { return InpTrueCostBe ? (InpAtrPeriod * _Point) : 0.0; }

datetime ServerToDAM(datetime s)
{
   return s + (datetime)((InpDamascusUtcOffset - InpBrokerGmtOffset) * 3600);
}

string DamString(datetime s)
{
   if(s == 0) return "";
   return TimeToString(ServerToDAM(s), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
}

bool InRestrictedWindow()
{
   if(!InpDamTimeFilter) return false;
   MqlDateTime m;
   TimeToStruct(ServerToDAM(TimeCurrent()), m);
   int hm = m.hour*60 + m.min;
   if(hm >= 7*60  && hm < 9*60)  return true;   // 07:00 - 09:00 DAM
   if(hm >= 13*60 && hm < 14*60) return true;   // 13:00 - 14:00 DAM
   return false;
}

void Journal(string msg)
{
   if(InpVerboseJournal) Print(msg);
}

//====================================================================
//  USED-KEY SET
//====================================================================
bool IsUsed(string key)
{
   for(int i=0; i<ArraySize(g_usedKeys); i++)
      if(g_usedKeys[i] == key) return true;
   return false;
}

void MarkUsed(string key)
{
   if(IsUsed(key)) return;
   int n = ArraySize(g_usedKeys);
   ArrayResize(g_usedKeys, n+1);
   g_usedKeys[n] = key;
}

void ClearUsed() { ArrayResize(g_usedKeys, 0); }

//====================================================================
//  TRADE REGISTRY
//====================================================================
void RegistryAdd(ulong posid, string tf, double level, double entry, double tp, double sl,
                 bool isBuy, bool isReal, string trigger, datetime openT)
{
   int n = ArraySize(g_posId);
   ArrayResize(g_posId,     n+1);
   ArrayResize(g_posTF,     n+1);
   ArrayResize(g_posLevel,  n+1);
   ArrayResize(g_posEntry,  n+1);
   ArrayResize(g_posTP,     n+1);
   ArrayResize(g_posSL,     n+1);
   ArrayResize(g_posTrigger,n+1);
   ArrayResize(g_posIsBuy,  n+1);
   ArrayResize(g_posReal,   n+1);
   ArrayResize(g_posOpen,   n+1);
   ArrayResize(g_posBE,     n+1);
   g_posId[n]=posid; g_posTF[n]=tf; g_posLevel[n]=level; g_posEntry[n]=entry;
   g_posTP[n]=tp; g_posSL[n]=sl; g_posTrigger[n]=trigger;
   g_posIsBuy[n]=isBuy; g_posReal[n]=isReal; g_posOpen[n]=openT; g_posBE[n]=false;
}

int RegistryFind(ulong posid)
{
   for(int i=0; i<ArraySize(g_posId); i++)
      if(g_posId[i] == posid) return i;
   return -1;
}

void RegistryRemove(int idx)
{
   int last = ArraySize(g_posId) - 1;
   if(idx < 0 || last < 0) return;
   g_posId[idx]=g_posId[last];         g_posTF[idx]=g_posTF[last];
   g_posLevel[idx]=g_posLevel[last];   g_posEntry[idx]=g_posEntry[last];
   g_posTP[idx]=g_posTP[last];         g_posSL[idx]=g_posSL[last];
   g_posTrigger[idx]=g_posTrigger[last];
   g_posIsBuy[idx]=g_posIsBuy[last];   g_posReal[idx]=g_posReal[last];
   g_posOpen[idx]=g_posOpen[last];     g_posBE[idx]=g_posBE[last];
   ArrayResize(g_posId,     last); ArrayResize(g_posTF,     last);
   ArrayResize(g_posLevel,  last); ArrayResize(g_posEntry,  last);
   ArrayResize(g_posTP,     last); ArrayResize(g_posSL,     last);
   ArrayResize(g_posTrigger,last); ArrayResize(g_posIsBuy,  last);
   ArrayResize(g_posReal,   last); ArrayResize(g_posOpen,   last);
   ArrayResize(g_posBE,     last);
}

bool RegistryHasTF(string tf)
{
   for(int i=0; i<ArraySize(g_posTF); i++)
      if(g_posTF[i] == tf) return true;
   return false;
}

//====================================================================
//  CLOSED-TRADE HISTORY
//====================================================================
void HistoryAppend(string symbol, string tf, string dir, string real,
                   datetime openT, datetime closeT, double durMin,
                   double level, double entry, double exitPx, double tp, double sl,
                   string outcome, double pnl, string trigger, bool be, string reason)
{
   int n = ArraySize(h_symbol);
   ArrayResize(h_symbol,n+1); ArrayResize(h_tf,n+1); ArrayResize(h_dir,n+1);
   ArrayResize(h_real,n+1);   ArrayResize(h_open,n+1); ArrayResize(h_close,n+1);
   ArrayResize(h_dur,n+1);    ArrayResize(h_level,n+1); ArrayResize(h_entry,n+1);
   ArrayResize(h_exit,n+1);   ArrayResize(h_tp,n+1);   ArrayResize(h_sl,n+1);
   ArrayResize(h_outcome,n+1);ArrayResize(h_pnl,n+1);  ArrayResize(h_trigger,n+1);
   ArrayResize(h_be,n+1);     ArrayResize(h_reason,n+1);
   h_symbol[n]=symbol; h_tf[n]=tf; h_dir[n]=dir; h_real[n]=real;
   h_open[n]=openT; h_close[n]=closeT; h_dur[n]=durMin; h_level[n]=level;
   h_entry[n]=entry; h_exit[n]=exitPx; h_tp[n]=tp; h_sl[n]=sl;
   h_outcome[n]=outcome; h_pnl[n]=pnl; h_trigger[n]=trigger; h_be[n]=be; h_reason[n]=reason;
}

//====================================================================
//  GANN LEVEL CALCULATION  (mirror of gann_calc_levels)
//====================================================================
void GannCalcLevels(double close)
{
   ArrayResize(g_levels, 0);
   double mult = (InpAnchorTF == PERIOD_H4) ? (GANN_TFC_H1 * 2.0) : GANN_TFC_H1;

   for(int i=0; i<ArraySize(g_coef); i++)
   {
      double offset = close * g_coef[i] * mult;
      double up = PriceRound(close + offset);
      double dn = PriceRound(close - offset);

      SGannLevel lu;
      lu.key = "up_"+(string)i; lu.price = up; lu.dir = 0;
      lu.star = g_coefStar[i];  lu.fan = g_coefFan[i];
      int n = ArraySize(g_levels); ArrayResize(g_levels, n+1); g_levels[n] = lu;

      if(dn > 0)
      {
         SGannLevel ld;
         ld.key = "dn_"+(string)i; ld.price = dn; ld.dir = 1;
         ld.star = g_coefStar[i]; ld.fan = g_coefFan[i];
         n = ArraySize(g_levels); ArrayResize(g_levels, n+1); g_levels[n] = ld;
      }
   }
   // reference level (anchor close)
   SGannLevel lr;
   lr.key="ref"; lr.price=PriceRound(close); lr.dir=2; lr.star=false; lr.fan=false;
   int m = ArraySize(g_levels); ArrayResize(g_levels, m+1); g_levels[m] = lr;
}

// active-level filter (mirror of gann_active_levels)
bool LevelIsActive(const SGannLevel &lv)
{
   if(lv.dir == 2) return false;                       // exclude ref
   if(InpZoneFilter == GANN_STAR_ONLY) return lv.star;
   if(InpZoneFilter == GANN_STAR_FAN)  return (lv.star || lv.fan);
   return true;                                        // GANN_ALL
}

int CountActiveLevels()
{
   int c=0;
   for(int i=0; i<ArraySize(g_levels); i++)
      if(LevelIsActive(g_levels[i])) c++;
   return c;
}

//====================================================================
//  ANCHOR / CYCLE MANAGER (mirror of gann_cycle_manager static_h1)
//====================================================================
void ManageCycle()
{
   datetime anchorBarTime = iTime(_Symbol, InpAnchorTF, 1); // last CLOSED anchor bar
   if(anchorBarTime <= 0) return;

   bool doAnchor = false;
   if(g_lastAnchorTime == 0)
      doAnchor = true;
   else if(anchorBarTime > g_lastAnchorTime)
   {
      double gapHours = (double)(anchorBarTime - g_lastAnchorTime) / 3600.0;
      if(gapHours >= (double)InpCycleHours) doAnchor = true;
   }
   if(!doAnchor) return;

   double h1close = iClose(_Symbol, InpAnchorTF, 1);
   if(h1close <= 0) return;

   GannCalcLevels(h1close);
   g_closeUsed      = h1close;
   g_lastAnchorTime = anchorBarTime;
   g_cycleStartTime = TimeCurrent();
   g_cycleActive    = true;
   ClearUsed();

   Journal(StringFormat("🔄 دورة جان جديدة (%dس) | إغلاق %s: %s | عدد المستويات النشطة: %d",
           InpCycleHours, EnumToString(InpAnchorTF),
           DoubleToString(h1close, _Digits), CountActiveLevels()));
}

// cycle invalidation (mirror of prot_cycle_inval)
void CheckCycleInvalidation()
{
   if(!InpCycleInvalEnabled || !g_cycleActive || g_closeUsed <= 0) return;
   double px = iClose(_Symbol, PERIOD_M1, 0);
   if(px <= 0) return;
   double dist = MathAbs(px - g_closeUsed);
   if(dist > InpCycleInvalPoints * _Point)
   {
      Journal(StringFormat("🚨 إلغاء الدورة: السعر تحرك بحدة (%s نقطة عن إغلاق الأنكر)",
              DoubleToString(dist/_Point, 0)));
      ArrayResize(g_levels, 0);
      g_closeUsed   = 0.0;
      g_cycleActive = false;
      ClearUsed();
   }
}

//====================================================================
//  TREND FILTER  (mirror of the EMA/VWAP block in gann_monitor_scanner)
//  returns: 1 = up, -1 = down, 0 = undecided / no data
//====================================================================
int MacroTrend()
{
   bool useEma  = (InpTrendFilterType == TREND_EMA  || InpTrendFilterType == TREND_BOTH);
   bool useVwap = (InpTrendFilterType == TREND_VWAP || InpTrendFilterType == TREND_BOTH);

   int pEma  = useEma  ? InpEmaPeriod  : 0;
   int pVwap = useVwap ? InpVwapPeriod : 0;
   int maxP  = MathMax(MathMax(pEma, pVwap), 100);
   int need  = MathMax(maxP + 10, 120);

   double close[];
   ArraySetAsSeries(close, false);
   int got = CopyClose(_Symbol, InpTrendTF, 1, need, close); // shift 1 = last closed
   if(got < 3) return 0;

   double curClose = close[got-1];
   bool emaUp  = false;
   bool vwapUp = false;

   if(useEma)
   {
      double alpha = 2.0 / (pEma + 1.0);
      double ema   = close[0];                       // seed = oldest (pandas ewm adjust=False)
      for(int i=1; i<got; i++)
         ema = alpha*close[i] + (1.0-alpha)*ema;
      emaUp = (curClose > ema);
   }

   if(useVwap)
   {
      double high[], low[];
      long   vol[];
      ArraySetAsSeries(high, false);
      ArraySetAsSeries(low , false);
      ArraySetAsSeries(vol , false);
      int gh = CopyHigh(_Symbol, InpTrendTF, 1, need, high);
      int gl = CopyLow (_Symbol, InpTrendTF, 1, need, low);
      int gv = CopyTickVolume(_Symbol, InpTrendTF, 1, need, vol);
      if(gh >= pVwap && gl >= pVwap && gv >= pVwap && pVwap > 0)
      {
         double sumTPV = 0.0, sumV = 0.0;
         int start = got - pVwap;                    // rolling window ending at last closed
         if(start < 0) start = 0;
         for(int i=start; i<got; i++)
         {
            double tp = (high[i] + low[i] + close[i]) / 3.0;
            double v  = (double)vol[i];
            sumTPV += tp * v;
            sumV   += v;
         }
         double vwap = (sumV > 0.0) ? (sumTPV / sumV) : curClose;
         vwapUp = (curClose > vwap);
      }
      else
      {
         return 0;                                   // insufficient VWAP data
      }
   }

   int state = 0;
   if(InpTrendFilterType == TREND_EMA)       state = emaUp  ? 1 : -1;
   else if(InpTrendFilterType == TREND_VWAP) state = vwapUp ? 1 : -1;
   else // BOTH: only decisive when both agree (Python returns None otherwise)
   {
      if(emaUp == vwapUp) state = emaUp ? 1 : -1;
      else                state = 0;
   }
   return state;
}

//====================================================================
//  ATR (mirror of _gann_atr)
//====================================================================
double GannATR(ENUM_TIMEFRAMES tf)
{
   int period = InpAtrPeriod;
   int need   = period + 50;
   double high[], low[], close[];
   ArraySetAsSeries(high, false);
   ArraySetAsSeries(low , false);
   ArraySetAsSeries(close,false);
   int gh = CopyHigh(_Symbol, tf, 1, need, high);
   int gl = CopyLow (_Symbol, tf, 1, need, low);
   int gc = CopyClose(_Symbol, tf, 1, need, close);
   int n  = MathMin(gh, MathMin(gl, gc));
   if(n < period + 1) return 0.0;

   double trSum = 0.0;
   int counted  = 0;
   for(int i=n-period; i<n; i++)
   {
      double prevClose = (i > 0) ? close[i-1] : close[i];
      double tr1 = high[i] - low[i];
      double tr2 = MathAbs(high[i] - prevClose);
      double tr3 = MathAbs(low[i]  - prevClose);
      double tr  = MathMax(tr1, MathMax(tr2, tr3));
      trSum += tr; counted++;
   }
   return (counted > 0) ? (trSum / counted) : 0.0;
}

//====================================================================
//  TP / SL DISTANCES (mirror of _gann_calc_tpsl)
//====================================================================
void CalcTpSlDist(ENUM_TIMEFRAMES tf, double &tpDist, double &slDist)
{
   if(InpTpSlMode == TPSL_ATR)
   {
      double atr = GannATR(tf);
      if(atr <= 0.0) atr = InpFixedSlPoints * _Point;  // fallback (mirror of Python)
      slDist = atr * InpAtrSlMult;
      tpDist = atr * InpAtrTpMult;
   }
   else
   {
      tpDist = InpFixedTpPoints * _Point;
      slDist = InpFixedSlPoints * _Point;
   }
}

double NormalizeLot(double lot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lot = MathRound(lot/step) * step;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return NormalizeDouble(lot, 2);
}

int CountMyPositions()
{
   int c = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      c++;
   }
   return c;
}

//====================================================================
//  TRADE ENTRY  (mirror of _gann_open_trade)
//====================================================================
void OpenTrade(bool isBuy, const SGannLevel &lv, ENUM_TIMEFRAMES tf, string tfName,
               string comboKey, string channel)
{
   if(InRestrictedWindow())
   {
      Journal(StringFormat("⏭️ [%s %s] رُفض الدخول: داخل نافذة دمشق المحظورة.", _Symbol, tfName));
      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double mid = (bid + ask) / 2.0;
   double margin = MarginPrice();

   if(InpExecRevalidation && MathAbs(mid - lv.price) > margin)
   {
      MarkUsed(comboKey);
      Journal(StringFormat("⏭️ [%s %s] رُفض: السعر ابتعد عن المستوى أثناء التنفيذ (%s ≠ %s).",
              _Symbol, tfName, DoubleToString(mid,_Digits), DoubleToString(lv.price,_Digits)));
      return;
   }

   double price = mid;
   double tpDist, slDist;
   CalcTpSlDist(tf, tpDist, slDist);

   double tp = isBuy ? PriceRound(price + tpDist) : PriceRound(price - tpDist);
   double sl = isBuy ? PriceRound(price - slDist) : PriceRound(price + slDist);

   if((isBuy && (price >= tp || price <= sl)) || (!isBuy && (price <= tp || price >= sl)))
   {
      MarkUsed(comboKey);
      Journal(StringFormat("⏭️ [%s %s] أُلغيت قبل الإرسال: السعر تجاوز TP/SL (TP:%s SL:%s).",
              _Symbol, tfName, DoubleToString(tp,_Digits), DoubleToString(sl,_Digits)));
      return;
   }

   MarkUsed(comboKey);

   if(!InpLiveTrading)
   {
      Journal(StringFormat("🟡 [مراقبة فقط] إشارة %s %s [%s] عند المستوى %s (لمس %s).",
              (isBuy?"BUY":"SELL"), _Symbol, tfName, DoubleToString(lv.price,_Digits), channel));
      return;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints((ulong)InpMaxSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   double lot = NormalizeLot(InpLotSize);
   bool ok = isBuy ? g_trade.Buy(lot, _Symbol, 0.0, sl, tp, tfName)
                   : g_trade.Sell(lot, _Symbol, 0.0, sl, tp, tfName);

   if(!ok)
   {
      Journal(StringFormat("❌ فشل فتح صفقة %s %s [%s]: retcode=%d (%s)",
              (isBuy?"BUY":"SELL"), _Symbol, tfName,
              g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
      return;
   }

   ulong  posid = g_trade.ResultOrder();
   double fill  = g_trade.ResultPrice();
   if(fill <= 0.0) fill = price;

   ulong dealTicket = g_trade.ResultDeal();
   if(dealTicket > 0 && HistoryDealSelect(dealTicket))
      posid = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

   // rebase TP/SL onto the ACTUAL fill (mirror of Python rebase-on-fill)
   if(MathAbs(fill - price) > _Point/2.0)
   {
      tp = isBuy ? PriceRound(fill + tpDist) : PriceRound(fill - tpDist);
      sl = isBuy ? PriceRound(fill - slDist) : PriceRound(fill + slDist);
      if(!g_trade.PositionModify(posid, sl, tp))
         Journal(StringFormat("⚠️ فشل تعديل TP/SL بعد التنفيذ [%s]: %s",
                 tfName, g_trade.ResultRetcodeDescription()));
   }

   RegistryAdd(posid, tfName, lv.price, fill, tp, sl, isBuy, true, channel, TimeCurrent());

   double slipPts = MathAbs(fill - lv.price) / _Point;
   Journal(StringFormat("✅ تم فتح %s %s [جان %s] | لمس %s | المستوى: %s | الدخول: %s | TP:%s SL:%s | انزلاق: %s نقطة | إغلاق الأنكر: %s",
           (isBuy?"BUY 📈":"SELL 📉"), _Symbol, tfName, channel,
           DoubleToString(lv.price,_Digits), DoubleToString(fill,_Digits),
           DoubleToString(tp,_Digits), DoubleToString(sl,_Digits),
           DoubleToString(slipPts,0), DoubleToString(g_closeUsed,_Digits)));
}

//====================================================================
//  TICK-DRIVEN ENTRY SCAN  (mirror of _gann_tick_fire_check)
//====================================================================
void EntryScan()
{
   if(g_dailyHit)      return;
   if(!g_cycleActive || ArraySize(g_levels) == 0) return;

   int maxConc = MathMax(1, InpMaxConcurrentTrades);
   if(CountMyPositions() >= maxConc) return;

   int trend = (InpEntryMode == ENTRY_TOUCH_TREND) ? MacroTrend() : 1;
   bool trendUp = (trend == 1);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double margin = MarginPrice();
   double spike  = SpikePrice();

   string channels[];
   if(InpExecMode == EXEC_ALL_CONCURRENT) { ArrayResize(channels,3); channels[0]="touch"; channels[1]="close"; channels[2]="hybrid"; }
   else if(InpExecMode == EXEC_CLOSE)     { ArrayResize(channels,1); channels[0]="close"; }
   else if(InpExecMode == EXEC_HYBRID)    { ArrayResize(channels,1); channels[0]="hybrid"; }
   else                                   { ArrayResize(channels,1); channels[0]="touch"; }

   for(int t=0; t<ArraySize(g_tfList); t++)
   {
      ENUM_TIMEFRAMES tf = g_tfList[t];
      string tfName      = g_tfName[t];

      if(RegistryHasTF(tfName)) continue;

      if(InpEntryMode == ENTRY_TOUCH_TREND && trend == 0) continue; // undecided trend

      double closedClose = iClose(_Symbol, tf, 1);
      if(closedClose <= 0) continue;

      for(int ch=0; ch<ArraySize(channels); ch++)
      {
         string channel = channels[ch];

         for(int i=0; i<ArraySize(g_levels); i++)
         {
            SGannLevel lv = g_levels[i];
            if(!LevelIsActive(lv)) continue;

            string baseCombo = InpAllowMultiTF ? (lv.key+"_"+tfName) : lv.key;
            string comboKey  = (InpExecMode == EXEC_ALL_CONCURRENT) ? (baseCombo+"_"+channel) : baseCombo;
            if(IsUsed(comboKey)) continue;

            bool isBuy = (lv.dir == 1);              // support -> buy, resistance -> sell

            if(InpEntryMode == ENTRY_TOUCH_TREND)
            {
               if(isBuy  && !trendUp) continue;
               if(!isBuy &&  trendUp) continue;
            }

            double checkPx = isBuy ? bid : ask;
            bool touched = false;
            if(channel == "close")
               touched = (MathAbs(closedClose - lv.price) <= margin);
            else if(channel == "hybrid")
            {
               if(MathAbs(checkPx - lv.price) > margin) touched = false;
               else if(InpSpikeFilter && MathAbs(checkPx - closedClose) > spike) touched = false;
               else touched = true;
            }
            else
               touched = (MathAbs(checkPx - lv.price) <= margin);

            if(!touched) continue;

            Journal(StringFormat("🎯 لمس مستوى [%s] %s على فريم %s (قناة %s) | السعر: %s | المستوى: %s",
                    (isBuy?"دعم/شراء":"مقاومة/بيع"), _Symbol, tfName, channel,
                    DoubleToString(checkPx,_Digits), DoubleToString(lv.price,_Digits)));

            OpenTrade(isBuy, lv, tf, tfName, comboKey, channel);
            break;                                   // one level per channel per tf
         }

         if(CountMyPositions() >= maxConc) return;
      }
   }
}

//====================================================================
//  BREAK-EVEN MANAGEMENT  (mirror of core_eval_break_even)
//====================================================================
void ManageBreakEven()
{
   if(!InpBreakEvenEnabled) return;
   double beDist   = InpBeTriggerPoints * _Point;
   double beMargin = BeCostMargin();

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ulong posid = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      int   ri    = RegistryFind(posid);
      if(ri >= 0 && g_posBE[ri]) continue;

      bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double curTp = PositionGetDouble(POSITION_TP);
      double px    = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool trigger = (isBuy  && px >= entry + beDist) ||
                     (!isBuy && px <= entry - beDist);
      if(!trigger) continue;

      double newSl = isBuy ? PriceRound(entry + beMargin) : PriceRound(entry - beMargin);
      g_trade.SetExpertMagicNumber(InpMagicNumber);
      if(g_trade.PositionModify(tk, newSl, curTp))
      {
         if(ri >= 0) { g_posBE[ri] = true; g_posSL[ri] = newSl; }
         Journal(StringFormat("🛡️ تم تفعيل Break-Even [%s] عند %s", _Symbol, DoubleToString(newSl,_Digits)));
      }
      else
         Journal(StringFormat("⚠️ فشل تفعيل Break-Even [%s]: %s", _Symbol, g_trade.ResultRetcodeDescription()));
   }
}

//====================================================================
//  DAILY PnL LIMITS
//====================================================================
double FloatingPnL()
{
   double total = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return total;
}

void CloseAllMyPositions()
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints((ulong)InpMaxSlippagePoints);
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(!g_trade.PositionClose(tk))
         Journal(StringFormat("⚠️ فشل إغلاق الصفقة #%I64u: %s", tk, g_trade.ResultRetcodeDescription()));
   }
}

void CheckDailyLimits()
{
   double totalDay  = g_dailyRealized + FloatingPnL();
   double ddLimit   = -MathAbs(InpDailyMaxLossUSD);
   double profitLim = InpDailyProfitTargetUSD;
   bool hitDD     = (ddLimit   < 0.0 && totalDay <= ddLimit);
   bool hitProfit = (profitLim > 0.0 && totalDay >= profitLim);

   if(hitDD || hitProfit)
   {
      g_dailyHit = true;
      Journal(StringFormat("%s تم الوصول للحد اليومي (%s$). سيتم إغلاق جميع الصفقات.",
              (hitDD ? "🛑 تراجع يومي" : "✅ هدف ربح يومي"), DoubleToString(totalDay,2)));
      CloseAllMyPositions();
   }
}

//====================================================================
//  NEW-DAY RESET
//====================================================================
void CheckNewDay()
{
   MqlDateTime m;
   TimeToStruct(TimeCurrent(), m);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", m.year, m.mon, m.day));
   if(g_dailyDate != today)
   {
      if(g_dailyDate != 0)
         Journal(StringFormat("🌅 يوم تداول جديد. تصفير العدادات اليومية (ربح محقق سابق: %s$).",
                 DoubleToString(g_dailyRealized,2)));
      g_dailyDate     = today;
      g_dailyRealized = 0.0;
      g_dailyHit      = false;
   }
}

//====================================================================
//  EXCEL (SpreadsheetML) REPORT ENGINE  — replaces the openpyxl exporter
//  Produces a real Excel-openable .xls with bold header + colored
//  WIN(green)/LOSS(red)/BE(gray) rows, mirroring export_live_trades_excel.
//====================================================================
string XmlEsc(string s)
{
   StringReplace(s, "&",  "&amp;");
   StringReplace(s, "<",  "&lt;");
   StringReplace(s, ">",  "&gt;");
   StringReplace(s, "\"", "&quot;");
   return s;
}

string StrCell(string style, string text)
{
   return "<Cell ss:StyleID=\""+style+"\"><Data ss:Type=\"String\">"+XmlEsc(text)+"</Data></Cell>";
}

string NumCell(string style, double val, int digits)
{
   return "<Cell ss:StyleID=\""+style+"\"><Data ss:Type=\"Number\">"+DoubleToString(val,digits)+"</Data></Cell>";
}

void WriteExcelReport()
{
   string nl = "\r\n";
   string xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + nl;
   xml += "<?mso-application progid=\"Excel.Sheet\"?>" + nl;
   xml += "<Workbook xmlns=\"urn:schemas-microsoft-com:office:spreadsheet\""
          " xmlns:ss=\"urn:schemas-microsoft-com:office:spreadsheet\">" + nl;

   // ── styles ──
   xml += "<Styles>";
   xml += "<Style ss:ID=\"hdr\"><Font ss:Bold=\"1\"/><Interior ss:Color=\"#D3D3D3\" ss:Pattern=\"Solid\"/>"
          "<Alignment ss:Horizontal=\"Center\" ss:Vertical=\"Center\"/></Style>";
   xml += "<Style ss:ID=\"win\"><Interior ss:Color=\"#C6EFCE\" ss:Pattern=\"Solid\"/>"
          "<Alignment ss:Horizontal=\"Center\"/></Style>";
   xml += "<Style ss:ID=\"loss\"><Interior ss:Color=\"#FFC7CE\" ss:Pattern=\"Solid\"/>"
          "<Alignment ss:Horizontal=\"Center\"/></Style>";
   xml += "<Style ss:ID=\"be\"><Interior ss:Color=\"#E0E0E0\" ss:Pattern=\"Solid\"/>"
          "<Alignment ss:Horizontal=\"Center\"/></Style>";
   xml += "<Style ss:ID=\"pln\"><Alignment ss:Horizontal=\"Center\"/></Style>";
   xml += "</Styles>" + nl;

   xml += "<Worksheet ss:Name=\"الصفقات الحية\"><Table>" + nl;

   // ── header row ──
   string hdrs[] = {"الزوج","الفريم","حقيقية/وهمية","الاتجاه","وقت الفتح (DAM)",
                    "وقت الإغلاق (DAM)","المدة (د)","مستوى الدخول","الدخول الفعلي",
                    "انزلاق الدخول","TP","SL","سعر الإغلاق","النتيجة","الربح ($)",
                    "نوع التنفيذ","BE مفعّل؟","سبب الإغلاق","الرصيد التراكمي"};
   xml += "<Row>";
   for(int i=0; i<ArraySize(hdrs); i++)
      xml += StrCell("hdr", hdrs[i]);
   xml += "</Row>" + nl;

   // ── data rows ──
   double running = 0.0;
   int nWin=0, nLoss=0, nBe=0;
   for(int r=0; r<ArraySize(h_symbol); r++)
   {
      running += h_pnl[r];
      string st = "pln";
      if(h_outcome[r]=="WIN")  { st="win";  nWin++;  }
      else if(h_outcome[r]=="LOSS") { st="loss"; nLoss++; }
      else if(h_outcome[r]=="BE")   { st="be";   nBe++;   }

      double slip = (h_entry[r]-h_level[r]) / _Point;

      xml += "<Row>";
      xml += StrCell(st, h_symbol[r]);
      xml += StrCell(st, h_tf[r]);
      xml += StrCell(st, h_real[r]);
      xml += StrCell(st, h_dir[r]);
      xml += StrCell(st, DamString(h_open[r]));
      xml += StrCell(st, DamString(h_close[r]));
      xml += NumCell(st, h_dur[r], 1);
      xml += NumCell(st, h_level[r], _Digits);
      xml += NumCell(st, h_entry[r], _Digits);
      xml += NumCell(st, slip, 0);
      xml += NumCell(st, h_tp[r], _Digits);
      xml += NumCell(st, h_sl[r], _Digits);
      xml += NumCell(st, h_exit[r], _Digits);
      xml += StrCell(st, h_outcome[r]);
      xml += NumCell(st, h_pnl[r], 2);
      xml += StrCell(st, h_trigger[r]);
      xml += StrCell(st, h_be[r] ? "نعم" : "—");
      xml += StrCell(st, h_reason[r]);
      xml += NumCell(st, running, 2);
      xml += "</Row>" + nl;
   }

   // ── summary row ──
   int total = ArraySize(h_symbol);
   double wr = (nWin+nLoss>0) ? (100.0*nWin/(nWin+nLoss)) : 0.0;
   xml += "<Row></Row>";
   xml += "<Row>"
        + StrCell("hdr","الإجمالي")
        + StrCell("pln", StringFormat("صفقات: %d | فوز: %d | خسارة: %d | تعادل: %d | WR: %s%% | صافي: %s$",
                  total, nWin, nLoss, nBe, DoubleToString(wr,1), DoubleToString(running,2)))
        + "</Row>" + nl;

   xml += "</Table></Worksheet></Workbook>" + nl;

   // ── write as UTF-8 bytes so Arabic renders correctly ──
   uchar bytes[];
   int len = StringToCharArray(xml, bytes, 0, -1, CP_UTF8);
   if(len > 0 && bytes[len-1] == 0) len--;   // strip null terminator

   int flags = FILE_WRITE|FILE_BIN;
   if(InpReportCommonFolder) flags |= FILE_COMMON;
   int fh = FileOpen(InpReportFile, flags);
   if(fh == INVALID_HANDLE)
   {
      Print("⚠️ تعذّر فتح ملف تقرير Excel: ", InpReportFile, " (خطأ ", GetLastError(), ")");
      return;
   }
   FileWriteArray(fh, bytes, 0, len);
   FileClose(fh);
}

//====================================================================
//  ONINIT
//====================================================================
void RebuildRegistryFromPositions()
{
   ArrayResize(g_posId, 0);
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      ulong  posid = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double tp    = PositionGetDouble(POSITION_TP);
      double sl    = PositionGetDouble(POSITION_SL);
      string tf    = PositionGetString(POSITION_COMMENT);
      datetime ot  = (datetime)PositionGetInteger(POSITION_TIME);
      RegistryAdd(posid, tf, entry, entry, tp, sl, isBuy, true, "restored", ot);
   }
}

int OnInit()
{
   BuildEnabledTFs();
   if(ArraySize(g_tfList) == 0)
   {
      Print("🛑 لا يوجد أي فريم مفعّل — لن يعمل السكانر.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints((ulong)InpMaxSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   RebuildRegistryFromPositions();
   CheckNewDay();
   ManageCycle();
   WriteExcelReport();   // create the file immediately (header + any history)

   Journal(StringFormat("🚀 GannFanScalper v10.1 بدأ على %s | فريمات مفعّلة: %d | فلتر: %s | وضع الدخول: %s | تنفيذ: %s | التقرير: %s",
           _Symbol, ArraySize(g_tfList),
           EnumToString(InpZoneFilter), EnumToString(InpEntryMode), EnumToString(InpExecMode), InpReportFile));
   return(INIT_SUCCEEDED);
}

//====================================================================
//  ONDEINIT
//====================================================================
void OnDeinit(const int reason)
{
   WriteExcelReport();   // ensure the final report is flushed
   Journal(StringFormat("⏹️ GannFanScalper v10.1 توقف على %s (سبب: %d). تم حفظ التقرير: %s",
           _Symbol, reason, InpReportFile));
}

//====================================================================
//  ONTICK
//====================================================================
void OnTick()
{
   CheckNewDay();
   ManageCycle();
   CheckCycleInvalidation();

   CheckDailyLimits();
   if(g_dailyHit) { ManageBreakEven(); return; }

   ManageBreakEven();
   if(InRestrictedWindow()) return;   // entries blocked; management still ran
   EntryScan();
}

//====================================================================
//  ONTRADETRANSACTION  (close detection + Excel export)
//====================================================================
string DealReasonLabel(long reason)
{
   switch((int)reason)
   {
      case DEAL_REASON_TP:     return "الهدف TP";
      case DEAL_REASON_SL:     return "الوقف SL";
      case DEAL_REASON_SO:     return "إغلاق إجباري (Stop Out)";
      case DEAL_REASON_EXPERT: return "حماية رأس المال / الإكسبيرت";
      case DEAL_REASON_CLIENT: return "إغلاق يدوي";
      case DEAL_REASON_MOBILE: return "إغلاق يدوي (موبايل)";
      case DEAL_REASON_WEB:    return "إغلاق يدوي (ويب)";
      default:                 return "غير محدد";
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult  &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY) return;

   ulong  posid   = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   double exitPx  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double pnl     = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                  + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                  + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   datetime closeT= (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   string  reason = DealReasonLabel(HistoryDealGetInteger(trans.deal, DEAL_REASON));

   int ri = RegistryFind(posid);
   string tfName = "?", trigger = "—";
   double levelPx=exitPx, entryPx=exitPx, tp=0.0, sl=0.0;
   bool   isBuy = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_SELL);
   bool   isReal = true, be = false;
   datetime openT = closeT;

   if(ri >= 0)
   {
      tfName=g_posTF[ri]; levelPx=g_posLevel[ri]; entryPx=g_posEntry[ri];
      tp=g_posTP[ri]; sl=g_posSL[ri]; trigger=g_posTrigger[ri];
      isBuy=g_posIsBuy[ri]; isReal=g_posReal[ri]; be=g_posBE[ri]; openT=g_posOpen[ri];
   }

   double durMin = (closeT > openT) ? ((double)(closeT - openT) / 60.0) : 0.0;
   string outcome = (pnl > 0.0) ? "WIN" : (pnl < 0.0 ? "LOSS" : "BE");

   g_dailyRealized += pnl;

   string trigLbl = trigger;
   if(trigger=="touch")  trigLbl="لمس مباشر ⚡";
   else if(trigger=="close")  trigLbl="إغلاق شمعة ⏳";
   else if(trigger=="hybrid") trigLbl="تنفيذ هجين 🛡️";

   HistoryAppend(_Symbol, tfName, (isBuy?"BUY 📈":"SELL 📉"), (isReal?"حقيقية":"وهمية"),
                 openT, closeT, durMin, levelPx, entryPx, exitPx, tp, sl,
                 outcome, pnl, trigLbl, be, reason);

   WriteExcelReport();

   Journal(StringFormat("🔔 إغلاق صفقة [%s جان %s] | النتيجة: %s | السبب: %s | الربح: %s$ | الرصيد: %s$",
           _Symbol, tfName, outcome, reason, DoubleToString(pnl,2),
           DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)));

   if(ri >= 0) RegistryRemove(ri);
}
//+------------------------------------------------------------------+
