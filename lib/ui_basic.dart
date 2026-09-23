import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// ==========================================
// 图像处理配置类
// ==========================================
class SnapshotConfig {
  final double blurSigma;
  final double darkenOpacity;

  const SnapshotConfig({
    this.blurSigma = 16.0,
    this.darkenOpacity = 0.05,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapshotConfig &&
          runtimeType == other.runtimeType &&
          blurSigma == other.blurSigma &&
          darkenOpacity == other.darkenOpacity;

  @override
  int get hashCode => blurSigma.hashCode ^ darkenOpacity.hashCode;
}

// ==========================================
// 全局 Shader 预加载
// ==========================================
ui.FragmentShader? _globalRefractionShader;

Future<void> preloadLiquidGlassShader({String assetPath = 'shaders/shader.frag'}) async {
  if (_globalRefractionShader != null) return;
  try {
    final program = await ui.FragmentProgram.fromAsset(assetPath);
    _globalRefractionShader = program.fragmentShader();
  } catch (e) {
    debugPrint('Liquid Glass Shader 加载失败: $e');
  }
}

Future<ui.Image> processSnapshotImage(
  ui.Image inputImage, {
  SnapshotConfig config = const SnapshotConfig(),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, inputImage.width.toDouble(), inputImage.height.toDouble()),
  );

  // 配置画笔：高斯模糊 + 黑色混合模式（降亮度）
  final paint = Paint()
    ..imageFilter = ui.ImageFilter.blur(
      sigmaX: config.blurSigma,
      sigmaY: config.blurSigma,
      tileMode: TileMode.clamp, // 避免边缘模糊白边
    )
    ..colorFilter = ColorFilter.mode(
      Colors.black.withOpacity(config.darkenOpacity),
      BlendMode.lighten,
    );

  // 将原图绘制进 Recorder
  canvas.drawImage(inputImage, Offset.zero, paint);

  // 导出处理后的图像（极快，耗时通常 < 3毫秒）
  final picture = recorder.endRecording();
  return await picture.toImage(inputImage.width, inputImage.height);
}

// ==========================================
// 背景纹理共享 Scope
// ==========================================
class LiquidGlassScope extends StatefulWidget {
  final CustomPainter painter;
  final Widget child;
  
  // 新增：是否模糊以及模糊参数配置
  final bool blur;
  final SnapshotConfig snapshotConfig;

  const LiquidGlassScope({
    super.key,
    required this.painter,
    required this.child,
    this.blur = true,
    this.snapshotConfig = const SnapshotConfig(),
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

  // Only one snapshot generation is allowed at a time. If the painter changes
  // while a snapshot is being generated, we mark the texture dirty and capture
  // the newest painter as soon as the current generation finishes.
  bool _textureDirty = false;
  bool _isGeneratingTexture = false;
  bool _textureUpdateScheduled = false;

  bool _painterNeedsUpdate(CustomPainter oldPainter, CustomPainter newPainter) {
    if (oldPainter.runtimeType != newPainter.runtimeType) {
      return true;
    }
    return newPainter.shouldRepaint(oldPainter);
  }

  @override
  void didUpdateWidget(covariant LiquidGlassScope oldWidget) {
    super.didUpdateWidget(oldWidget);

    final painterChanged = _painterNeedsUpdate(oldWidget.painter, widget.painter);
    final snapshotConfigChanged = oldWidget.blur != widget.blur ||
        oldWidget.snapshotConfig != widget.snapshotConfig;

    if (painterChanged || snapshotConfigChanged) {
      _requestTextureUpdate();
    }
  }

  @override
  void dispose() {
    _bgImage?.dispose(); // 页面销毁时统一释放显存
    super.dispose();
  }

  void _requestTextureUpdate() {
    if (!mounted || _lastSize == Size.zero) return;

    _textureDirty = true;
    if (_isGeneratingTexture || _textureUpdateScheduled) return;

    _textureUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textureUpdateScheduled = false;
      if (!mounted || !_textureDirty || _isGeneratingTexture) return;
      _generateLatestTexture();
    });
  }

  /// Capture the latest painter state. Changes that happen while this is
  /// running are coalesced into one follow-up capture instead of starting a
  /// new screenshot for every scroll callback.
  Future<void> _generateLatestTexture() async {
    if (!mounted || _isGeneratingTexture || _lastSize == Size.zero) return;

    _isGeneratingTexture = true;
    _textureDirty = false;

    final size = _lastSize;
    final painter = widget.painter;
    final blur = widget.blur;
    final snapshotConfig = widget.snapshotConfig;

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, size.width, size.height),
      );

      painter.paint(canvas, size);

      final picture = recorder.endRecording();
      final rawImage = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      picture.dispose();

      ui.Image finalImage = rawImage;
      if (blur) {
        finalImage = await processSnapshotImage(
          rawImage,
          config: snapshotConfig,
        );
        rawImage.dispose();
      }

