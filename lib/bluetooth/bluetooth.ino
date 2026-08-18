#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <queue>
#include <string>
#include <time.h>     // 用于标准时间处理
#include "esp_pm.h"   // [新增] 用于配置电源管理模式

#define BLE_DEVICE_NAME "ESP32S3_SmartBottle"

// 与 Flutter 端匹配的自定义 UUID
#define SERVICE_UUID           "11111111-2222-3333-4444-555555555555" 
#define CHARACTERISTIC_UUID_RX "11111111-2222-3333-4444-555555555556" // ESP32 接收 (对应 App Tx)
#define CHARACTERISTIC_UUID_TX "11111111-2222-3333-4444-555555555557" // ESP32 发送 (对应 App Rx)

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
unsigned long lastTriggerTime = 0;

// ====== 2. 时间同步状态 ======
bool hasTimeRecord = false;
unsigned long timeSyncMillis = 0;
time_t timeSyncEpoch = 0;
// ======================================

// 监听蓝牙连接状态的回调类
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
    }
};

// 监听蓝牙接收数据的回调类
class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue().c_str();

      if (rxValue.length() > 0) {
        Serial.print("收到来自 App 的指令: ");
        Serial.println(rxValue.c_str());

        // 解析包含 current time 的 JSON，获取同步时间点
        if (rxValue.indexOf("\"current time\"") > 0) {
            int timeIndex = rxValue.indexOf("\"time\"");
            if (timeIndex > 0) {
                // 定位 ISO8601 时间字符串并简单裁剪解析
                int start = rxValue.indexOf("\"", timeIndex + 6) + 1;
                int end = rxValue.indexOf("\"", start);

                if (start > 0 && end > start) {
                    String tStr = rxValue.substring(start, end);
                    int y, mo, d, h, m, s;
                    // 通过 sscanf 将类似 2026-08-17T22:47:49Z 的文本转为数字
                    if (sscanf(tStr.c_str(), "%d-%d-%dT%d:%d:%dZ", &y, &mo, &d, &h, &m, &s) == 6) {
                        struct tm t = {0};
                        t.tm_year = y - 1900;
                        t.tm_mon = mo - 1;
                        t.tm_mday = d;
                        t.tm_hour = h;
                        t.tm_min = m;
                        t.tm_sec = s;
                        
                        timeSyncEpoch = mktime(&t);    // 记录基准绝对时间秒数
                        timeSyncMillis = millis();     // 记录接收基准时的相对开机时间（毫秒）
                        hasTimeRecord = true;
                        
                        Serial.println("MCU 已成功同步绝对时间！");
                    }
                }
            }
        }
      }
    }
};

// ====== 3. 将任意记录时的 millis 转换为绝对时间 ======
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
  
  // 确保时区设置为 GMT 以防 mktime 计算偏移出错
  setenv("TZ", "GMT0", 1);
  tzset();

  // [新增] 配置底层电源管理，允许动态调频和进入自动 Light-sleep
  esp_pm_config_esp32c3_t pm_config = {
      .max_freq_mhz = 160,
      .min_freq_mhz = 10,   // 空闲时 CPU 降频至 10MHz
      .light_sleep_enable = true // 允许自动进入 Light-sleep
  };
  esp_pm_configure(&pm_config);
  
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
  
  // [修改] 降低蓝牙广播频率，间隔设为 2 秒
  // 蓝牙时间单位为 0.625ms，因此 2000ms / 0.625 = 3200 (十六进制为 0x0C80)
  pAdvertising->setMinInterval(0x0C80);  
  pAdvertising->setMaxInterval(0x0C80);
  
  BLEDevice::startAdvertising();
}

void loop() {
  unsigned long currentMillis = millis();

  // 1. 数据采集与压栈完全独立，不受任何时间同步限制
  if (currentMillis - lastTriggerTime >= 5000) {
      lastTriggerTime = currentMillis;
      int randomVolume = random(50, 300); 
      messageQueue.push({randomVolume, currentMillis});
      Serial.printf("数据已压入队列，水量: %d, 相对时间: %lu\n", randomVolume, currentMillis);
  }

  // 2. 发送逻辑：只有在蓝牙连接且【拥有时间基准】时，才出栈发送
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
      // 发送时保持短延时避免 App 漏包
      delay(100); 
  }

  // 3. 处理蓝牙断开重连的逻辑
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

  // [新增] 让出 CPU 控制权，触发 FreeRTOS 调度
  // 这允许系统在空闲时关闭射频（Modem-sleep）或暂停 CPU（Light-sleep）
  delay(50); 
}