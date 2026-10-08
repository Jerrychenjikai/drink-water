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

Future<void> preloadLiquidGlassShader({
  String assetPath = 'shaders/refraction.frag',
}) async {
  if (_globalRefractionShader != null) return;

  try {
    final program = await ui.FragmentProgram.fromAsset(assetPath);
    _globalRefractionShader = program.fragmentShader();
  } catch (e) {
    debugPrint('Liquid Glass Shader 加载失败: $e');
  }
}

// ==========================================
// 对快照图片进行模糊 / 亮度处理
// ==========================================
Future<ui.Image> processSnapshotImage(
  ui.Image inputImage, {
  SnapshotConfig config = const SnapshotConfig(),
}) async {
  final recorder = ui.PictureRecorder();

  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(
      0,
      0,
      inputImage.width.toDouble(),
      inputImage.height.toDouble(),
    ),
  );

  final paint = Paint()
    ..imageFilter = ui.ImageFilter.blur(
      sigmaX: config.blurSigma,
      sigmaY: config.blurSigma,
      tileMode: TileMode.clamp,
    )
    ..colorFilter = ColorFilter.mode(
      Colors.black.withOpacity(config.darkenOpacity),
      BlendMode.lighten,
    );

  canvas.drawImage(
    inputImage,
    Offset.zero,
    paint,
  );

  final picture = recorder.endRecording();

  return await picture.toImage(
    inputImage.width,
    inputImage.height,
  );
}

// ==========================================
// 背景纹理共享 Scope
//
// 同时兼容两种背景来源：
//
// 1. painter
//    直接重放 CustomPainter 生成纹理。
//    支持:
//      - painter.shouldRepaint()
//      - painter 自身 Listenable 通知
//      - painter 替换
//
// 2. repaintBoundaryKey
//    从真实 RenderRepaintBoundary 捕获背景纹理。
//    保留旧版本接口与行为。
//
// 当 painter 和 repaintBoundaryKey 同时存在时：
//     painter 优先。
// ==========================================
class LiquidGlassScope extends StatefulWidget {
  /// 直接传入 CustomPainter。
  ///
  /// Scope 会调用 painter.paint() 来生成背景纹理，
  /// 并监听 painter 自身的 repaint 通知。
  final CustomPainter? painter;

  /// 从 RenderRepaintBoundary 捕获真实背景。
  ///
  /// 当 painter == null 时使用。
  final GlobalKey? repaintBoundaryKey;

  final Widget child;

  /// 是否对生成的背景纹理进行模糊。
  final bool blur;

  /// 背景纹理后处理配置。
  final SnapshotConfig snapshotConfig;

  const LiquidGlassScope({
    super.key,
    this.painter,
    this.repaintBoundaryKey,
    required this.child,
    this.blur = true,
    this.snapshotConfig = const SnapshotConfig(),
  });

  /// 获取当前 Scope 的背景纹理数据。
  static _LiquidGlassData? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_LiquidGlassInherited>()
        ?.data;
  }

  /// 手动通知 Scope 重新捕获背景纹理。
  ///
  /// 兼容旧版本接口。
  static void notifyUpdate(BuildContext context) {
    final state =
        context.findAncestorStateOfType<_LiquidGlassScopeState>();

    state?._requestTextureUpdate();
  }

  @override
  State<LiquidGlassScope> createState() =>
      _LiquidGlassScopeState();
}

class _LiquidGlassScopeState extends State<LiquidGlassScope> {
  ui.Image? _bgImage;

  /// 当前用于生成 painter 纹理的尺寸。
  Size _lastBgSize = Size.zero;

  /// 最近一次看到的屏幕尺寸。
  Size _lastScreenSize = Size.zero;

  /// 是否已经收到新的纹理更新请求。
  bool _textureDirty = false;

  /// 当前是否正在生成纹理。
  bool _isGeneratingTexture = false;

  /// 当前是否已经安排了 post-frame 更新任务。
  bool _textureUpdateScheduled = false;

  // ------------------------------------------
  // Painter Listenable 监听
  // ------------------------------------------

  void _attachPainterListener(CustomPainter? painter) {
    painter?.addListener(_handlePainterRepaint);
  }

