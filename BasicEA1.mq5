//+------------------------------------------------------------------+
//|                                                     BasicEA1.mq5 |
//|                                          Angelo R. L. Homen, CQF |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Angelo R. L. Homen, CQF"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "BasicEA - 1"

//+------------------------------------------------------------------+
//|DEFINES                                                           |
//+------------------------------------------------------------------+
#define LEVEL_95       10001
#define LEVEL_99       10002
#define RISK_VAR       10003
#define RISK_ES        10004
#define TRIGGER_BUY    10005
#define TRIGGER_SELL   10006
#define NO_TRIGGER     10007

//+------------------------------------------------------------------+
//| References                                                       |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Math/Stat/Normal.mqh>
CTrade            m_trade;
CPositionInfo     m_position;
CSymbolInfo       m_symbol;

//+------------------------------------------------------------------+
//| MQL Variables                                                    |
//+------------------------------------------------------------------+
MqlRates CandleData[];
MqlRates daily_bar[];

//+------------------------------------------------------------------+
//|ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_CONFIDENCE_LEVELS
  {
   _LEVEL_95 = LEVEL_95,   //95%
   _LEVEL_99 = LEVEL_99,   //99%
  };

enum ENUM_RISK_USING
  {
   _RISK_VAR = RISK_VAR,   //Value at Risk (VaR)
   _RISK_ES = RISK_ES,     //Expected Shortfall (ES)
  };

enum ENUM_TRIGGERS
  {
   _TRIGGER_BUY = TRIGGER_BUY,
   _TRIGGER_SELL = TRIGGER_SELL,
   _NO_TRIGGER = NO_TRIGGER,
  };

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
ulong magic_number;
int average_period;
ENUM_TIMEFRAMES returns_timeframe;
ENUM_RISK_USING risk_indicator;
double risk_array[];
double risk_ma;
double risk_std_dev;
double returns_array[];
double confidence_level;
double VaR = 0;
double ES = 0;
double array_mean;
double array_std_dev;
double last_value;
int init_trade_hour;
int init_trade_min;
int end_trade_hour;
int end_trade_min;
int close_pos_hour;
int close_pos_min;

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "Expert advisor's settings"
input ulong                   input_magic_number         = 1;                 //EA Magic number

input group "Expert advisor's setup parameters"
input ENUM_RISK_USING         input_risk_indicator       = RISK_VAR;          //Risk indicator calculation
input ENUM_TIMEFRAMES         input_returns_timeframe    = PERIOD_M1;         //Returns timeframe
input uint                    input_average_period       = 20;                //Risk indicator MA period
input ENUM_CONFIDENCE_LEVELS  input_confidence_level     = LEVEL_95;          //Risk indicator confidence level
input double                  input_risk_std_dev         = 2;                 //Risk indicator lower Standard Deviation
input string                  input_init_trade_time      = "09:05";           //Time to initialize trades
input string                  input_end_trade_time       = "13:00";           //Time to end trades
input string                  input_close_positions      = "17:00";           //Time to close positions

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!InitializeParameters())
      return(INIT_PARAMETERS_INCORRECT);

   if(!InitializeArrays())
      return(INIT_FAILED);

   m_trade.SetExpertMagicNumber(magic_number);

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {

  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   EACoreExecution();
  }

//+------------------------------------------------------------------+
//| Core logic                                                       |
//+------------------------------------------------------------------+
void EACoreExecution()
  {
   long check_positions = OpenPositionTicketByMagic();

   if(TimeToTrade())
     {
      if(NewCandle())
        {
         if(!CalculateStatistics())
            return;

         switch(TriggerActions())
           {
            case TRIGGER_BUY:
               BuyTriggerLogic(check_positions);
               break;
            case TRIGGER_SELL:
               SellTriggerLogic(check_positions);
               break;
            default:
               NoTriggerLogic(check_positions);
               break;
           }
        }
     }

   if(TimeToClosePositions())
     {
      if(check_positions != 0)
        {
         ulong ticket = MathAbs(check_positions);
         m_trade.PositionClose(ticket, -1);
        }
     }
  }

//+------------------------------------------------------------------+
//| Buy trigger logic                                                |
//+------------------------------------------------------------------+
void BuyTriggerLogic(long check_positions)
  {
   if(check_positions == 0) // No open position
     {
      if(m_trade.Buy(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), _Symbol, 0, 0, 0, NULL))
        {
         Print("Buy deal done.");
        }
     }
   else // Open position
     {
      ulong ticket = MathAbs(check_positions);

      if(check_positions > 0) //Buy open position
        {

        }
      else                    //Sell open position
        {
         m_trade.PositionClose(ticket, -1);
        }
     }
  }

//+------------------------------------------------------------------+
//| Sell trigger logic                                               |
//+------------------------------------------------------------------+
void SellTriggerLogic(long check_positions)
  {
   if(check_positions == 0) // No open position
     {
      if(m_trade.Sell(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), _Symbol, 0, 0, 0, NULL))
        {
         Print("Sell deal done.");
        }
     }
   else // Open position
     {
      ulong ticket = MathAbs(check_positions);

      if(check_positions > 0) //Buy open position
        {
         m_trade.PositionClose(ticket, -1);
        }
      else                    //Sell open position
        {

        }
     }
  }

