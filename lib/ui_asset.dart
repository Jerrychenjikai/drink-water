import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'ui_basic.dart';

// ==========================================
// 新增：液态玻璃 SnackBar（优化版）
// ==========================================

/// 显示一个具有液态玻璃质感的 SnackBar，无任何边框。
///
/// 如果当前上下文存在 [LiquidGlassScope] 且已生成背景纹理，则使用真正的
/// [LiquidGlassContainer] 渲染玻璃效果；否则回退到一种轻量的半透明白色圆角容器，
/// 避免截图开销，同时保持视觉一致性。
void showLiquidGlassSnackBar(BuildContext context, Widget content) {
  final messenger = ScaffoldMessenger.of(context);
  final scopeData = LiquidGlassScope.of(context);

  // 尝试从 Scope 获取共享背景纹理
  final bgImage = scopeData?.backgroundImage;
  final bgSize = scopeData?.bgSize;

  // 构建 SnackBar 的内容 Widget（容器）
  Widget buildContainer() {
    if (bgImage != null && bgSize != null) {
      // 有玻璃纹理 → 使用真正的 LiquidGlassContainer
      return SizedBox(
        height: 80, // 固定高度，与常规 SnackBar 一致
        child: LiquidGlassContainer(
          width: double.infinity,
          height: double.infinity,
          borderRadius: 16,
          backgroundImage: bgImage,
          bgSize: bgSize,
          refractionIntensity: 7,
          edgeMargin: 20,
          child: Center(child: content),
        ),
      );
    } else {
      // 无纹理 → 回退到轻量半透明样式（无边框）
      return Container(
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          // 明确去掉任何边框
          border: Border.all(color: Colors.transparent, width: 0),
          boxShadow: null, // 无阴影，保持扁平
        ),
        child: Center(child: content),
      );
    }
  }

  final snackBar = SnackBar(
    backgroundColor: Colors.transparent,          // 背景完全透明
    elevation: 0,                                 // 无阴影
    shape: const RoundedRectangleBorder(
      side: BorderSide.none,                      // 去掉系统边框
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    content: buildContainer(),
  );

  messenger.showSnackBar(snackBar);
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