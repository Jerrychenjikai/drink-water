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
  
  // 记录上一次的窗口尺寸，用于对比是否发生了变化
  Size _lastSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _loadShader(); // 仅加载一次 Shader 程序
  }

  @override
  void dispose() {
    _backgroundImage?.dispose(); // 页面销毁时释放背景图片资源
    super.dispose();
  }

  /// 一次性加载 Shader 程序
  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/refraction.frag');
      final shader = program.fragmentShader();

      if (mounted) {
        setState(() {
          _refractionShader = shader;
        });
      }
    } catch (e) {
      debugPrint('Shader 加载失败: $e');
    }
  }

  /// 根据新尺寸重新生成背景图片纹理
  Future<void> _updateBackgroundTexture(Size size) async {
    if (size.width <= 0 || size.height <= 0) return;

    final bgImage = await _createBackgroundTexture(size);

    if (mounted) {
      setState(() {
        // 释放上一张图片的显存，防止内存泄漏
        _backgroundImage?.dispose();
        _backgroundImage = bgImage;
      });
    } else {
      bgImage.dispose();
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
    // 获取当前窗口/屏幕尺寸
    final screenSize = MediaQuery.sizeOf(context);

    // 检测窗口尺寸是否发生改变（包括初始化尺寸变化）
    if (_lastSize != screenSize) {
      _lastSize = screenSize;
      
      // 在当前帧渲染完成后重新生成背景图片，避免在 build 过程中直接 setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateBackgroundTexture(screenSize);
      });
    }

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
                
                // 液态玻璃卡片
                LiquidGlassContainer(
                  height: 260,
                  borderRadius: 36,
                  refractionShader: _refractionShader,
                  backgroundImage: _backgroundImage,
                  refractionIntensity: 10,
                  bgSize: screenSize, // 传入最新的全屏背景大小
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
              color: Colors.blueAccent.withOpacity(0.9),
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