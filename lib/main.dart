import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:math';

// 引入保存了裸 Shader 渲染层 LiquidGlassContainer 的文件
import 'ui_basic.dart'; 

void main() {
  runApp(const DrinkWaterApp());
}

class DrinkWaterApp extends StatelessWidget {
  const DrinkWaterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lens Distortion Test',
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
  ui.FragmentShader? _refractionShader;
  ui.Image? _backgroundImage;

  @override
  void initState() {
    super.initState();
    _initShaderAndBackground();
  }

  Future<void> _initShaderAndBackground() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/refraction.frag');
      final shader = program.fragmentShader();

      // 这里的尺寸需要足够大，能够覆盖屏幕
      final screenSize = ui.PlatformDispatcher.instance.views.first.physicalSize /
          ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
          
      // 使用相同的 CheckerboardPainter 生成底层纹理
      final bgImage = await _createBackgroundTexture(screenSize);

      if (mounted) {
        setState(() {
          _refractionShader = shader;
          _backgroundImage = bgImage;
        });
      }
    } catch (e) {
      debugPrint('Shader 或背景图加载失败: $e');
    }
  }

  /// 利用 CheckerboardPainter 离屏生成拼接色棋盘格图像
  Future<ui.Image> _createBackgroundTexture(Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
    
    // 绘制棋盘格
    CheckerboardPainter().paint(canvas, size);
    
    final picture = recorder.endRecording();
    return await picture.toImage(size.width.toInt(), size.height.toInt());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 底层 UI 背景：使用棋盘格拼接色
          Positioned.fill(
            child: CustomPaint(
              painter: CheckerboardPainter(),
            ),
          ),
          
          // 2. 顶层内容
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              children: [
                const SizedBox(height: 32),
                
                // 为了在复杂背景上看清字，给标题加个小白底
                Container(
                  color: Colors.white70,
                  child: const Text(
                    "drink water",
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      color: Colors.black87,
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // 4. 液态玻璃卡片（用于观察边缘畸变）
                LiquidGlassContainer(
                  height: 260,
                  borderRadius: 36,
                  refractionShader: _refractionShader,
                  backgroundImage: _backgroundImage,
                  refractionIntensity: 0.08,
                  bgSize: MediaQuery.of(context).size, // 只需传入全屏背景大小
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          color: Colors.white70,
                          child: Text(
                            "This Week",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const Spacer(),
                        _buildBarChart(),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 400), 
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
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
              color: Colors.blueAccent.withOpacity(0.9), // 改为纯色以便在复杂背景下看清
              borderRadius: BorderRadius.circular(12),
            ),
          );
        }),
      ),
    );
  }
}

/// 绘制硬边缘拼接色的棋盘格 Painter
class CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()..color = const Color(0xFF8EC5FC); // 蓝色块
    final paint2 = Paint()..color = const Color(0xFFE2F0CB); // 绿色块

    const double gridSize = 40.0; // 格子大小

    for (double x = 0; x < size.width; x += gridSize) {
      for (double y = 0; y < size.height; y += gridSize) {
        // 判断奇偶性交替颜色
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