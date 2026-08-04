import 'package:flutter/material.dart';
import 'dart:math';

import 'ui_basic.dart'; 
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
  final GlobalKey _backgroundKey = GlobalKey();
  final WaterTrackingService _waterTracking = WaterTrackingService();
  
  // 保存异步 Fetch 任务，避免每次 build 重复拉取健康数据
  late Future<List<double>> _weeklyWaterFuture;

  @override
  void initState() {
    super.initState(); // ✅ 修正：必须调用 super.initState()
    _initHealthData();
  }

  void _initHealthData() async {
    // 异步申请权限，然后获取周数据
    bool granted = await _waterTracking.requestPermissions();
    if (granted) {
      setState(() {
        _weeklyWaterFuture = _waterTracking.getPastWeekDailyWaterIntake();
      });
    } else {
      setState(() {
        _weeklyWaterFuture = Future.value(List.filled(7, 0.0));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePainter = GradientBackgroundPainter();

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
                    
                    // 【玻璃卡片 + 异步图表】
                    LiquidGlassContainer(
                      height: 260,
                      borderRadius: 36,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "This Week",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            const Spacer(),
                            // ✅ 修正：使用 FutureBuilder 优雅加载异步数据
                            FutureBuilder<List<double>>(
                              future: _weeklyWaterFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const SizedBox(
                                    height: 140,
                                    child: Center(
                                      child: CircularProgressIndicator.adaptive(),
                                    ),
                                  );
                                }
                                final data = snapshot.data ?? List.filled(7, 0.0);
                                return WaterBarChart(waterData: data);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    const LiquidGlassContainer(
                      height: 100,
                      borderRadius: 24,
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
                          borderRadius: BorderRadius.circular(16),
                        ),
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
      ),
    );
  }
}

class WaterBarChart extends StatelessWidget {
  /// 接收过去 7 天的饮水量列表（单位：ml）
  final List<double> waterData;

  /// 目标饮水量（用于计算柱状图满格比例，默认 2000 ml）
  final double targetWater;

  const WaterBarChart({
    super.key,
    required this.waterData,
    this.targetWater = 2000.0,
  });

  @override
  Widget build(BuildContext context) {
    // 确保数据长度不为 0，若为空则显示默认 7 个 0
    final displayData = waterData.length == 7 ? waterData : List.filled(7, 0.0);

    // 动态算出 7 天中的最大值，确保图表的比例上限至少等于 targetWater
    final double maxVal = max(
      targetWater,
      displayData.reduce((curr, next) => curr > next ? curr : next),
    );

    const double chartHeight = 140.0;

    return SizedBox(
      height: chartHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (index) {
          final double amount = displayData[index];

          // 计算比例（0.0 ~ 1.0）
          final double ratio = maxVal > 0 ? (amount / maxVal).clamp(0.0, 1.0) : 0.0;

          // 计算对应像素高度（最少保留 4px 避免完全看不到）
          final double barHeight = max(chartHeight * ratio, 4.0);

          return Tooltip(
            message: '${amount.toStringAsFixed(0)} ml', // 长按显示具体数值
            child: Container(
              width: 24,
              height: barHeight,
              decoration: BoxDecoration(
                // 达到了目标水量显示深蓝，未达到显示浅蓝
                color: amount >= targetWater
                    ? Colors.blueAccent
                    : Colors.blueAccent.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
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