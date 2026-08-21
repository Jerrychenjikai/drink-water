#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <queue>
#include <string>
#include <time.h>     
#include "esp_pm.h"   
#include "HX711.h"    

// ==================== 1. 全局常量配置 ====================
#define BLE_DEVICE_NAME        "ESP32S3_SmartBottle"
#define SERVICE_UUID           "11111111-2222-3333-4444-555555555555" 
#define CHARACTERISTIC_UUID_RX "11111111-2222-3333-4444-555555555556" 
#define CHARACTERISTIC_UUID_TX "11111111-2222-3333-4444-555555555557" 

// 硬件引脚配置
#define HX711_DOUT_PIN         4
#define HX711_SCK_PIN          5
#define HX711_SCALE_FACTOR     392.16f

// 喝水算法参数配置
#define WEIGHT_THRESHOLD       3.0f     // 物理防抖判定门限（g）
#define STABLE_DELAY           2000     // 读数稳定等待时间（ms）
#define LIFT_THRESHOLD         100.0f   // 判定为“拿起/放回”的最小重量变化（g），建议小于空杯重
#define MIN_DRINK_VOL          10.0f    // 最小有效喝水记录水量（g），低于此值不入列

// ==================== 2. 数据结构定义 ====================
struct DrinkRecord {
    int volume;                  // 喝水量 (g)
    unsigned long eventMillis;   // 发生的相对时间戳
};

struct BottleDetectorState {
    float currentWeight = 0.0f;       // 当前实时重量
    float lastStableWeight = 0.0f;    // 上一次稳定的读数
    float lastValidWeight = 0.0f;     // M1: 拿起前的稳定基准重量
    float liftedMinWeight = 0.0f;     // M2 (过程极小值): 拿起期间检测到的最低重量
    bool isLifted = false;             // 状态标识：水杯是否离开秤面
    bool initialized = false;          // 是否已完成首次基准初始化
    unsigned long lastWeightChangeTime = 0; // 最后一次重量发生波动的时间点
};

// ==================== 3. 全局对象与变量 ====================
HX711 scale;
BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic = NULL;
std::queue<DrinkRecord> messageQueue;
BottleDetectorState g_detector;

bool deviceConnected = false;
bool oldDeviceConnected = false;

// 时间同步状态
bool hasTimeRecord = false;
unsigned long timeSyncMillis = 0;
time_t timeSyncEpoch = 0;

// ==================== 4. 蓝牙回调类 ====================
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) override {
      deviceConnected = true;
    }
    void onDisconnect(BLEServer* pServer) override {
      deviceConnected = false;
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) override {
      String rxValue = pCharacteristic->getValue().c_str();

      if (rxValue.length() > 0 && rxValue.indexOf("\"current time\"") > 0) {
        int timeIndex = rxValue.indexOf("\"time\"");
        if (timeIndex > 0) {
            int start = rxValue.indexOf("\"", timeIndex + 6) + 1;
            int end = rxValue.indexOf("\"", start);

            if (start > 0 && end > start) {
                String tStr = rxValue.substring(start, end);
                int y, mo, d, h, m, s;
                if (sscanf(tStr.c_str(), "%d-%d-%dT%d:%d:%dZ", &y, &mo, &d, &h, &m, &s) == 6) {
                    struct tm t = {0};
                    t.tm_year = y - 1900;
                    t.tm_mon = mo - 1;
                    t.tm_mday = d;
                    t.tm_hour = h;
                    t.tm_min = m;
                    t.tm_sec = s;
                    
                    timeSyncEpoch = mktime(&t);    
                    timeSyncMillis = millis();     
                    hasTimeRecord = true;
                    Serial.println("MCU 已成功同步绝对时间！");
                }
            }
        }
      }
    }
};

// ==================== 5. 辅助函数 ====================
std::string getAbsoluteTime(unsigned long eventMillis) {
    long diffSeconds = (long)(eventMillis - timeSyncMillis) / 1000;
    time_t eventEpoch = timeSyncEpoch + diffSeconds;
    
    struct tm *ti = gmtime(&eventEpoch);
    char timeBuf[32];
    snprintf(timeBuf, sizeof(timeBuf), "%04d-%02d-%02dT%02d:%02d:%02dZ", 
             ti->tm_year + 1900, ti->tm_mon + 1, ti->tm_mday, 
             ti->tm_hour, ti->tm_min, ti->tm_sec);
             
    return std::string(timeBuf);
}