  void _detachPainterListener(CustomPainter? painter) {
    painter?.removeListener(_handlePainterRepaint);
  }

  void _handlePainterRepaint() {
    _requestTextureUpdate();
  }

  // ------------------------------------------
  // 判断 painter 是否发生需要重绘的变化
  // ------------------------------------------

  bool _painterNeedsUpdate(
    CustomPainter? oldPainter,
    CustomPainter? newPainter,
  ) {
    if (identical(oldPainter, newPainter)) {
      return false;
    }

    if (oldPainter == null || newPainter == null) {
      return true;
    }

    if (oldPainter.runtimeType != newPainter.runtimeType) {
      return true;
    }

    return newPainter.shouldRepaint(oldPainter);
  }

  // ------------------------------------------
  // 初始化
  // ------------------------------------------

  @override
  void initState() {
    super.initState();

    _attachPainterListener(widget.painter);

    // 首次渲染完成后自动捕获一次背景纹理。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // painter 模式使用屏幕尺寸；
      // boundary 模式也需要一个初始尺寸。
      if (_lastBgSize == Size.zero) {
        _lastBgSize = MediaQuery.sizeOf(context);
      }

      _requestTextureUpdate();
    });
  }

  // ------------------------------------------
  // Widget 更新
  // ------------------------------------------

  @override
  void didUpdateWidget(
    covariant LiquidGlassScope oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    // painter 实例发生替换时重新挂监听。
    if (!identical(oldWidget.painter, widget.painter)) {
      _detachPainterListener(oldWidget.painter);
      _attachPainterListener(widget.painter);
    }

    final painterChanged = _painterNeedsUpdate(
      oldWidget.painter,
      widget.painter,
    );

    final sourceChanged =
        oldWidget.repaintBoundaryKey !=
        widget.repaintBoundaryKey;

    final snapshotConfigChanged =
        oldWidget.blur != widget.blur ||
        oldWidget.snapshotConfig != widget.snapshotConfig;

    if (
      painterChanged ||
      sourceChanged ||
      snapshotConfigChanged
    ) {
      _requestTextureUpdate();
    }
  }

  // ------------------------------------------
  // 销毁
  // ------------------------------------------

  @override
  void dispose() {
    _detachPainterListener(widget.painter);

    _bgImage?.dispose();

    super.dispose();
  }

  // ------------------------------------------
  // 请求更新纹理
  // ------------------------------------------

  void _requestTextureUpdate() {
    if (!mounted) return;

    if (_lastBgSize == Size.zero) {
      return;
    }

    _textureDirty = true;

    // 当前正在生成时，不再并发生成。
    // 当前任务结束后会再次处理最新状态。
    if (_isGeneratingTexture) {
      return;
    }

    // 已经安排过下一帧，也不需要重复安排。
    if (_textureUpdateScheduled) {
      return;
    }

    _textureUpdateScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textureUpdateScheduled = false;

      if (
        !mounted ||
        !_textureDirty ||
        _isGeneratingTexture
      ) {
        return;
      }

      _generateLatestTexture();
    });
  }

  // ------------------------------------------
  // 生成最新纹理
  // ------------------------------------------
  //
  // painter 模式：
  //
  //     painter.paint()
  //         ↓
  //     Picture
  //         ↓
  //     Image
  //
  // repaintBoundary 模式：
  //
  //     RenderRepaintBoundary.toImage()
  //
  // 生成过程中如果又发生新的更新，不启动第二个并发任务，
  // 而是把 _textureDirty 保持为 true。
  //
  // 当前任务完成以后，会再捕获一次最新状态。
  // ------------------------------------------

  Future<void> _generateLatestTexture() async {
    if (
      !mounted ||
      _isGeneratingTexture ||
      _lastBgSize == Size.zero
    ) {
      return;
    }

    _isGeneratingTexture = true;
    _textureDirty = false;

    ui.Image? rawImage;
    ui.Image? finalImage;
    ui.Picture? picture;

    final size = _lastBgSize;

    // 在任务开始时锁定当前 painter / config，
    // 避免生成过程中 widget 替换导致使用混杂状态。
    final painter = widget.painter;
    final blur = widget.blur;
    final snapshotConfig = widget.snapshotConfig;

    bool success = false;

    try {
      // ==========================================
      // 模式 A：直接从 CustomPainter 生成纹理
      // ==========================================
      if (painter != null) {
        final recorder = ui.PictureRecorder();

        final canvas = Canvas(
          recorder,
          Rect.fromLTWH(
            0,
            0,
            size.width,
            size.height,
          ),
        );

        painter.paint(
          canvas,
          size,
        );

        picture = recorder.endRecording();

        rawImage = await picture.toImage(
          max(
            1,
            size.width.round(),
          ),
          max(
            1,
            size.height.round(),
          ),
        );

        picture.dispose();
        picture = null;
      }

      // ==========================================
      // 模式 B：从 RenderRepaintBoundary 生成纹理
      // ==========================================
      else {
        final boundaryKey =
            widget.repaintBoundaryKey;

        if (boundaryKey != null) {
          final boundary =
              boundaryKey.currentContext
                  ?.findRenderObject()
              as RenderRepaintBoundary?;

          if (
            boundary != null &&
            boundary.attached &&
            boundary.hasSize
          ) {
            final bgSize = boundary.size;

            // 保留旧版本限制：
            // 最多使用 1.2 倍像素比例，
            // 避免截图过大影响流畅度。
            final dpr =
                MediaQuery.of(context)
                    .devicePixelRatio;

            final targetRatio = min(
              dpr,
              1.2,
            );

            rawImage =
                await boundary.toImage(
              pixelRatio: targetRatio,
            );

            // 真实 Boundary 的尺寸优先作为背景尺寸。
            if (bgSize != _lastBgSize) {
              _lastBgSize = bgSize;
            }
          }
        }
      }

      // ==========================================
      // 对生成的图片进行后处理
      // ==========================================

      if (rawImage != null) {
        finalImage = rawImage;

        if (blur) {
          finalImage =
              await processSnapshotImage(
            rawImage,
            config: snapshotConfig,
          );

          rawImage.dispose();
          rawImage = null;
        }

        // 组件已经销毁。
        if (!mounted) {
          finalImage?.dispose();
          finalImage = null;

          return;
        }

        setState(() {
          _bgImage?.dispose();

          _bgImage = finalImage;

          // 所有权转移给 State。
          finalImage = null;
        });

        success = true;
      }
    } catch (
      e,
      stackTrace
    ) {
      debugPrint(
        'Liquid Glass background snapshot failed: $e',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );
    } finally {
      picture?.dispose();
      rawImage?.dispose();
      finalImage?.dispose();

      _isGeneratingTexture = false;

      // 当前生成期间发生了新的更新：
      // 再捕获最新状态。
      //
      // 如果第一次截图失败，
      // 例如 RenderRepaintBoundary 尚未完成 Paint，
      // 也会自动在下一帧继续尝试。
      if (
        mounted &&
        (
          _textureDirty ||
          (!success && _bgImage == null)
        )
      ) {
        _requestTextureUpdate();
      }
    }
  }

  // ------------------------------------------
  // Build
  // ------------------------------------------

  @override
  Widget build(BuildContext context) {
    final screenSize =
        MediaQuery.sizeOf(context);

    // 屏幕尺寸发生变化时重新捕获背景。
    //
    // 这可以覆盖：
    // - 手机横竖屏切换
    // - 窗口缩放
    // - 平板尺寸变化
    // - Web / Desktop resize
    if (_lastScreenSize != screenSize) {
      _lastScreenSize = screenSize;

      // painter 模式始终跟随屏幕尺寸。
      //
      // boundary 模式如果尚未获得真实尺寸，
      // 则先使用屏幕尺寸作为临时值。
      if (
        widget.painter != null ||
        _lastBgSize == Size.zero
      ) {
        _lastBgSize = screenSize;
      }

      _requestTextureUpdate();
    }

    return _LiquidGlassInherited(
      data: _LiquidGlassData(
        backgroundImage: _bgImage,

        bgSize:
            _lastBgSize == Size.zero
                ? screenSize
                : _lastBgSize,

        boundaryKey:
            widget.repaintBoundaryKey,
      ),

      child: Listener(
        behavior:
            HitTestBehavior.translucent,

        // 触摸开始时重新捕获。
        onPointerDown: (_) {
          _requestTextureUpdate();
        },

        // 触摸移动时重新捕获。
        onPointerMove: (_) {
          _requestTextureUpdate();
        },

        // 触摸结束时重新捕获。
        onPointerUp: (_) {
          _requestTextureUpdate();
        },

        child: NotificationListener<
            ScrollNotification>(
          onNotification: (notification) {
            _requestTextureUpdate();

            // 不阻断原有 ScrollNotification。
            return false;
          },

          child: widget.child,
        ),
      ),
    );
  }
}