      if (!mounted) {
        finalImage.dispose();
        return;
      }

      setState(() {
        _bgImage?.dispose();
        _bgImage = finalImage;
      });
    } catch (e, stackTrace) {
      debugPrint('Liquid Glass background snapshot failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isGeneratingTexture = false;

      // A newer painter/state arrived while the current generation was in
      // progress. Capture the newest one rather than the stale one.
      if (mounted && _textureDirty) {
        _requestTextureUpdate();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    if (_lastSize != screenSize) {
      _lastSize = screenSize;
      _requestTextureUpdate();
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
// 液态玻璃容器组件 (支持实时坐标捕捉与 Shader 渲染)
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
    this.refractionIntensity = 3,
    this.bgSize,
  });

  @override
  State<LiquidGlassContainer> createState() => _LiquidGlassContainerState();
}

class _LiquidGlassContainerState extends State<LiquidGlassContainer> {
  // 保持 GlobalKey 在 State 中持久化，避免动画重建时重新创建 Key
  final GlobalKey _containerKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    if (_globalRefractionShader == null) {
      preloadLiquidGlassShader();
    }

    final scopeData = LiquidGlassScope.of(context);
    final effectiveImage = widget.backgroundImage ?? scopeData?.backgroundImage;
    final effectiveBgSize = widget.bgSize ?? scopeData?.bgSize ?? MediaQuery.sizeOf(context);
    
    // 关键：自动搜寻外层最近的 Scrollable 容器并获取其 ScrollPosition (继承自 Listenable)
    final scrollPosition = Scrollable.maybeOf(context)?.position;

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
                    containerKey: _containerKey,
                    bgSize: effectiveBgSize,
                    borderRadius: widget.borderRadius, 
                    edgeMargin: widget.edgeMargin / 1.5,
                    repaint: scrollPosition, // 绑定滚动信号
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
  final GlobalKey containerKey;
  final Size bgSize;
  final double borderRadius;
  final double edgeMargin;   

  _RefractionPainter({
    required this.shader,
    required this.image,
    required this.intensity,
    required this.containerKey,
    required this.bgSize,
    required this.borderRadius,
    required this.edgeMargin,
    Listenable? repaint, // 1. 新增 repaint 参数，用于接收滚动监听
  }) : super(repaint: repaint); // 2. 关键：传递给父类 CustomPainter，实现自动局部位移重绘

  @override
  void paint(Canvas canvas, Size size) {
    Offset currentOffset = Offset.zero;
    final renderBox = containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize && renderBox.attached) {
      currentOffset = renderBox.localToGlobal(Offset.zero);
    }

    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
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
    // 当属性更改时才重新对比，坐标刷新已由 super(repaint) 接管
    return oldDelegate.image != image ||
           oldDelegate.intensity != intensity ||
           oldDelegate.bgSize != bgSize ||
           oldDelegate.borderRadius != borderRadius ||
           oldDelegate.edgeMargin != edgeMargin;
  }
}

// ==========================================
// 弹窗
// ==========================================
Future<T?> showLiquidGlassPopup<T>({
  required BuildContext context,
  required GlobalKey backgroundKey,
  required Widget child,
  String shaderAssetPath = 'shaders/shader.frag',
  double width = 320,
  double height = 460,
  double borderRadius = 32.0,
  double edgeMargin = 30.0,
  double refractionIntensity = 3,
  Color barrierColor = Colors.black12,

  double mobileWidthThreshold = 600.0, 
  double mobileHeightThreshold = 1000.0,
}) async {
  if (_globalRefractionShader == null) {
    await preloadLiquidGlassShader(assetPath: shaderAssetPath);
  }

  final origImage = await captureBackground(context, backgroundKey);
  
  // 修改处：使用新的 SnapshotConfig 传参
  final snapshotImage = origImage == null ? null : await processSnapshotImage(
      origImage,
      config: const SnapshotConfig(
        blurSigma: 16.0,      // 模糊程度
        darkenOpacity: 0.05,  // 变暗程度
      ),
    );
    
  final screenSize = MediaQuery.sizeOf(context);

  if (!context.mounted) return null;

  // 判断屏幕宽度和高度是否均小于一定值（判定为 iPhone/手机端）
  final isMobile = screenSize.width < mobileWidthThreshold && 
                   screenSize.height < mobileHeightThreshold;

  if (isMobile) {
    // 手机端：从屏幕底部冒出，宽度占据整个屏幕
    return showModalBottomSheet<T>(
      context: context,
      barrierColor: barrierColor,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, 
      builder: (context) {
        return Padding( // 👈 新增 Padding 包裹层
          // 👈 动态获取键盘高度，并在底部撑开对应空间的 Padding
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), 
          child: LiquidGlassContainer(
            width: double.infinity,
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
  } else {
    // 否则（桌面端/平板端）：保持不变，居中显示
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