// 核心喝水检测状态机（已修复初始化死锁问题）
void processWeightDetection(unsigned long currentMillis, float newWeight) {
    // 1. 物理防抖检测
    if (abs(newWeight - g_detector.currentWeight) > WEIGHT_THRESHOLD) {
        g_detector.currentWeight = newWeight;
        g_detector.lastWeightChangeTime = currentMillis; 
        
        // 如果处在被拿起状态，不断更新离秤期间的最低读数
        if (g_detector.isLifted && newWeight < g_detector.liftedMinWeight) {
            g_detector.liftedMinWeight = newWeight;
        }
    } 
    else {
        // 2. 读数稳定满 STABLE_DELAY 毫秒
        if (currentMillis - g_detector.lastWeightChangeTime > STABLE_DELAY) {
            
            // 【修正重点】未初始化时，只要读数静止满 2 秒，无需触发重量差变化，直接锁定 M1
            if (!g_detector.initialized) {
                g_detector.lastStableWeight = g_detector.currentWeight;
                g_detector.lastValidWeight = g_detector.currentWeight;
                g_detector.initialized = true;
                Serial.printf("【初始化成功】检测到系统静止，基准重量 M1 锁定为: %.1f g\n", g_detector.lastValidWeight);
                return;
            }

            // 初始化完成后，才触发重量突变的状态切换逻辑
            if (abs(g_detector.currentWeight - g_detector.lastStableWeight) > WEIGHT_THRESHOLD) {
                g_detector.lastStableWeight = g_detector.currentWeight;

                if (!g_detector.isLifted) {
                    // 【状态 A：水杯在秤上】
                    if (g_detector.currentWeight < g_detector.lastValidWeight - LIFT_THRESHOLD) {
                        g_detector.isLifted = true;
                        g_detector.liftedMinWeight = g_detector.currentWeight;
                        Serial.println("【状态切换】水杯被拿起，锁定基准重量 M1");
                    } 
                    else {
                        // 未达拿起门限，平滑更新基准
                        g_detector.lastValidWeight = g_detector.currentWeight;
                    }
                } 
                else {
                    // 【状态 B：水杯已被拿起】
                    if (g_detector.currentWeight > g_detector.liftedMinWeight + LIFT_THRESHOLD) {
                        float drinkAmount = g_detector.lastValidWeight - g_detector.currentWeight; // M1 - M3
                        
                        if (drinkAmount >= MIN_DRINK_VOL) {
                            messageQueue.push({(int)drinkAmount, currentMillis});
                            Serial.printf("【喝水成功】喝水量: %d g (M1: %.1f -> M3: %.1f)\n", 
                                          (int)drinkAmount, g_detector.lastValidWeight, g_detector.currentWeight);
                        } 
                        else if (drinkAmount <= -MIN_DRINK_VOL) {
                            Serial.printf("【检测加水】增加水量: %d g\n", (int)(-drinkAmount));
                        } 
                        else {
                            Serial.println("【状态结算】水杯已放回，水量基本无变化");
                        }

                        // 结算完毕：更新基准 M1，重置状态
                        g_detector.lastValidWeight = g_detector.currentWeight;
                        g_detector.isLifted = false;
                        Serial.println("【状态切换】水杯已放回，更新基准重量 M1");
                    }
                }
            }
        }
    }
}

// ==================== 6. Arduino 主程序 ====================
void setup() {
  Serial.begin(115200);
  
  setenv("TZ", "GMT0", 1);
  tzset();

  // 低功耗配置
  esp_pm_config_esp32s3_t pm_config = {
      .max_freq_mhz = 160,
      .min_freq_mhz = 10,   
      .light_sleep_enable = true 
  };
  esp_pm_configure(&pm_config);
  
  // HX711 初始化
  scale.begin(HX711_DOUT_PIN, HX711_SCK_PIN);
  scale.set_scale(HX711_SCALE_FACTOR); 
  delay(500);
  scale.tare();           

  // BLE 初始化
  BLEDevice::init(BLE_DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pTxCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID_TX,
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  pTxCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
                       CHARACTERISTIC_UUID_RX,
                       BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
                     );
  pRxCharacteristic->setCallbacks(new MyCallbacks());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinInterval(0x0C80);  
  pAdvertising->setMaxInterval(0x0C80);
  BLEDevice::startAdvertising();
}

void loop() {
  unsigned long currentMillis = millis();

  // 1. 唤醒并读取重量
  scale.power_up();

  if (scale.wait_ready_timeout(1500)) {
      for(int i = 0; i < 3; i++) scale.get_units(1);
      float newWeight = scale.get_units(1); 

      // 运行喝水检测状态机
      processWeightDetection(currentMillis, newWeight);
  } 
  else {
      Serial.println("读取失败: HX711 未响应");
  }

  // 2. BLE 队列数据发送
  if (deviceConnected && !messageQueue.empty() && hasTimeRecord) {
      DrinkRecord record = messageQueue.front();
      messageQueue.pop(); 
      
      char jsonBuffer[128];
      snprintf(jsonBuffer, sizeof(jsonBuffer), 
               "{\"type\": \"report drink water\", \"volume\": %d, \"time\": \"%s\"}", 
               record.volume, getAbsoluteTime(record.eventMillis).c_str());
               
      std::string msg(jsonBuffer);
      pTxCharacteristic->setValue((uint8_t*)msg.c_str(), msg.length());
      pTxCharacteristic->notify();
      
      Serial.printf("BLE 发送成功: %s\n", msg.c_str());
      delay(100); 
  }

  // 3. 断开重连控制
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); 
      pServer->startAdvertising();
      oldDeviceConnected = deviceConnected;
      Serial.println("蓝牙已断开，重新开始广播...");
  }
  
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
      Serial.println("蓝牙连接建立！");
  }

  // 4. 进入休眠
  scale.power_down(); 
  delay(200); 
}