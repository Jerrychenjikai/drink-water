import 'package:flutter/material.dart';
import 'dart:math';

import 'ui_basic.dart'; 
import 'health_basic.dart';
import 'water_record_page.dart';
import 'bluetooth_search_page.dart';
import 'ui_asset.dart';

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

  @override
  void initState() {
    super.initState(); // ✅ 修正：必须调用 super.initState()
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
              // 1. 底层 UI 背景
              Positioned.fill(
                child: CustomPaint(
                  painter: GradientBackgroundPainter(),
                ),
              ),
              
              // 2. 顶层内容
              SafeArea(
                child: Center(
                  child: Column(
                    children: [
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      liquidButton(
                        onPressed: () {
                          // 一行代码轻松跳转并带截图动画
                          WaterRecordPage.push(context, _homepageKey);
                        },
                        child: const Text("跳转到喝水记录页"),
                      ),
                      liquidButton(
                        onPressed: () {
                          // 一行代码轻松跳转并带截图动画
                          BluetoothSearchPage.push(context, _homepageKey);
                        },
                        child: const Text("跳转到蓝牙配对页"),
                      ),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
                      const Text('something'),
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

/// 背景绘制器
class GradientBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.fromARGB(255, 1, 145, 255), // 深邃暗夜蓝 (奠定强对比基调)
          Color(0xFF00C9FF), 
          Color(0xFF00F2FE), // 极光电光青 (瞬间拉高明度)
          Color.fromARGB(255, 141, 252, 153), // 荧光薄荷绿 (剧烈拉开色相)
          Color.fromARGB(255, 0, 255, 115), // 浓郁翡翠绿 (加深色彩饱满度)
        ],
        // 通过密集配置 stops，让颜色在局部像素范围内剧烈跃迁
        stops: [0.0, 0.25, 0.45, 0.75, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}