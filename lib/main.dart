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
        showLiquidGlassSnackBar(
          context: context, 
          content: Text(
            milliliters != null 
              ? 'Bluetooth msg: $message\nsync to health app: ${recordSuccess ? "success" : "fail"}'
              : 'Bluetooth msg: $message'
          ),
          backgroundKey: _homepageKey,
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
      snapshotConfig: const SnapshotConfig(
        blurSigma: 4.0,       // 模糊程度：数值越小，背景图案越清晰
        darkenOpacity: 0.05,  // 暗度调节（保持默认即可）
      ),
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
                                        ? "Connecting" 
                                        : (_isConnected ? "Connected" : "Disconnected"),
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: _isConnected ? Colors.blue.shade900 : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 48),
                                  
                                  if (!_isConnected && !_isConnecting)
                                    liquidButton(
                                      onPressed: _tryConnect,
                                      child: Text(
                                        "Connect",
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
                                child: const Text("Hydration", textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: liquidButton(
                                onPressed: () async {
                                  await BluetoothSearchPage.push(context, _homepageKey);
                                  _tryConnect();
                                },
                                child: const Text("Bluetooth Pairing", textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.bold)),
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

import 'package:flutter/material.dart';

class GradientBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // ==========================================
    // 1. 铺满不透明的白色底
    // ==========================================
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(bgRect, bgPaint);

    // ==========================================
    // 2. 绘制 80% 的水和波浪线
    // ==========================================
    final waterTop = size.height * 0.2; // 顶部留白 20%
    final waveHeight = size.height * 0.02; // 波浪起伏幅度
    final waveWidth = size.width / 2; // 单个波浪的宽度

    // --- 后层波浪 (浅色，增加层次感) ---
    final backWavePath = Path()
      ..moveTo(0, waterTop + waveHeight)
      ..quadraticBezierTo(waveWidth * 0.5, waterTop + waveHeight * 2.5, waveWidth, waterTop + waveHeight)
      ..quadraticBezierTo(waveWidth * 1.5, waterTop - waveHeight * 0.5, size.width, waterTop + waveHeight)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final backWavePaint = Paint()
      ..color = const Color(0xFF81D4FA).withOpacity(0.6); // 极浅的蓝
    canvas.drawPath(backWavePath, backWavePaint);

    // --- 前层波浪 (主水体) ---
    final frontWavePath = Path()
      ..moveTo(0, waterTop)
      ..quadraticBezierTo(waveWidth * 0.5, waterTop - waveHeight * 1.5, waveWidth, waterTop)
      ..quadraticBezierTo(waveWidth * 1.5, waterTop + waveHeight * 1.5, size.width, waterTop)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    // 模拟水的深浅渐变
    final waterPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF29B6F6), // 较浅的蓝
          Color(0xFF0277BD), // 较深的蓝
        ],
      ).createShader(Rect.fromLTWH(0, waterTop, size.width, size.height - waterTop));
      
    canvas.drawPath(frontWavePath, waterPaint);

    // ==========================================
    // 3. 绘制卡通气泡（实心浅蓝 + 白色高光点）
    // ==========================================
    // 实心半透明浅蓝色气泡主体（模拟水下通透感）
    final bubblePaint = Paint()
      ..color = const Color(0xFFB3E5FC).withOpacity(0.55) 
      ..style = PaintingStyle.fill;

    // 纯白色高光点 Paint，提升立体感
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.fill;

    // 辅助函数：画带白色高光的实心气泡
    void drawBubble(Offset center, double radius) {
      // 1. 绘制实心浅蓝气泡
      canvas.drawCircle(center, radius, bubblePaint);

      // 2. 在气泡左上角绘制白色高光点
      canvas.drawCircle(
        Offset(center.dx - radius * 0.35, center.dy - radius * 0.35),
        radius * 0.25, // 高光点大小等比例缩放
        highlightPaint,
      );
    }

    // 定义气泡数据：[x坐标比例, y坐标比例, 半径比例]
    // 参考了提供的图片，采用"大带小"的聚落式分布，避免均匀排列显得死板
    final bubbleData = [
      // 左上群落
      [0.28, 0.38, 0.05],
      [0.38, 0.40, 0.025],
      
      // 右上群落
      [0.75, 0.35, 0.045],
      [0.66, 0.31, 0.02],
      
      // 核心区域（居中偏大）
      [0.45, 0.55, 0.075],
      [0.58, 0.48, 0.035],
      
      // 左下群落
      [0.32, 0.68, 0.065],
      [0.42, 0.72, 0.025],
      [0.25, 0.78, 0.035],
      
      // 右下群落
      [0.78, 0.65, 0.055],
      [0.68, 0.72, 0.025],
      [0.85, 0.82, 0.03],
      
      // 底部零星点缀
      [0.55, 0.88, 0.04],
      [0.18, 0.90, 0.025],
    ];

    // 遍历绘制所有气泡
    for (final data in bubbleData) {
      final dx = size.width * data[0];
      final dy = size.height * data[1];
      final radius = size.width * data[2];
      drawBubble(Offset(dx, dy), radius);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}