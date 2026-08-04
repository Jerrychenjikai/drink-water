#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <queue>
#include <string>

#define BLE_DEVICE_NAME "ESP32S3_SmartBottle"

// 与 Flutter 端匹配的自定义 UUID
#define SERVICE_UUID           "11111111-2222-3333-4444-555555555555" 
#define CHARACTERISTIC_UUID_RX "11111111-2222-3333-4444-555555555556" // ESP32 接收 (对应 App Tx)
#define CHARACTERISTIC_UUID_TX "11111111-2222-3333-4444-555555555557" // ESP32 发送 (对应 App Rx)

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// 数据发送队列
std::queue<std::string> messageQueue;
unsigned long lastTriggerTime = 0;

// 监听蓝牙连接状态的回调类[cite: 1]
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
    }
};

// 监听蓝牙接收数据的回调类[cite: 1]
class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue();
      if (rxValue.length() > 0) {
        // 此处保留扩展双向传输的能力，可以接收 App 下发的控制指令
        Serial.print("收到来自 App 的指令: ");
        Serial.println(rxValue.c_str());
      }
    }
};

// 模拟生成 ISO8601 格式的时间戳
std::string getSimulatedTime() {
    unsigned long sec = millis() / 1000;
    char timeBuf[32];
    // 使用假定的基准时间 2026-08-03T21:22:53 叠加运行秒数
    snprintf(timeBuf, sizeof(timeBuf), "2026-08-03T21:%02lu:%02luZ", 
             (22 + (sec / 60)) % 60, (53 + sec) % 60);
    return std::string(timeBuf);
}

void setup() {
  Serial.begin(115200);
  while (!Serial) { delay(10); }

  BLEDevice::init(BLE_DEVICE_NAME);[cite: 1]
  
  pServer = BLEDevice::createServer();[cite: 1]
  pServer->setCallbacks(new MyServerCallbacks());[cite: 1]

  BLEService *pService = pServer->createService(SERVICE_UUID);[cite: 1]

  // 创建发送特征值 (TX)，允许通知 (Notify)[cite: 1]
  pTxCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID_TX,
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  pTxCharacteristic->addDescriptor(new BLE2902());[cite: 1]

  // 创建接收特征值 (RX)，允许写入 (Write)[cite: 1]
  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
                       CHARACTERISTIC_UUID_RX,
                       BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
                     );
  pRxCharacteristic->setCallbacks(new MyCallbacks());[cite: 1]

  pService->start();[cite: 1]
  pServer->getAdvertising()->start();[cite: 1]
}

void loop() {
  unsigned long currentMillis = millis();

  // 1. 每过 5 秒，不论蓝牙是否配对，往发送队列里加入信息
  if (currentMillis - lastTriggerTime >= 5000) {
      lastTriggerTime = currentMillis;
      
      int randomVolume = random(50, 300); // 随机生成饮水量 50~300ml
      char jsonBuffer[128];
      snprintf(jsonBuffer, sizeof(jsonBuffer), 
               "{\"type\": \"report drink water\", \"volume\": %d, \"time\": \"%s\"}", 
               randomVolume, getSimulatedTime().c_str());
               
      messageQueue.push(std::string(jsonBuffer));
      Serial.printf("数据已压入队列: %s\n", jsonBuffer);
  }

  // 2. 如果蓝牙成功配对，清空（发送出）队列信息
  if (deviceConnected && !messageQueue.empty()) {
      std::string msg = messageQueue.front();
      messageQueue.pop(); // 弹出已处理的消息
      
      pTxCharacteristic->setValue((uint8_t*)msg.c_str(), msg.length());
      pTxCharacteristic->notify();
      
      Serial.printf("BLE 发送成功: %s\n", msg.c_str());
      
      // 注意在信息之间留一些缓冲时间以应对蓝牙库底层的波动
      // 这里我使用了 100ms 的延时，能有效避免拥塞掉包
      delay(100); 
  }

  // 3. 处理蓝牙断开重连的逻辑
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); // 留出时间让蓝牙堆栈准备好
      pServer->startAdvertising(); // 重新开始广播，允许新的连接
      oldDeviceConnected = deviceConnected;
      Serial.println("蓝牙已断开，重新开始广播...");
  }
  
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
      Serial.println("蓝牙连接建立！准备推送积压队列...");
  }
}