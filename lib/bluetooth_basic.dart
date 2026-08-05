import 'dart:async';
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

/// 改写后的扫描函数：支持传入具体的 Service UUID 过滤设备
Future<List<MySerialDevice>> scanDevicesWithService({String targetServiceUuid = serviceUuid}) async {
  List<MySerialDevice> availableDevices = [];

  try {
    // Android 端动态申请蓝牙和定位权限
    if (Platform.isAndroid) {
      await [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
    }
    
    // 开始扫描，利用 withServices 根据 Service ID 过滤，持续 3 秒
    await FlutterBluePlus.startScan(
      withServices: [Guid(targetServiceUuid)],
      timeout: const Duration(seconds: 3)
    );
    
    // 等待扫描结束
    await FlutterBluePlus.isScanning.where((val) => val == false).first;
    
    for (ScanResult r in FlutterBluePlus.lastScanResults) {
      if (r.device.platformName.isNotEmpty) {
        availableDevices.add(
          MySerialDevice(
            name: r.device.platformName, 
            devicePath: r.device.remoteId.str, // MAC Address
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
  BluetoothCharacteristic? _txChar; // 写入特征 (App 发送 -> ESP32 接收)
  BluetoothCharacteristic? _rxChar; // 接收特征 (App 接收 <- ESP32 发送)
  StreamController<Uint8List>? _streamController;
  StreamSubscription? _subscription;

  @override
  Future<bool> open(String path) async {
    try {
      _device = BluetoothDevice.fromId(path);
      // 无论当前状态如何，先断开一次清理底层状态
      await _device!.disconnect();
      await Future.delayed(const Duration(milliseconds: 200));

      await _device!.connect(autoConnect: false, license: License.nonprofit);

      // 加上短暂的延时（例如 500 毫秒 - 1秒）
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
      
      // 开启通知监听数据
      await _rxChar!.setNotifyValue(true);
      _subscription = _rxChar!.onValueReceived.listen((data) {
        // 在这里收到的是 JSON 字符串的 UTF-8 字节，可以传到上层统一解析
        _streamController?.add(Uint8List.fromList(data));
      });

      return true;
    } catch (e) {
      print("BLE 连接失败: $e");
      return false;
    }
  }

  @override
  Future<void> configure({required int baudRate, required int dataBits, required int stopBits, required int parity}) async {
    // 留空即可
  }

  @override
  Future<void> writeData(Uint8List data) async {
    // 保留向 ESP32 下发数据的能力（双向扩展）
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