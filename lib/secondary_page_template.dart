import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'ui_basic.dart'; // 引入你的 captureBackground 与 processSnapshotImage

class FluidRoute {
  static Future<T?> push<T>({
    required BuildContext context,
    required GlobalKey backgroundKey,
    required Widget Function(BuildContext context, ui.Image snapshotImage) pageBuilder,
    double blurSigma = 16.0,
    double darkenOpacity = 0.05,
    Duration transitionDuration = const Duration(milliseconds: 300),
  }) async {
    ui.Image? rawSnapshot;
    ui.Image? processedSnapshot;

    try {
      // 1. 截取原始图像
      rawSnapshot = await captureBackground(context, backgroundKey);
      
      // 检查 context 是否还挂载，若未挂载则必须释放刚生成的 rawSnapshot
      if (rawSnapshot == null || !context.mounted) {
        rawSnapshot?.dispose();
        return null;
      }

      // 2. 离屏预处理
      processedSnapshot = await processSnapshotImage(
        rawSnapshot,
        blurSigma: blurSigma,
        darkenOpacity: darkenOpacity,
      );

      // 【关键】原始截图使命完成，如果 processSnapshotImage 内部没释放，这里必须手动释放
      // 如果 processSnapshotImage 内部已经 dispose 了 rawSnapshot，此处可省略
      rawSnapshot.dispose(); 
      rawSnapshot = null; // 置空防止重复 dispose

      // 检查处理完成后 context 是否依然有效
      if (!context.mounted) {
        processedSnapshot.dispose();
        return null;
      }

      // 3. 正常跳转
      return await Navigator.of(context).push<T>(
        PageRouteBuilder(
          opaque: false,
          transitionDuration: transitionDuration,
          reverseTransitionDuration: transitionDuration,
          pageBuilder: (context, animation, secondaryAnimation) {
            return FadeTransition(
              opacity: animation,
              child: pageBuilder(context, processedSnapshot!),
            );
          },
        ),
      );
    } catch (e) {
      // 发生任何异常时，兜底释放掉已创建的图片
      rawSnapshot?.dispose();
      processedSnapshot?.dispose();
      rethrow;
    }
  }
}

/// 2. 通用流体动画页面包裹组件
class FluidPageWrapper extends StatefulWidget {
  /// 传入预处理好的截图
  final ui.Image snapshotImage;

  /// 外部传入的 backgroundKey（可选），主要用于内部弹窗截图
  final GlobalKey? backgroundKey;

  /// 从顶部滑入的 Widget 构造器（Offset: 0, -0.5 -> 0, 0）
  final Widget Function(BuildContext context, VoidCallback handlePop)? topChildBuilder;

  /// 从底部滑入的 Widget 构造器（Offset: 0, 0.5 -> 0, 0）
  final Widget Function(BuildContext context, VoidCallback handlePop)? bottomChildBuilder;

  /// 如果需要完全自定义动画层，可使用此自定义 Builder
  final Widget Function(
    BuildContext context,
    AnimationController controller,
    Animation<Offset> topSlideAnim,
    Animation<Offset> bottomSlideAnim,
    Animation<double> scaleAnim,
    VoidCallback handlePop,
  )? customBuilder;

  /// 动画持续时间，默认 500ms
  final Duration animDuration;

  const FluidPageWrapper({
    super.key,
    required this.snapshotImage,
    this.backgroundKey,
    this.topChildBuilder,
    this.bottomChildBuilder,
    this.customBuilder,
    this.animDuration = const Duration(milliseconds: 500),
  });

  @override
  State<FluidPageWrapper> createState() => _FluidPageWrapperState();
}

class _FluidPageWrapperState extends State<FluidPageWrapper>
    with SingleTickerProviderStateMixin {
  late final GlobalKey _fallbackKey;
  late AnimationController _controller;
  late Animation<Offset> _topSlideAnim;
  late Animation<Offset> _bottomSlideAnim;
  late Animation<double> _scaleAnim;
  bool _isExiting = false;

  GlobalKey get _effectiveBackgroundKey => widget.backgroundKey ?? _fallbackKey;

  @override
  void initState() {
    super.initState();
    _fallbackKey = GlobalKey();
    _initAnimations();
  }

  void _initAnimations() {
    _controller = AnimationController(
      vsync: this,
      duration: widget.animDuration,
    );

    // iOS 风格流体曲线
    const iosCurve = Cubic(0.16, 1.0, 0.3, 1.0);

    _topSlideAnim = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: iosCurve,
    ));

    _bottomSlideAnim = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: iosCurve,
    ));

    _scaleAnim = Tween<double>(
      begin: 1.08,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: iosCurve,
    ));

    _controller.forward();
  }

  /// 统一处理退出动画并 Pop
  Future<void> _handlePop() async {
    if (_isExiting) return;
    _isExiting = true;

    await _controller.reverse();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    widget.snapshotImage.dispose(); // 自动释放内存
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handlePop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: RepaintBoundary(
          key: _effectiveBackgroundKey,
          child: Stack(
            children: [
              // 1. 底层：直接渲染预处理截图背景
              Positioned.fill(
                child: RawImage(
                  image: widget.snapshotImage,
                  fit: BoxFit.cover,
                ),
              ),

              // 2. 顶层内容（动画层）
              SafeArea(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    if (widget.customBuilder != null) {
                      return widget.customBuilder!(
                        context,
                        _controller,
                        _topSlideAnim,
                        _bottomSlideAnim,
                        _scaleAnim,
                        _handlePop,
                      );
                    }

                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        if (widget.topChildBuilder != null)
                          Transform.translate(
                            offset: _topSlideAnim.value * screenSize.height,
                            child: Transform.scale(
                              scale: _scaleAnim.value,
                              child: widget.topChildBuilder!(context, _handlePop),
                            ),
                          ),

                        if (widget.topChildBuilder != null && widget.bottomChildBuilder != null)
                          const SizedBox(height: 20),

                        if (widget.bottomChildBuilder != null)
                          Transform.translate(
                            offset: _bottomSlideAnim.value * screenSize.height,
                            child: Transform.scale(
                              scale: _scaleAnim.value,
                              child: widget.bottomChildBuilder!(context, _handlePop),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}