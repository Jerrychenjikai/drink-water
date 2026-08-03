import 'package:flutter/material.dart';
import 'dart:math';

import 'ui_basic.dart'; 

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
  bool background = false;
  final GlobalKey _backgroundKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final activePainter = background ? CheckerboardPainter() : GradientBackgroundPainter();

    // 【1】用 LiquidGlassScope 包裹整个页面
    return LiquidGlassScope(
      painter: activePainter,
      child: Scaffold(
        body: RepaintBoundary(
          key: _backgroundKey,
          child: Stack(
            children: [
              // 1. 底层 UI 背景
              Positioned.fill(
                child: CustomPaint(
                  painter: activePainter,
                ),
              ),
              
              // 2. 顶层内容
              SafeArea(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  children: [
                    const SizedBox(height: 32),
                    
                    const Text(
                      "drink water",
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                        color: Colors.black87,
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // 【2】第一个玻璃卡片：不需要传 backgroundImage 和 bgSize 了！
                    const LiquidGlassContainer(
                      height: 260,
                      borderRadius: 36,
                      refractionIntensity: 10,
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "This Week",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            Spacer(),
                            _BarChart(),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 【3】甚至可以随意放第二个玻璃卡片，共享同一显存纹理，性能无耗损！
                    const LiquidGlassContainer(
                      height: 100,
                      borderRadius: 24,
                      refractionIntensity: 15,
                      child: Center(
                        child: Text("Another Liquid Glass Card"),
                      ),
                    ),
                    
                    const SizedBox(height: 32),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.white.withOpacity(0.5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)
                        )
                      ),
                      onPressed: () {
                        showLiquidGlassPopup(
                          context: context,
                          backgroundKey: _backgroundKey,
                          width: 280,
                          height: 180,
                          borderRadius: 24.0,
                          child: const Center(
                            child: Text(
                              "hello world",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        "Show Liquid Popup",
                        style: TextStyle(fontSize: 18, color: Colors.black87),
                      ),
                    ),
                    
                    const SizedBox(height: 400), 
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            setState(() {
              background = !background;
            });
          },
        ),
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart();

  @override
  Widget build(BuildContext context) {
    final random = Random(42);
    final heights = List.generate(7, (index) => 0.2 + random.nextDouble() * 0.8);

    return SizedBox(
      height: 140,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (index) {
          return Container(
            width: 24,
            height: 140 * heights[index],
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
            ),
          );
        }),
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
        colors: [Color(0xFF8EC5FC), Color(0xFFE2F0CB)],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()..color = const Color(0xFF8EC5FC);
    final paint2 = Paint()..color = const Color(0xFFE2F0CB);
    const double gridSize = 40.0;

    for (double x = 0; x < size.width; x += gridSize) {
      for (double y = 0; y < size.height; y += gridSize) {
        bool isEven = ((x / gridSize).floor() + (y / gridSize).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, gridSize, gridSize),
          isEven ? paint1 : paint2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}