import 'dart:async';
import 'dart:convert'; // 新增：用于 JSON 编码
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // 引入蓝牙库
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

// 使用完全自定义的 UUID 替换原 Nordic UART UUID
const String serviceUuid = "11111111-2222-3333-4444-555555555555";
// 注意：App 的接收 (Notify) 对应的是 ESP32 的发送 (TX)
const String rxUuid      = "11111111-2222-3333-4444-555555555557"; 
// App 的发送 (Write) 对应的是 ESP32 的接收 (RX)
const String txUuid      = "11111111-2222-3333-4444-555555555556"; 

/// 统一的串行设备模型
class MySerialDevice {
  final String name;
  final String devicePath; // BLE MAC

  MySerialDevice({
    required this.name, 
    required this.devicePath, 
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MySerialDevice &&
          runtimeType == other.runtimeType &&
          devicePath == other.devicePath;

  @override
  int get hashCode => devicePath.hashCode;
}

/// 发送当前时间到单片机的独立函数
Future<void> syncCurrentTimeToDevice(IHardwareChannel channel) async {
  // 生成当前标准 ISO8601 时间（如：2026-08-17T22:47:49Z）
  final now = DateTime.now().toUtc();
  final isoStr = "${now.toIso8601String().split('.')[0]}Z"; 
  
  final payload = jsonEncode({
    'type': 'current time',
    'time': isoStr
  });
  
  // 将 JSON 字符串转为 UTF-8 字节并写入通道
  await channel.writeData(Uint8List.fromList(utf8.encode(payload)));
}

/// 改写后的扫描函数：支持传入具体的 Service UUID 过滤设备
Future<List<MySerialDevice>> scanDevicesWithService({String targetServiceUuid = serviceUuid}) async {
  List<MySerialDevice> availableDevices = [];
  // ... (保留原 scanDevicesWithService 代码不变)[cite: 1]
  try {
    if (Platform.isAndroid) {
      await [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
    }
    
    await FlutterBluePlus.startScan(
      withServices: [Guid(targetServiceUuid)],
      timeout: const Duration(seconds: 3)
    );
    
    await FlutterBluePlus.isScanning.where((val) => val == false).first;
    
    for (ScanResult r in FlutterBluePlus.lastScanResults) {
      if (r.device.platformName.isNotEmpty) {
        availableDevices.add(
          MySerialDevice(
            name: r.device.platformName, 
            devicePath: r.device.remoteId.str, 
          ),
        );
      }
    }
  } catch (e) {
    print("扫描特定 Service BLE 设备失败: $e");
  }

  return availableDevices;
}

abstract class IHardwareChannel {
  Future<bool> open(String path);
  Future<void> configure({required int baudRate, required int dataBits, required int stopBits, required int parity});
  Future<void> writeData(Uint8List data);
  Future<void> closeAndDispose();
  Stream<Uint8List> get listenStream;
}

class BleHardwareChannel implements IHardwareChannel {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;
  StreamController<Uint8List>? _streamController;
  StreamSubscription? _subscription;

  @override
  Future<bool> open(String path) async {
    try {
      _device = BluetoothDevice.fromId(path);
      await _device!.disconnect();
      await Future.delayed(const Duration(milliseconds: 200));

      await _device!.connect(autoConnect: false, license: License.nonprofit);
      await Future.delayed(const Duration(milliseconds: 500)); 

      List<BluetoothService> services = await _device!.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == txUuid) {
              _txChar = char;
            } else if (char.uuid.toString().toLowerCase() == rxUuid) {
              _rxChar = char;
            }
          }
        }
      }

      if (_txChar == null || _rxChar == null) {
        await _device!.disconnect();
        return false;
      }

      _streamController = StreamController<Uint8List>.broadcast();
      
      await _rxChar!.setNotifyValue(true);
      _subscription = _rxChar!.onValueReceived.listen((data) {
        _streamController?.add(Uint8List.fromList(data));
      });

      return true;
    } catch (e) {
      print("BLE 连接失败: $e");
      return false;
    }
  }

  @override
  Future<void> configure({required int baudRate, required int dataBits, required int stopBits, required int parity}) async {}

  @override
  Future<void> writeData(Uint8List data) async {
    if (_txChar != null) await _txChar!.write(data, withoutResponse: true);
  }

  @override
  Future<void> closeAndDispose() async {
    await _subscription?.cancel();
    await _streamController?.close();
    await _device?.disconnect();
    _device = null;
  }

  @override
  Stream<Uint8List> get listenStream => _streamController?.stream ?? const Stream.empty();
}