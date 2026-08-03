// ui_basic.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// ==========================================
// 全局 Shader 预加载
// ==========================================
ui.FragmentShader? _globalRefractionShader;

Future<void> preloadLiquidGlassShader({String assetPath = 'shaders/refraction.frag'}) async {
  if (_globalRefractionShader != null) return;
  try {
    final program = await ui.FragmentProgram.fromAsset(assetPath);
    _globalRefractionShader = program.fragmentShader();
  } catch (e) {
    debugPrint('Liquid Glass Shader 加载失败: $e');
  }
}

// ==========================================
// 背景纹理共享 Scope
// ==========================================
class LiquidGlassScope extends StatefulWidget {
  final CustomPainter painter;
  final Widget child;

  const LiquidGlassScope({
    super.key,
    required this.painter,
    required this.child,
  });

  /// 供子组件获取背景纹理和尺寸数据
  static _LiquidGlassData? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_LiquidGlassInherited>()?.data;
  }

  @override
  State<LiquidGlassScope> createState() => _LiquidGlassScopeState();
}

class _LiquidGlassScopeState extends State<LiquidGlassScope> {
  ui.Image? _bgImage;
  Size _lastSize = Size.zero;

  @override
  void didUpdateWidget(covariant LiquidGlassScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 Painter（如背景主题）发生改变时自动刷新纹理
    if (oldWidget.painter != widget.painter && _lastSize != Size.zero) {
      _generateTexture(_lastSize);
    }
  }

  @override
  void dispose() {
    _bgImage?.dispose(); // 页面销毁时统一释放显存
    super.dispose();
  }

  /// 统一的生成背景纹理逻辑，同一个页面无论多少个玻璃卡片，此方法只执行一次
  Future<void> _generateTexture(Size size) async {
    if (size.width <= 0 || size.height <= 0) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
    
    widget.painter.paint(canvas, size);
    
    final picture = recorder.endRecording();
    final newImage = await picture.toImage(size.width.toInt(), size.height.toInt());

    if (mounted) {
      setState(() {
        _bgImage?.dispose(); // 释放旧显存
        _bgImage = newImage;
      });
    } else {
      newImage.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    if (_lastSize != screenSize) {
      _lastSize = screenSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _generateTexture(screenSize);
      });
    }

    return _LiquidGlassInherited(
      data: _LiquidGlassData(
        backgroundImage: _bgImage,
        bgSize: screenSize,
      ),
      child: widget.child,
    );
  }
}

class _LiquidGlassData {
  final ui.Image? backgroundImage;
  final Size bgSize;
  _LiquidGlassData({this.backgroundImage, required this.bgSize});
}

class _LiquidGlassInherited extends InheritedWidget {
  final _LiquidGlassData data;

  const _LiquidGlassInherited({
    required this.data,
    required super.child,
  });

  @override
  bool updateShouldNotify(_LiquidGlassInherited oldWidget) {
    return oldWidget.data.backgroundImage != data.backgroundImage ||
           oldWidget.data.bgSize != data.bgSize;
  }
}

// ==========================================
// 液态玻璃容器组件 (支持自动从 Scope 提取数据)
// ==========================================
class LiquidGlassContainer extends StatefulWidget {
  final Widget child;
  final double width;
  final double height;
  final double borderRadius;
  final double edgeMargin; 
  
  final ui.Image? backgroundImage; // 支持手动传入，不传则自动从 Scope 拿          
  final double refractionIntensity;          
  final Size? bgSize;              // 支持手动传入，不传则自动从 Scope 拿

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.width = double.infinity,
    this.height = double.infinity,
    this.borderRadius = 32.0,
    this.edgeMargin = 30.0,
    this.backgroundImage,
    this.refractionIntensity = 7,
    this.bgSize,
  });

  @override
  State<LiquidGlassContainer> createState() => _LiquidGlassContainerState();
}