// ==========================================
// Scope 数据
// ==========================================
class _LiquidGlassData {
  final ui.Image? backgroundImage;

  final Size bgSize;

  /// 当背景来自 RenderRepaintBoundary 时，
  /// 用于计算 LiquidGlassContainer 相对背景的位置。
  final GlobalKey? boundaryKey;

  _LiquidGlassData({
    this.backgroundImage,
    required this.bgSize,
    this.boundaryKey,
  });
}

// ==========================================
// Inherited 数据
// ==========================================
class _LiquidGlassInherited extends InheritedWidget {
  final _LiquidGlassData data;

  const _LiquidGlassInherited({
    required this.data,
    required super.child,
  });

  @override
  bool updateShouldNotify(
    _LiquidGlassInherited oldWidget,
  ) {
    return
        oldWidget.data.backgroundImage !=
            data.backgroundImage ||
        oldWidget.data.bgSize !=
            data.bgSize ||
        oldWidget.data.boundaryKey !=
            data.boundaryKey;
  }
}

// ==========================================
// 液态玻璃容器
//
// 支持：
// - 自定义尺寸
// - 自定义圆角
// - edgeMargin
// - refractionIntensity
// - 手动 backgroundImage
// - 自动从 LiquidGlassScope 获取 backgroundImage
// - 手动 bgSize
// - 自动从 LiquidGlassScope 获取 bgSize
// - ScrollPosition repaint
// - RenderRepaintBoundary 相对坐标
// ==========================================
class LiquidGlassContainer
    extends StatefulWidget {
  final Widget child;

  final double width;

  final double height;

  final double borderRadius;

  final double edgeMargin;

  final ui.Image? backgroundImage;

  final double refractionIntensity;

  final Size? bgSize;

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
  State<LiquidGlassContainer>
      createState() =>
          _LiquidGlassContainerState();
}

