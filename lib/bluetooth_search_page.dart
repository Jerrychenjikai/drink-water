import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 引入你的基础 UI、模板及设备模型类文件
import 'ui_basic.dart';
import 'ui_asset.dart';
import 'secondary_page_template.dart'; 
import 'bluetooth_basic.dart'; // 包含 MySerialDevice

/// 改写后的扫描函数：支持传入具体的 Service UUID 过滤设备
Future<List<MySerialDevice>> scanDevicesWithService(String targetServiceUuid) async {
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

class BluetoothSearchPage extends StatefulWidget {
  final ui.Image snapshotImage;
  
  const BluetoothSearchPage({super.key, required this.snapshotImage});

  /// 一行代码实现页面跳转（包含截图、模糊处理、Fade 进入动画）
  static Future<void> push(BuildContext context, GlobalKey backgroundKey) {
    return FluidRoute.push(
      context: context,
      backgroundKey: backgroundKey,
      pageBuilder: (context, processedSnapshot) => BluetoothSearchPage(snapshotImage: processedSnapshot),
    );
  }

  @override
  State<BluetoothSearchPage> createState() => _BluetoothSearchPageState();
}

class _BluetoothSearchPageState extends State<BluetoothSearchPage> {
  final GlobalKey _backgroundKey = GlobalKey();
  
  // 替换成你实际的设备 Service ID
  final String _targetServiceUuid = "11111111-2222-3333-4444-555555555555"; 

  List<MySerialDevice> _scannedDevices = [];
  bool _isScanning = false;
  String? _savedMacAddress;

  @override
  void initState() {
    super.initState();
    _loadSavedDevice();
  }

  /// 读取已存的设备 MAC 码
  Future<void> _loadSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedMacAddress = prefs.getString('saved_ble_mac');
    });
  }

  /// 执行设备扫描
  Future<void> _startScan() async {
    if (_isScanning) return;
    
    setState(() {
      _isScanning = true;
      _scannedDevices.clear();
    });

    final devices = await scanDevicesWithService(_targetServiceUuid);

    if (mounted) {
      setState(() {
        _scannedDevices = devices;
        _isScanning = false;
      });
    }
  }

  /// 选中并保存设备 MAC
  Future<void> _selectDevice(MySerialDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_ble_mac', device.devicePath);
    
    setState(() {
      _savedMacAddress = device.devicePath;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已绑定设备: ${device.name} (${device.devicePath})'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FluidPageWrapper(
      snapshotImage: widget.snapshotImage,
      backgroundKey: _backgroundKey,
      topChildBuilder: (context, handlePop) => _buildTopSection(context, handlePop),
      bottomChildBuilder: (context, handlePop) => _buildBottomSection(context),
    );
  }

  /// 构建从上方滑入的内容（标题等）
  Widget _buildTopSection(BuildContext context, VoidCallback handlePop) {
    final screenSize = MediaQuery.sizeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        GestureDetector(
          onTap: handlePop, // 点击返回执行反向退出动画
          child: const Icon(Icons.arrow_back_ios, color: Colors.black87, size: 28),
        ),
        const SizedBox(height: 16),
        const Text(
          "bluetooth",
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
            color: Colors.black87,
          ),
        ),
        if (_savedMacAddress != null) ...[
          const SizedBox(height: 8),
          Text(
            "Current MAC: $_savedMacAddress",
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
        const SizedBox(height: 32),
        LiquidGlassContainer(
          height: 360,
          borderRadius: 36,
          backgroundImage: widget.snapshotImage,
          bgSize: screenSize,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Available Devices",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black),
                    ),
                    if (_isScanning)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                      )
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _scannedDevices.isEmpty && !_isScanning
                      ? const Center(
                          child: Text(
                            "No devices found.\nTap scan to search.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          itemCount: _scannedDevices.length,
                          separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.3)),
                          itemBuilder: (context, index) {
                            final device = _scannedDevices[index];
                            final isSelected = device.devicePath == _savedMacAddress;

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                device.name,
                                style: TextStyle(
                                  color: isSelected ? Colors.blue.shade800 : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                device.devicePath,
                                style: const TextStyle(color: Colors.black54, fontSize: 12),
                              ),
                              trailing: isSelected 
                                ? const Icon(Icons.check_circle, color: Colors.blue) 
                                : const Icon(Icons.bluetooth, color: Colors.black38),
                              onTap: () => _selectDevice(device),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建从下方滑入的内容（列表容器与扫描按钮）
  Widget _buildBottomSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        liquidButton(
          onPressed: _isScanning ? () {} : _startScan,
          child: Text(
            _isScanning ? "Scanning..." : "Scan Devices",
            style: const TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}