import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 根据你的实际文件结构调整引用
import 'ui_asset.dart';
import 'ui_basic.dart'; 
import 'bluetooth_basic.dart'; // 包含 BleHardwareChannel 定义
import 'bluetooth_search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey _homepageKey = GlobalKey();
  
  BleHardwareChannel? _bleChannel;
  bool _isConnected = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _bleChannel?.closeAndDispose(); // 页面销毁时断开蓝牙释放资源
    super.dispose();
  }

  /// 尝试从 SharedPreferences 读取 MAC 地址并建立蓝牙连接
  Future<void> _tryConnect() async {
    // 防抖与防重入校验
    if (_isConnecting || _isConnected) return;
    
    if (mounted) {
      setState(() {
        _isConnecting = true;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final mac = prefs.getString('saved_ble_mac');
      
      if (mac != null && mac.isNotEmpty) {
        // 创建硬件通道实例
        _bleChannel?.closeAndDispose(); 
        _bleChannel = BleHardwareChannel();
        
        bool success = await _bleChannel!.open(mac);
        
        if (success && mounted) {
          setState(() {
            _isConnected = true;
          });
          
          // 监听蓝牙发来的消息
          _bleChannel!.listenStream.listen((data) {
            _handleBleMessage(data);
          }, onDone: () {
            if (mounted) setState(() => _isConnected = false);
          }, onError: (e) {
            if (mounted) setState(() => _isConnected = false);
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
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  /// 处理收到的蓝牙消息
  void _handleBleMessage(Uint8List data) {
    try {
      // 将接收到的 Uint8List 转换为 UTF-8 字符串，并解析为 Map
      final String jsonStr = utf8.decode(data);
      final Map<String, dynamic> message = jsonDecode(jsonStr);
      
      // 处理消息的回调先空着...

      // 每次收到消息都弹一个持续0.4s的 ScaffoldMessenger
      if (mounted) {
        // 清除旧的 SnackBar 避免堆叠排队延迟
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
    // 每次 rebuild 的时候，如果未连接且没有在连接中，则读取 mac 并尝试连接
    // 使用 Future.microtask 避免在 build 阶段直接触发 setState 导致报错
    if (!_isConnected && !_isConnecting) {
      Future.microtask(() => _tryConnect());
    }

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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: LiquidGlassContainer(
                      width: double.infinity,
                      height: 380,
                      borderRadius: 36,
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // 蓝牙状态图标
                            Icon(
                              _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                              size: 72,
                              color: _isConnected ? Colors.blue.shade800 : Colors.black54,
                            ),
                            const SizedBox(height: 24),
                            
                            // 蓝牙状态文本
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
                            
                            // 未连接时，给出手动连接按钮
                            if (!_isConnected)
                              liquidButton(
                                onPressed: () async {
                                  // 跳转到蓝牙搜索页，带 FluidRoute 模糊截图动画
                                  await BluetoothSearchPage.push(context, _homepageKey);
                                  // 当搜索页 Pop 弹回时，尝试发起新一轮连接
                                  _tryConnect();
                                },
                                child: Text(
                                  _isConnecting ? "连接中..." : "手动连接 / 搜索",
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 保留原有的背景绘制器
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