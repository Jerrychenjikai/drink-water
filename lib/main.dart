import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // 【新增】引入 flutter_blue_plus 以监听底层连接状态

import 'ui_asset.dart';
import 'ui_basic.dart'; 
import 'bluetooth_basic.dart'; 
import 'bluetooth_search_page.dart';
import 'water_record_page.dart';
import 'health_basic.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  preloadLiquidGlassShader();
  runApp(const DrinkWaterApp());
}

class DrinkWaterApp extends StatelessWidget {
  const DrinkWaterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drink Water',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: '.SF Pro Display', 
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey _homepageKey = GlobalKey();
  
  BleHardwareChannel? _bleChannel;
  StreamSubscription? _bleSubscription;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSubscription; // 【新增】用于监听设备连接状态
  
  final WaterTrackingService _waterTracking = WaterTrackingService();
  
  bool _isConnected = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryConnect();
    });
  }

  @override
  void dispose() {
    _bleSubscription?.cancel(); 
    _deviceStateSubscription?.cancel(); // 【新增】释放状态监听
    _bleChannel?.closeAndDispose(); 
    super.dispose();
  }

  Future<void> _tryConnect() async {
    if (_isConnecting || _isConnected) return;
    
    if (mounted) {
      setState(() => _isConnecting = true);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final mac = prefs.getString('saved_ble_mac');
      
      if (mac != null && mac.isNotEmpty) {
        await _bleSubscription?.cancel();
        await _deviceStateSubscription?.cancel(); // 【新增】断开前清理旧的状态监听
        _bleChannel?.closeAndDispose(); 
        
        _bleChannel = BleHardwareChannel();
        bool success = await _bleChannel!.open(mac);
        
        if (success && mounted) {
          setState(() => _isConnected = true);

          await syncCurrentTimeToDevice(_bleChannel!);
          
          // 监听蓝牙数据流
          _bleSubscription = _bleChannel!.listenStream.listen(
            (data) {
              _handleBleMessage(data);
            },
            onDone: () {
              if (mounted) setState(() => _isConnected = false);
            },
            onError: (e) {
              if (mounted) setState(() => _isConnected = false);
            },
          );

          // 【新增】利用 flutter_blue_plus 监听当前 MAC 设备的底层连接状态
          // 当单片机断电、重启或超出距离时，会自动触发断开事件并更新 UI
          _deviceStateSubscription = BluetoothDevice.fromId(mac).connectionState.listen((state) {
            if (state == BluetoothConnectionState.disconnected) {
              if (mounted) setState(() => _isConnected = false);
            }
          });
        } else {
          if (mounted) setState(() => _isConnected = false);
        }
      }
    } catch (e) {
      debugPrint("蓝牙连接异常: $e");
      if (mounted) setState(() => _isConnected = false);
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _handleBleMessage(Uint8List data) async {
    try {
      final String jsonStr = utf8.decode(data);
      final Map<String, dynamic> message = jsonDecode(jsonStr);
      
      double? milliliters;
      if (message.containsKey('volume')) {
        milliliters = (message['volume'] as num).toDouble();
      } else if (message.containsKey('ml')) {
        milliliters = (message['ml'] as num).toDouble();
      }

      DateTime? drinkTime;
      if (message.containsKey('time')) {
        try {
          // 硬件端发送的时间带有 'Z' (如 "2026-08-20T10:02:19Z")，说明是 UTC 时间[cite: 3]
          // DateTime.parse 会自动识别它，随后调用 toLocal() 转换为设备所在时区
          drinkTime = DateTime.parse(message['time']).toLocal();
        } catch (e) {
          debugPrint("解析时间字段失败: $e");
        }
      }
      // ===========================================

      bool recordSuccess = false;

      if (milliliters != null && milliliters > 0) {
        bool granted = await _waterTracking.requestPermissions();
        if (granted) {
          // === 【修改】将解析后的时间传递给记录方法 ===
          recordSuccess = await _waterTracking.recordWaterIntake(
            milliliters: milliliters,
            timestamp: drinkTime,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        showLiquidGlassSnackBar(context, Text(
            milliliters != null 
              ? '收到蓝牙消息: $message\n自动同步健康数据: ${recordSuccess ? "成功" : "失败"}'
              : '收到蓝牙消息: $message'
          ),
        );
      }
    } catch (e) {
      debugPrint("解析蓝牙数据失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlassScope(
      painter: GradientBackgroundPainter(),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: RepaintBoundary(
          key: _homepageKey,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: GradientBackgroundPainter(),
                ),
              ),
              
              SafeArea(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: LiquidGlassContainer(
                          width: double.infinity,
                          height: 380,
                          borderRadius: 36,
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                                    size: 72,
                                    color: _isConnected ? Colors.blue.shade800 : Colors.black54,
                                  ),
                                  const SizedBox(height: 24),
                                  
                                  Text(
                                    _isConnecting 
                                        ? "正在连接设备..." 
                                        : (_isConnected ? "已成功连接" : "未连接设备"),
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: _isConnected ? Colors.blue.shade900 : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 48),
                                  
                                  if (!_isConnected)
                                    liquidButton(
                                      onPressed: _tryConnect,
                                      child: Text(
                                        _isConnecting ? "连接中..." : "再次尝试连接",
                                        style: const TextStyle(
                                          fontSize: 18,
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: liquidButton(
                                onPressed: () {
                                  WaterRecordPage.push(context, _homepageKey);
                                },
                                child: const Text("喝水记录页", textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: liquidButton(
                                onPressed: () async {
                                  await BluetoothSearchPage.push(context, _homepageKey);
                                  _tryConnect();
                                },
                                child: const Text("蓝牙配对页", textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GradientBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.fromARGB(255, 1, 145, 255),
          Color(0xFF00C9FF), 
          Color(0xFF00F2FE), 
          Color.fromARGB(255, 141, 252, 153), 
          Color.fromARGB(255, 0, 255, 115),
        ],
        stops: [0.0, 0.25, 0.45, 0.75, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}