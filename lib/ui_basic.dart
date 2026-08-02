import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class LiquidGlassContainer extends StatefulWidget {
  final Widget child;
  final double width;
  final double height;
  final double borderRadius;
  
  final ui.FragmentShader? refractionShader; 
  final ui.Image? backgroundImage;           
  final double refractionIntensity;          
  final Size bgSize; // 背景全屏尺寸

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.width = double.infinity,
    this.height = double.infinity,
    this.borderRadius = 32.0,
    this.refractionShader,
    this.backgroundImage,
    this.refractionIntensity = 0.05,
    this.bgSize = const Size(1000, 1000),
  });

  @override
  State<LiquidGlassContainer> createState() => _LiquidGlassContainerState();
}

class _LiquidGlassContainerState extends State<LiquidGlassContainer> {
  final GlobalKey _containerKey = GlobalKey();
  Offset _currentOffset = Offset.zero;
  ScrollPosition? _scrollPosition;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachScrollListener();
  }

  /// 监听父级 Scrollable 组件的滚动事件
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
    // 首次渲染后立即获取一次位置
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePosition());
  }

  /// 动态计算容器在屏幕上的全局坐标 (localToGlobal)
  void _updatePosition() {
    if (!mounted) return;
    final renderBox = _containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final newOffset = renderBox.localToGlobal(Offset.zero);
      if (newOffset != _currentOffset) {
        setState(() {
          _currentOffset = newOffset;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_updatePosition);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _containerKey, // 挂载 GlobalKey 以获取 RenderBox 坐标
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          children: [
            // Shader 全局动态折射层
            if (widget.refractionShader != null && widget.backgroundImage != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _RefractionPainter(
                    shader: widget.refractionShader!,
                    image: widget.backgroundImage!,
                    intensity: widget.refractionIntensity,
                    offset: _currentOffset, // 动态传入实时屏幕坐标
                    bgSize: widget.bgSize,
                  ),
                ),
              ),

            // 实际视图内容
            widget.child,
          ],
        ),
      ),
    );
  }
}

/// Shader 渲染器 (保持精炼)
class _RefractionPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image image;
  final double intensity;
  final Offset offset;
  final Size bgSize;

  _RefractionPainter({
    required this.shader,
    required this.image,
    required this.intensity,
    required this.offset,
    required this.bgSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 0, 1: u_container_size
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    
    // 2, 3: u_container_offset (实时屏幕位置)
    shader.setFloat(2, offset.dx);
    shader.setFloat(3, offset.dy);

    // 4, 5: u_bg_size
    shader.setFloat(4, bgSize.width);
    shader.setFloat(5, bgSize.height);

    // 6: u_intensity
    shader.setFloat(6, intensity);

    // Sampler 0: u_bg_texture
    shader.setImageSampler(0, image);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _RefractionPainter oldDelegate) {
    return oldDelegate.shader != shader ||
        oldDelegate.image != image ||
        oldDelegate.intensity != intensity ||
        oldDelegate.offset != offset ||
        oldDelegate.bgSize != bgSize;
  }
}