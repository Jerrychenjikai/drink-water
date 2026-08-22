import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'ui_basic.dart';

// ==========================================
// 新增：液态玻璃 SnackBar
// ==========================================

/// 显示一个具有液态玻璃质感的 SnackBar，无任何边框。
/// 
/// 自动从 [LiquidGlassScope] 获取背景纹理；若不存在，则截取当前屏幕并实时处理。
/// SnackBar 高度固定为 80，内容居中显示，支持自定义内容。
void showLiquidGlassSnackBar(BuildContext context, Widget content) {
  final messenger = ScaffoldMessenger.of(context);
  final scopeData = LiquidGlassScope.of(context);

  // 优先使用 Scope 中已生成的背景纹理（同步）
  if (scopeData?.backgroundImage != null && scopeData?.bgSize != null) {
    _showSnackBarWithImage(
      messenger,
      context,
      content,
      scopeData!.backgroundImage!,
      scopeData.bgSize,
      disposeImage: false, // Scope 管理生命周期
    );
  } else {
    // 否则异步截屏并处理（适用于未包裹 LiquidGlassScope 的情况）
    _captureAndShowSnackBar(messenger, context, content);
  }
}

/// 异步截取当前屏幕，处理后显示 SnackBar
Future<void> _captureAndShowSnackBar(
  ScaffoldMessengerState messenger,
  BuildContext context,
  Widget content,
) async {
  try {
    // 截取整个屏幕
    final renderView = WidgetsBinding.instance.renderView;
    final pixelRatio = View.of(context).devicePixelRatio;
    final rawImage = await renderView.toImage(pixelRatio: pixelRatio);

    // 应用模糊 + 变暗处理（使用默认配置）
    final processedImage = await processSnapshotImage(
      rawImage,
      config: const SnapshotConfig(),
    );
    // 释放原始图像（processSnapshotImage 内部会复制，原始需手动释放）
    rawImage.dispose();

    if (!messenger.mounted) {
      processedImage.dispose();
      return;
    }

    final screenSize = MediaQuery.sizeOf(context);
    _showSnackBarWithImage(
      messenger,
      context,
      content,
      processedImage,
      screenSize,
      disposeImage: true, // 由本函数创建的图像，需在 SnackBar 关闭后释放
    );
  } catch (e) {
    // 发生异常时降级为普通 SnackBar
    debugPrint('LiquidGlass SnackBar 截图失败，回退到普通 SnackBar: $e');
    messenger.showSnackBar(SnackBar(content: content));
  }
}

/// 使用给定的背景图像构建并显示 SnackBar
void _showSnackBarWithImage(
  ScaffoldMessengerState messenger,
  BuildContext context,
  Widget content,
  ui.Image bgImage,
  Size bgSize, {
  bool disposeImage = false,
}) {
  // 构建 SnackBar，完全透明背景，无边框无阴影
  final snackBar = SnackBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      side: BorderSide.none, // 去掉边框
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    content: SizedBox(
      height: 80, // 固定高度，匹配常见 SnackBar
      child: LiquidGlassContainer(
        width: double.infinity,
        height: double.infinity, // 由父 SizedBox 约束
        borderRadius: 16,
        backgroundImage: bgImage,
        bgSize: bgSize,
        refractionIntensity: 7,
        edgeMargin: 20,
        child: Center(child: content), // 内容居中
      ),
    ),
  );

  final controller = messenger.showSnackBar(snackBar);

  // 若图像为本函数创建，则在 SnackBar 关闭后释放显存
  if (disposeImage) {
    controller.closed.then((_) => bgImage.dispose());
  }
}


/// 提取出的通用 Elevated Button 构建函数
Widget liquidButton({
  required Widget child,
  required VoidCallback? onPressed,
}) {
  return ElevatedButton(
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
      backgroundColor: Colors.white.withOpacity(0.5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    onPressed: onPressed,
    child: child,
  );
}

class WaterRingProgress extends StatelessWidget {
  final double currentWater;
  final double targetWater;
  final double size;
  final double strokeWidth;

  const WaterRingProgress({
    super.key,
    required this.currentWater,
    this.targetWater = 2000.0,
    this.size = 140.0,
    this.strokeWidth = 14.0,
  });

  @override
  Widget build(BuildContext context) {
    // 限制进度比例在 0.0 ~ 1.0 之间
    final double ratio = targetWater > 0
        ? (currentWater / targetWater).clamp(0.0, 1.0)
        : 0.0;
    
    final bool isGoalReached = currentWater >= targetWater;

    // 保持与 WaterBarChart 一致的配色逻辑
    final Color progressColor = isGoalReached
        ? Colors.blueAccent
        : Colors.blueAccent.withOpacity(0.5);

    final Color trackColor = Colors.blueAccent.withOpacity(0.12);

    return Tooltip(
      message: '${currentWater.toStringAsFixed(0)} / ${targetWater.toStringAsFixed(0)} ml',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 环形进度条绘制层
            CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(
                ratio: ratio,
                strokeWidth: strokeWidth,
                progressColor: progressColor,
                trackColor: trackColor,
              ),
            ),
            // 中间文字显示
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentWater.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: size * 0.2,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
                Text(
                  '/ ${targetWater.toStringAsFixed(0)} ml',
                  style: TextStyle(
                    fontSize: size * 0.09,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double ratio;
  final double strokeWidth;
  final Color progressColor;
  final Color trackColor;

  _RingPainter({
    required this.ratio,
    required this.strokeWidth,
    required this.progressColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double center = size.width / 2;
    final double radius = center - (strokeWidth / 2);
    final Offset offsetCenter = Offset(center, center);

    // 1. 绘制底层阴影/背景轨道
    final Paint trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(offsetCenter, radius, trackPaint);

    // 2. 绘制前景进度弧线
    if (ratio > 0) {
      final Paint progressPaint = Paint()
        ..color = progressColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      // 从正上方 (-90度，即 -pi/2) 开始顺时针绘制
      const double startAngle = -pi / 2;
      final double sweepAngle = 2 * pi * ratio;

      canvas.drawArc(
        Rect.fromCircle(center: offsetCenter, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.ratio != ratio ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class WaterBarChart extends StatelessWidget {
  final List<double> waterData;
  final double targetWater;

  const WaterBarChart({
    super.key,
    required this.waterData,
    this.targetWater = 2000.0,
  });

  @override
  Widget build(BuildContext context) {
    final displayData = waterData.length == 7 ? waterData : List.filled(7, 0.0);

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
          final double ratio = maxVal > 0 ? (amount / maxVal).clamp(0.0, 1.0) : 0.0;
          final double barHeight = max(chartHeight * ratio, 4.0);

          return Tooltip(
            message: '${amount.toStringAsFixed(0)} ml',
            child: Container(
              width: 24,
              height: barHeight,
              decoration: BoxDecoration(
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