class _LiquidGlassContainerState extends State<LiquidGlassContainer> {
  final GlobalKey _containerKey = GlobalKey();
  final ValueNotifier<Offset> _offsetNotifier = ValueNotifier(Offset.zero);
  ScrollPosition? _scrollPosition;
  Animation<double>? _routeAnimation; 

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachScrollListener();
    _attachRouteAnimationListener(); 
  }

  void _attachRouteAnimationListener() {
    final route = ModalRoute.of(context);
    if (route != null && route.animation != null) {
      final animation = route.animation;
      if (_routeAnimation != animation) {
        _routeAnimation?.removeListener(_updatePosition);
        _routeAnimation = animation;
        _routeAnimation?.addListener(_updatePosition); 
      }
    }
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
      if (newOffset != _offsetNotifier.value) {
        _offsetNotifier.value = newOffset;
      }
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_updatePosition);
    _routeAnimation?.removeListener(_updatePosition); 
    _offsetNotifier.dispose(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if(_globalRefractionShader == null){
      preloadLiquidGlassShader();
    }

    // 【关键】：优先取手动传入的，无传参则自动从父级 Scope 获取
    final scopeData = LiquidGlassScope.of(context);
    final effectiveImage = widget.backgroundImage ?? scopeData?.backgroundImage;
    final effectiveBgSize = widget.bgSize ?? scopeData?.bgSize ?? MediaQuery.sizeOf(context);
    
    return SizedBox(
      key: _containerKey,
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          children: [
            if (_globalRefractionShader != null && effectiveImage != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _RefractionPainter(
                    shader: _globalRefractionShader!,
                    image: effectiveImage,
                    intensity: widget.refractionIntensity,
                    offsetNotifier: _offsetNotifier, 
                    bgSize: effectiveBgSize,
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

class _RefractionPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image image;
  final double intensity;
  final ValueNotifier<Offset> offsetNotifier;
  final Size bgSize;
  final double borderRadius;
  final double edgeMargin;   

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
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    
    final currentOffset = offsetNotifier.value; 
    shader.setFloat(2, currentOffset.dx);
    shader.setFloat(3, currentOffset.dy);

    shader.setFloat(4, bgSize.width);
    shader.setFloat(5, bgSize.height);
    shader.setFloat(6, intensity);
    shader.setFloat(7, borderRadius);
    shader.setFloat(8, edgeMargin);
    shader.setImageSampler(0, image);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _RefractionPainter oldDelegate) {
    return oldDelegate.shader != shader ||
        oldDelegate.image != image ||
        oldDelegate.intensity != intensity ||
        oldDelegate.bgSize != bgSize ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.edgeMargin != edgeMargin ||
        oldDelegate.offsetNotifier != offsetNotifier;
  }
}

// ==========================================
// 弹窗
// ==========================================
Future<T?> showLiquidGlassPopup<T>({
  required BuildContext context,
  required GlobalKey backgroundKey,
  required Widget child,
  String shaderAssetPath = 'shaders/refraction.frag',
  double width = 320,
  double height = 460,
  double borderRadius = 32.0,
  double edgeMargin = 30.0,
  double refractionIntensity = 7,
  Color barrierColor = Colors.black12, 
}) async {
  if (_globalRefractionShader == null) {
    await preloadLiquidGlassShader(assetPath: shaderAssetPath);
  }

  final snapshotImage = await captureBackground(context, backgroundKey);
  final screenSize = MediaQuery.sizeOf(context);

  if (!context.mounted) return null;

  return showDialog<T>(
    context: context,
    barrierColor: barrierColor,
    builder: (context) {
      return Center(
        child: LiquidGlassContainer(
          width: width,
          height: height,
          borderRadius: borderRadius,
          edgeMargin: edgeMargin,
          backgroundImage: snapshotImage,            
          refractionIntensity: refractionIntensity,
          bgSize: screenSize,
          child: child,
        ),
      );
    },
  );
}

Future<ui.Image?> captureBackground(BuildContext context, GlobalKey backgroundKey) async {
  try {
    final boundary = backgroundKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final pixelRatio = View.of(context).devicePixelRatio;
    return await boundary.toImage(pixelRatio: pixelRatio);
  } catch (e) {
    debugPrint("快照捕获失败: $e");
    return null;
  }
}