#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <queue>
#include <string>
#include <time.h>     
#include "esp_pm.h"   
#include "HX711.h"    

#define BLE_DEVICE_NAME "ESP32S3_SmartBottle"

#define SERVICE_UUID           "11111111-2222-3333-4444-555555555555" 
#define CHARACTERISTIC_UUID_RX "11111111-2222-3333-4444-555555555556" 
#define CHARACTERISTIC_UUID_TX "11111111-2222-3333-4444-555555555557" 

// HX711 引脚定义
const int HX711_DOUT = 4;
const int HX711_SCK = 5;
HX711 scale;

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// ====== 1. 结构体与队列 ======
struct DrinkRecord {
    int volume;
    unsigned long eventMillis;
};
std::queue<DrinkRecord> messageQueue;

// ====== 2. 时间同步状态 ======
bool hasTimeRecord = false;
unsigned long timeSyncMillis = 0;
time_t timeSyncEpoch = 0;

// ====== 3. 状态检测与防抖变量 ======
float currentWeight = 0.0;
float lastStableWeight = 0.0;
unsigned long lastWeightChangeTime = 0;

const float WEIGHT_THRESHOLD = 3.0;      
const unsigned long STABLE_DELAY = 2000; 

// ======================================

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue().c_str();

      if (rxValue.length() > 0) {
        Serial.print("收到来自 App 的指令: ");
        Serial.println(rxValue.c_str());

        if (rxValue.indexOf("\"current time\"") > 0) {
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
    }
};

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

void setup() {
  Serial.begin(115200);
  
  setenv("TZ", "GMT0", 1);
  tzset();

  esp_pm_config_esp32s3_t pm_config = {
      .max_freq_mhz = 160,
      .min_freq_mhz = 10,   
      .light_sleep_enable = true 
  };
  esp_pm_configure(&pm_config);
  
  scale.begin(HX711_DOUT, HX711_SCK);
  scale.set_scale(228.0); 
  delay(500);
  scale.tare();           
  Serial.println("HX711 初始化并去皮完成...");

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

  // ====== 1. 唤醒 HX711 ======
  scale.power_up();

  // 等待数据准备就绪。HX711 唤醒后大概需要 100ms 才能出第一个数据。
  // 设置 150ms 超时，防止发生引脚故障时程序死锁。
  if (scale.wait_ready_timeout(500)) {
      for(int i=0;i<3;i++) scale.get_units(1);
      float newWeight = scale.get_units(1); 
      Serial.printf("当前重量：%.10f\n", newWeight);

      long rawValue = scale.read();
      Serial.printf("HX711 原始读数：%ld\n", rawValue);

      // 物理防抖逻辑
      if (abs(newWeight - currentWeight) > WEIGHT_THRESHOLD) {
          currentWeight = newWeight;
          lastWeightChangeTime = currentMillis; 
      } 
      else {
          if (currentMillis - lastWeightChangeTime > STABLE_DELAY) {
              if (abs(currentWeight - lastStableWeight) > WEIGHT_THRESHOLD) {
                  lastStableWeight = currentWeight;
                  
                  if (currentWeight > 0) {
                      messageQueue.push({(int)currentWeight, currentMillis});
                      Serial.printf("检测到重量稳定！推入队列: %d, 相对时间: %lu\n", (int)currentWeight, currentMillis);
                  }
              }
          }
      }
  } else {
      Serial.println("读取失败: HX711 未响应");
  }

  // ====== 2. 数据发送逻辑 ======
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

  // ====== 3. 断开重连 ======
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); 
      pServer->startAdvertising();
      oldDeviceConnected = deviceConnected;
      Serial.println("蓝牙已断开，重新开始广播...");
  }
  
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
      Serial.println("蓝牙连接建立！准备推送积压队列...");
  }

  // ====== 4. 断电休眠 ======
  // 将 HX711 掉电，功耗降至 1uA 以下
  scale.power_down(); 
  
  // 延长 delay，让 ESP32 拥有长达 200ms 的完整空闲时间进入 Light-sleep
  delay(200); 
}