class _LiquidGlassContainerState
    extends State<LiquidGlassContainer> {
  /// State 生命周期内保持同一个 Key。
  final GlobalKey _containerKey =
      GlobalKey();

  @override
  Widget build(BuildContext context) {
    // Shader 尚未加载时异步加载。
    if (_globalRefractionShader == null) {
      preloadLiquidGlassShader();
    }

    final scopeData =
        LiquidGlassScope.of(context);

    // 手动传入优先；
    // 否则从 Scope 获取。
    final effectiveImage =
        widget.backgroundImage ??
            scopeData?.backgroundImage;

    // 手动传入优先；
    // 否则从 Scope 获取。
    final effectiveBgSize =
        widget.bgSize ??
            scopeData?.bgSize ??
            MediaQuery.sizeOf(context);

    // ------------------------------------------
    // 圆角兼容
    //
    // 传入：
    //     borderRadius < 0
    //     或 borderRadius == infinity
    //
    // 自动按高度的一半处理。
    // 保留旧版本接口语义。
    // ------------------------------------------
    double effectiveRadius =
        widget.borderRadius;

    if (
      effectiveRadius < 0 ||
      effectiveRadius == double.infinity
    ) {
      effectiveRadius =
          widget.height != double.infinity
              ? widget.height / 2
              : 32.0;
    }

    // ------------------------------------------
    // 监听最近的 Scrollable
    //
    // ScrollPosition 本身是 Listenable。
    //
    // 将它传给 _RefractionPainter 的 repaint，
    // 即可在滚动时仅重绘 Painter，
    // 不需要重新 build 整棵 Widget Tree。
    // ------------------------------------------
    final scrollPosition =
        Scrollable.maybeOf(context)?.position;

    return SizedBox(
      key: _containerKey,
      width: widget.width,
      height: widget.height,

      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(
          effectiveRadius,
        ),

        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: 16,
            sigmaY: 16,
          ),

          child: Container(
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(
                effectiveRadius,
              ),

              color:
                  Colors.white.withOpacity(
                0.12,
              ),
            ),

            child: Stack(
              children: [
                // ==========================================
                // Shader 背景
                // ==========================================
                if (
                  _globalRefractionShader !=
                          null &&
                  effectiveImage != null
                )
                  Positioned.fill(
                    child: CustomPaint(
                      painter:
                          _RefractionPainter(
                        shader:
                            _globalRefractionShader!,
                        image:
                            effectiveImage,
                        intensity:
                            widget
                                .refractionIntensity,
                        containerKey:
                            _containerKey,
                        backgroundKey:
                            scopeData
                                ?.boundaryKey,
                        bgSize:
                            effectiveBgSize,
                        borderRadius:
                            effectiveRadius,
                        edgeMargin:
                            widget.edgeMargin /
                                1.5,

                        // 绑定 ScrollPosition。
                        repaint:
                            scrollPosition,
                      ),
                    ),
                  ),

                // ==========================================
                // 实际内容
                // ==========================================
                widget.child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 折射 Shader Painter
// ==========================================
class _RefractionPainter
    extends CustomPainter {
  final ui.FragmentShader shader;

  final ui.Image image;

  final double intensity;

  final GlobalKey containerKey;

  final GlobalKey? backgroundKey;

  final Size bgSize;

  final double borderRadius;

  final double edgeMargin;

  _RefractionPainter({
    required this.shader,
    required this.image,
    required this.intensity,
    required this.containerKey,
    this.backgroundKey,
    required this.bgSize,
    required this.borderRadius,
    required this.edgeMargin,
    Listenable? repaint,
  }) : super(
          repaint: repaint,
        );

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    Offset currentOffset =
        Offset.zero;

    // ------------------------------------------
    // 获取 LiquidGlassContainer 的全局位置
    // ------------------------------------------
    final renderBox =
        containerKey.currentContext
                ?.findRenderObject()
            as RenderBox?;

    if (
      renderBox != null &&
      renderBox.hasSize &&
      renderBox.attached
    ) {
      currentOffset =
          renderBox.localToGlobal(
        Offset.zero,
      );
    }

    // ------------------------------------------
    // 如果存在真实背景 Key：
    //
    // 把 Container 的全局坐标转换成
    // 相对于背景 RenderRepaintBoundary 的坐标。
    //
    // 这样背景滚动 / 位移时，
    // Shader 采样位置依然正确。
    // ------------------------------------------
    if (backgroundKey != null) {
      final bgRenderBox =
          backgroundKey!
                  .currentContext
                  ?.findRenderObject()
              as RenderBox?;

      if (
        bgRenderBox != null &&
        bgRenderBox.attached
      ) {
        final bgOffset =
            bgRenderBox.localToGlobal(
          Offset.zero,
        );

        currentOffset =
            currentOffset - bgOffset;
      }
    }

    // ------------------------------------------
    // Shader 参数
    //
    // 0: container width
    // 1: container height
    // 2: x offset
    // 3: y offset
    // 4: background width
    // 5: background height
    // 6: refraction intensity
    // 7: border radius
    // 8: edge margin
    // ------------------------------------------

    shader.setFloat(
      0,
      size.width,
    );

    shader.setFloat(
      1,
      size.height,
    );

    shader.setFloat(
      2,
      currentOffset.dx,
    );

    shader.setFloat(
      3,
      currentOffset.dy,
    );

    shader.setFloat(
      4,
      bgSize.width,
    );

    shader.setFloat(
      5,
      bgSize.height,
    );

    shader.setFloat(
      6,
      intensity,
    );

    shader.setFloat(
      7,
      borderRadius,
    );

    shader.setFloat(
      8,
      edgeMargin,
    );

    shader.setImageSampler(
      0,
      image,
    );

    final paint =
        Paint()..shader = shader;

    canvas.drawRect(
      Offset.zero & size,
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _RefractionPainter oldDelegate,
  ) {
    return
        oldDelegate.image != image ||
        oldDelegate.intensity !=
            intensity ||
        oldDelegate.bgSize != bgSize ||
        oldDelegate.borderRadius !=
            borderRadius ||
        oldDelegate.edgeMargin !=
            edgeMargin ||
        oldDelegate.backgroundKey !=
            backgroundKey;
  }
}

// ==========================================
// 液态玻璃弹窗
// ==========================================
Future<T?> showLiquidGlassPopup<T>({
  required BuildContext context,
  required GlobalKey backgroundKey,
  required Widget child,

  String shaderAssetPath =
      'shaders/shader.frag',

  double width = 320,

  double height = 460,

  double borderRadius = 32.0,

  double edgeMargin = 30.0,

  double refractionIntensity = 3,

  Color barrierColor = Colors.black12,

  double mobileWidthThreshold = 600.0,

  double mobileHeightThreshold =
      1000.0,
}) async {
  // ------------------------------------------
  // 确保 Shader 已加载
  // ------------------------------------------
  if (_globalRefractionShader == null) {
    await preloadLiquidGlassShader(
      assetPath: shaderAssetPath,
    );
  }

  // ------------------------------------------
  // 捕获背景
  // ------------------------------------------
  final origImage =
      await captureBackground(
    context,
    backgroundKey,
  );

  // ------------------------------------------
  // 对背景进行模糊
  // ------------------------------------------
  final snapshotImage =
      origImage == null
          ? null
          : await processSnapshotImage(
              origImage,
              config:
                  const SnapshotConfig(
                blurSigma: 16.0,
                darkenOpacity: 0.05,
              ),
            );

  // 原图不再需要。
  origImage?.dispose();

  final screenSize =
      MediaQuery.sizeOf(context);

  if (!context.mounted) {
    return null;
  }

  // ------------------------------------------
  // 判断是否使用 Mobile BottomSheet
  // ------------------------------------------
  final isMobile =
      screenSize.width <
              mobileWidthThreshold &&
          screenSize.height <
              mobileHeightThreshold;

  // ==========================================
  // 手机
  // ==========================================
  if (isMobile) {
    return showModalBottomSheet<T>(
      context: context,

      barrierColor: barrierColor,

      backgroundColor:
          Colors.transparent,

      isScrollControlled: true,

      builder: (context) {
        return Padding(
          // 键盘弹出时让 BottomSheet
          // 自动避开键盘。
          padding:
              EdgeInsets.only(
            bottom:
                MediaQuery.viewInsetsOf(
              context,
            ).bottom,
          ),

          child:
              LiquidGlassContainer(
            width:
                double.infinity,

            height:
                height,

            borderRadius:
                borderRadius,

            edgeMargin:
                edgeMargin,

            backgroundImage:
                snapshotImage,

            refractionIntensity:
                refractionIntensity,

            bgSize:
                screenSize,

            child:
                child,
          ),
        );
      },
    );
  }

  // ==========================================
  // Desktop / Tablet
  // ==========================================
  return showDialog<T>(
    context: context,

    barrierColor: barrierColor,

    builder: (context) {
      return Center(
        child:
            LiquidGlassContainer(
          width:
              width,

          height:
              height,

          borderRadius:
              borderRadius,

          edgeMargin:
              edgeMargin,

          backgroundImage:
              snapshotImage,

          refractionIntensity:
              refractionIntensity,

          bgSize:
              screenSize,

          child:
              child,
        ),
      );
    },
  );
}

// ==========================================
// 捕获 RenderRepaintBoundary
// ==========================================
Future<ui.Image?> captureBackground(
  BuildContext context,
  GlobalKey backgroundKey,
) async {
  try {
    final boundary =
        backgroundKey.currentContext
                ?.findRenderObject()
            as RenderRepaintBoundary?;

    if (boundary == null) {
      return null;
    }

    if (!boundary.attached) {
      return null;
    }

    if (!boundary.hasSize) {
      return null;
    }

    final pixelRatio =
        View.of(context).devicePixelRatio;

    return await boundary.toImage(
      pixelRatio: pixelRatio,
    );
  } catch (e) {
    debugPrint(
      '快照捕获失败: $e',
    );

    return null;
  }
}