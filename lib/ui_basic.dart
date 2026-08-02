import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class LiquidGlassContainer extends StatefulWidget {
  final Widget child;
  final double width;
  final double height;
  final double borderRadius;
  final double edgeMargin; // 新增：畸变边框宽度 (像素)
  
  final ui.FragmentShader? refractionShader; 
  final ui.Image? backgroundImage;           
  final double refractionIntensity;          
  final Size bgSize; 

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.width = double.infinity,
    this.height = double.infinity,
    this.borderRadius = 32.0,
    this.edgeMargin = 30.0, // 默认边缘 30px 内发生畸变
    this.refractionShader,
    this.backgroundImage,
    this.refractionIntensity = 0.08,
    this.bgSize = const Size(1000, 1000),
  });

  @override
  State<LiquidGlassContainer> createState() => _LiquidGlassContainerState();
}


class _LiquidGlassContainerState extends State<LiquidGlassContainer> {
  final GlobalKey _containerKey = GlobalKey();
  
  // 【修改点 1】：使用 ValueNotifier 替代普通的 Offset
  final ValueNotifier<Offset> _offsetNotifier = ValueNotifier(Offset.zero);
  ScrollPosition? _scrollPosition;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachScrollListener();
  }

  void _attachScrollListener() {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable != null) {
      final position = scrollable.position;
      if (_scrollPosition != position) {
        _scrollPosition?.removeListener(_updatePosition);
        _scrollPosition = position;
        _scrollPosition?.addListener(_updatePosition);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePosition());
  }

  void _updatePosition() {
    if (!mounted) return;
    final renderBox = _containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final newOffset = renderBox.localToGlobal(Offset.zero);
      // 【修改点 2】：直接更新 Notifier 的值，彻底删掉 setState
      if (newOffset != _offsetNotifier.value) {
        _offsetNotifier.value = newOffset;
      }
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_updatePosition);
    _offsetNotifier.dispose(); // 记得释放 Notifier
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _containerKey,
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          children: [
            if (widget.refractionShader != null && widget.backgroundImage != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _RefractionPainter(
                    shader: widget.refractionShader!,
                    image: widget.backgroundImage!,
                    intensity: widget.refractionIntensity,
                    // 【修改点 3】：将 Notifier 传递给 Painter
                    offsetNotifier: _offsetNotifier, 
                    bgSize: widget.bgSize,
                    borderRadius: widget.borderRadius, 
                    edgeMargin: widget.edgeMargin/1.5,
                  ),
                ),
              ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

/// Shader 渲染器
class _RefractionPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image image;
  final double intensity;
  final ValueNotifier<Offset> offsetNotifier;
  final Size bgSize;
  final double borderRadius; // 新增
  final double edgeMargin;   // 新增

  _RefractionPainter({
    required this.shader,
    required this.image,
    required this.intensity,
    required this.offsetNotifier,
    required this.bgSize,
    required this.borderRadius,
    required this.edgeMargin,
  }) : super(repaint: offsetNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    // 0, 1: 容器尺寸
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    
    // 2, 3: 实时屏幕坐标
    final currentOffset = offsetNotifier.value; 
    shader.setFloat(2, currentOffset.dx);
    shader.setFloat(3, currentOffset.dy);

    // 4, 5: 背景尺寸
    shader.setFloat(4, bgSize.width);
    shader.setFloat(5, bgSize.height);

    // 6: 强度
    shader.setFloat(6, intensity);

    // 7, 8: 传递圆角与畸变边框像素宽度
    shader.setFloat(7, borderRadius);
    shader.setFloat(8, edgeMargin);

    shader.setImageSampler(0, image);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _RefractionPainter oldDelegate) {
    // 【修改点】：只要有任意一个影响画面的配置属性发生了改变，就返回 true 触发重绘
    return oldDelegate.shader != shader ||
        oldDelegate.image != image ||
        oldDelegate.intensity != intensity ||
        oldDelegate.bgSize != bgSize ||
        oldDelegate.borderRadius != borderRadius || // 比对圆角
        oldDelegate.edgeMargin != edgeMargin ||     // 比对畸变带宽度
        oldDelegate.offsetNotifier != offsetNotifier; // 预防性比对 Notifier 对象引用
  }
}