//+------------------------------------------------------------------+
//| No trigger logic                                                 |
//+------------------------------------------------------------------+
void NoTriggerLogic(long check_positions)
  {
   if(check_positions == 0) // No open position
     {

     }
   else // Open position
     {
      ulong ticket = MathAbs(check_positions);

      if(check_positions > 0)
        {
         if(last_value <= array_mean)
           {
            m_trade.PositionClose(ticket, -1);
           }
        }

      if(check_positions < 0)
        {
         if(last_value >= array_mean)
           {
            m_trade.PositionClose(ticket, -1);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Open positions by magic                                          |
//+------------------------------------------------------------------+
long OpenPositionTicketByMagic()
  {
   if(m_position.SelectByMagic(_Symbol, magic_number))
     {
      long position_type;
      m_position.InfoInteger(POSITION_TYPE, position_type);
      if(position_type == POSITION_TYPE_BUY)
         return (long)m_position.Ticket();
      else
         return -(long)m_position.Ticket();
     }

   return 0;
  }

//+------------------------------------------------------------------+
//| Trigger actions                                                  |
//+------------------------------------------------------------------+
ENUM_TRIGGERS TriggerActions()
  {
   if(ArraySize(risk_array) < average_period)
     {
      return NO_TRIGGER;
     }

   RecalculateRiskArray();

   if(RiskIndicatorAboveStdDev())
     {
      return TRIGGER_BUY;
     }

   if(RiskIndicatorBelowStdDev())
     {
      return TRIGGER_SELL;
     }

   return NO_TRIGGER;
  }

//+------------------------------------------------------------------+
//| Recalculate risk array                                           |
//+------------------------------------------------------------------+
void RecalculateRiskArray()
  {
   array_mean = 0;
   array_std_dev = 0;
   last_value = risk_array[0];

   double array_sum = 0;

   for(int i = 0; i < average_period; i++)
     {
      array_sum += risk_array[i];
     }

   array_mean = array_sum/average_period;

   double std_dev_sum = 0;

   for(int i = 0; i < average_period; i++)
      std_dev_sum += MathPow(risk_array[i] - array_mean, 2);

   array_std_dev = MathSqrt(std_dev_sum/(average_period - 1));
  }

//+------------------------------------------------------------------+
//| VaR/ES with bigger risk                                          |
//+------------------------------------------------------------------+
bool RiskIndicatorBelowStdDev()
  {
   if(last_value < array_mean + array_std_dev * risk_std_dev)
     {
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| VaR/ES with less risk                                            |
//+------------------------------------------------------------------+
bool RiskIndicatorAboveStdDev()
  {
   if(last_value > array_mean + array_std_dev * risk_std_dev)
     {
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Calculate statisics                                              |
//+------------------------------------------------------------------+
bool CalculateStatistics()
  {
   if(CopyRates(_Symbol, returns_timeframe, 0, average_period, CandleData) < average_period)
     {
      Print("[ERROR] Error with copy rates.");
      return false;
     }

   int error_code = 0;
   int ES_count = 0;
   double ES_sum = 0;
   double returns_sum = 0;
   double std_dev_sum = 0;
   double returns_avg = 0;
   double returns_std_dev = 0;
   uint positive_count = 0;

   for(int i = 0; i < average_period; i++)
     {
      if(CandleData[i].close - CandleData[i].open > 0)
        {
         returns_array[i] = (CandleData[i].high - CandleData[i].low)/CandleData[i].high;
         returns_sum += returns_array[i];
         positive_count++;
        }
      else
        {
         returns_array[i] = (CandleData[i].low - CandleData[i].high)/CandleData[i].low;
         returns_sum += returns_array[i];
        }
     }

   returns_avg = returns_sum / average_period;

   for(int i = 0; i < average_period; i++)
      std_dev_sum += MathPow(returns_array[i] - returns_avg, 2);

   returns_std_dev = MathSqrt(std_dev_sum/(average_period-1));

   VaR = MathQuantileNormal(1 - confidence_level, returns_avg, returns_std_dev, error_code);

   for(int i = 0; i < ArraySize(returns_array); i++)
     {
      if(returns_array[i] <= VaR)
        {
         ES_sum += returns_array[i];
         ES_count++;
        }
     }

   if(risk_indicator == RISK_ES)
     {
      if(ES_count > 0)
        {
         ES = ES_sum/ES_count;
         RiskArrayConstruction(ES);
        }
      else
        {
         VaR = NULL;
         ES = NULL;
         return false;
        }
     }

   if(risk_indicator == RISK_VAR)
     {
      RiskArrayConstruction(VaR);
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Risk array construction                                          |
//+------------------------------------------------------------------+
void RiskArrayConstruction(double value)
  {
   if(ArraySize(risk_array) < average_period)
     {
      if(ArrayResize(risk_array, ArraySize(risk_array) + 1) == -1)
        {
         Print("[ERRO] Array 'risk_array' ressize error.");
        }
     }

   int risk_array_size = ArraySize(risk_array);

   for(int i = risk_array_size - 1; i >= 0; i--)
     {
      if(i == 0)
        {
         risk_array[i] = value;
         continue;
        }

      if(i < risk_array_size)
        {
         risk_array[i] = risk_array[i - 1];
        }
     }
  }

//+------------------------------------------------------------------+
//| Initialize arrays                                                |
//+------------------------------------------------------------------+
bool InitializeArrays()
  {
   if(!ArraySetAsSeries(CandleData, true))
      return false;

   if(!ArraySetAsSeries(daily_bar, true))
      return false;

   if(ArrayResize(returns_array, average_period) == -1)
     {
      Print("[ERRO] Array 'returns_array' ressize error.");
      return (false);
     }

   if(ArrayResize(risk_array, 0) == -1)
     {
      Print("[ERRO] Array 'risk_array' ressize error.");
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Initialize parameters                                            |
//+------------------------------------------------------------------+
bool InitializeParameters()
  {
   magic_number = input_magic_number;

   returns_timeframe = input_returns_timeframe;

   average_period = (int)input_average_period;

   if(input_risk_std_dev == 0)
      return false;

   if(input_risk_std_dev > 0)
      risk_std_dev = input_risk_std_dev;
   else
      risk_std_dev = -input_risk_std_dev;

   if(input_confidence_level == LEVEL_95)
      confidence_level = .95;
   else
      confidence_level = .99;

   if(input_risk_indicator == RISK_ES)
      risk_indicator = RISK_ES;
   else
      risk_indicator = RISK_VAR;

   if(!SetTimesOfTrading())
     {
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Time of Trading inputs                                           |
//+------------------------------------------------------------------+
bool SetTimesOfTrading()
  {
   string init_trade[];
   if(StringSplit(input_init_trade_time, ':', init_trade) < 2)
     {
      return false;
     }
   init_trade_hour = (int)StringToInteger(init_trade[0]);
   init_trade_min = (int)StringToInteger(init_trade[1]);

   string end_trade[];
   if(StringSplit(input_end_trade_time, ':', end_trade) < 2)
     {
      return false;
     }
   end_trade_hour = (int)StringToInteger(end_trade[0]);
   end_trade_min = (int)StringToInteger(end_trade[1]);

   string close_trade[];
   if(StringSplit(input_close_positions, ':', close_trade) < 2)
     {
      return false;
     }
   close_pos_hour = (int)StringToInteger(close_trade[0]);
   close_pos_min = (int)StringToInteger(close_trade[1]);

   int copied = CopyRates(_Symbol, PERIOD_D1, 0, 1, daily_bar);
   if(copied == 1)
     {
      datetime init = daily_bar[0].time + (init_trade_hour * 60 * 60) + (init_trade_min * 60);
      datetime end = daily_bar[0].time + (end_trade_hour * 60 * 60) + (end_trade_min * 60);
      datetime close = daily_bar[0].time + (close_pos_hour * 60 * 60) + (close_pos_min * 60);

      if(init > end)
        {
         Print("[ERROR] Time to end trades must be bigger than time to init trades.");
         return false;
        }

      if(close < end)
        {
         Print("[ERROR] Time to close position must be bigger than time to end trades.");
         return false;
        }

     }
   else
     {
      Print("[ERROR] Error with copy rates 'daily_bar'");
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| New Candle                                                       |
//+------------------------------------------------------------------+
bool NewCandle()
  {
   static datetime last_time_day = 0;

   datetime lastbar_time = (datetime)SeriesInfoInteger(_Symbol, returns_timeframe, SERIES_LASTBAR_DATE);

   if(last_time_day == 0)
     {
      last_time_day = lastbar_time;
      return false;
     }

   if(last_time_day != lastbar_time)
     {
      last_time_day = lastbar_time;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Time to trade                                                    |
//+------------------------------------------------------------------+
bool TimeToTrade()
  {
   int copied = CopyRates(_Symbol, PERIOD_D1, 0, 1, daily_bar);
   if(copied == 1)
     {
      datetime init = daily_bar[0].time + (init_trade_hour * 60 * 60) + (init_trade_min * 60);
      datetime end = daily_bar[0].time + (end_trade_hour * 60 * 60) + (end_trade_min * 60);

      datetime now = TimeTradeServer();

      if(now >= init && now < end)
        {
         return (true);
        }
     }
   else
     {
      Print("[ERROR] Error with copy rates 'daily_bar'");
      return false;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Time to close positions                                          |
//+------------------------------------------------------------------+
bool TimeToClosePositions()
  {
   int copied = CopyRates(_Symbol, PERIOD_D1, 0, 1, daily_bar);
   if(copied == 1)
     {
      datetime close_time = daily_bar[0].time + (close_pos_hour * 60 * 60) + (close_pos_min * 60);
      datetime now = TimeTradeServer();

      if(now >= close_time)
        {
         return (true);
        }
     }
   else
     {
      Print("[ERROR] Error with copy rates 'daily_bar'");
      return false;
     }
   return false;
  }
//+------------------------------------------------------------------+
