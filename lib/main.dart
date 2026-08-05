import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_asset.dart';
import 'ui_basic.dart'; 
import 'bluetooth_basic.dart'; 
import 'bluetooth_search_page.dart';
import 'water_record_page.dart';

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
  StreamSubscription? _bleSubscription; // 1. 保存流订阅，防止重复监听
  
  bool _isConnected = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    // 2. 将自动连接移至 initState 阶段，只在页面初始化时触发一次
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryConnect();
    });
  }

  @override
  void dispose() {
    _bleSubscription?.cancel(); // 清理流监听
    _bleChannel?.closeAndDispose(); 
    super.dispose();
  }

  /// 尝试从 SharedPreferences 读取 MAC 地址并建立蓝牙连接
  Future<void> _tryConnect() async {
    if (_isConnecting || _isConnected) return;
    
    if (mounted) {
      setState(() => _isConnecting = true);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final mac = prefs.getString('saved_ble_mac');
      
      if (mac != null && mac.isNotEmpty) {
        // 断开并释放上一次连接与监听
        await _bleSubscription?.cancel();
        _bleChannel?.closeAndDispose(); 
        
        _bleChannel = BleHardwareChannel();
        bool success = await _bleChannel!.open(mac);
        
        if (success && mounted) {
          setState(() => _isConnected = true);
          
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

  /// 处理收到的蓝牙消息
  void _handleBleMessage(Uint8List data) {
    try {
      final String jsonStr = utf8.decode(data);
      final Map<String, dynamic> message = jsonDecode(jsonStr);
      
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('收到蓝牙消息: $message'),
            duration: const Duration(milliseconds: 400),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("解析蓝牙数据失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // 移除原先在 build 方法里的 Future.microtask 自动连接逻辑

    return LiquidGlassScope(
      painter: GradientBackgroundPainter(),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: RepaintBoundary(
          key: _homepageKey,
          child: Stack(
            children: [
              // 1. 底层 UI 渐变背景
              Positioned.fill(
                child: CustomPaint(
                  painter: GradientBackgroundPainter(),
                ),
              ),
              
              // 2. 顶层内容：蓝牙连接面板
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
                      // 3. 使用 Expanded 防止横向按钮排版溢出
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: liquidButton(
                                onPressed: () {
                                  WaterRecordPage.push(context, _homepageKey);
                                },
                                child: const Text("喝水记录页", textAlign: TextAlign.center),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: liquidButton(
                                onPressed: () async {
                                  // 从搜索配对页返回后，自动尝试连接新选中的设备
                                  await BluetoothSearchPage.push(context, _homepageKey);
                                  _tryConnect();
                                },
                                child: const Text("蓝牙配对页", textAlign: TextAlign.center),
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