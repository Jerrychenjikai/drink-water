import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'ui_basic.dart';

// ==========================================
// 新增：液态玻璃 SnackBar
// ==========================================
Future<void> showLiquidGlassSnackBar({
  required BuildContext context,
  required GlobalKey backgroundKey,
  required Widget content,
  double height = 80,
  double borderRadius = 16,
  double refractionIntensity = 3,
  double edgeMargin = 20,
}) async {
  // 1. 直接截取背景图
  final rawImage = await captureBackground(context, backgroundKey);
  if (rawImage == null) return;

  // 2. 预处理高斯模糊[cite: 1]
  final snapshotImage = await processSnapshotImage(
    rawImage,
    config: const SnapshotConfig(blurSigma: 16.0, darkenOpacity: 0.05),
  );

  if (!context.mounted) return;

  final screenSize = MediaQuery.sizeOf(context);

  // 3. 弹出毛玻璃 SnackBar[cite: 1]
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      content: SizedBox(
        height: height,
        child: LiquidGlassContainer(
          width: double.infinity,
          height: double.infinity,
          borderRadius: borderRadius,
          backgroundImage: snapshotImage,
          bgSize: screenSize,
          refractionIntensity: refractionIntensity,
          edgeMargin: edgeMargin,
          child: Center(child: content),
        ),
      ),
    ),
  );
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

    // 修改：使用主界面蓝牙已连接的深蓝色 (shade800/shade900)，提升在蓝水背景上的对比度
    final Color progressColor = isGoalReached
        ? Colors.blue.shade900
        : Colors.blue.shade800;

    // 轨道采用白色半透明，在深色水背景上依然清晰可见
    final Color trackColor = Colors.white.withOpacity(0.35);

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
                    color: Colors.blue.shade900, // 调整为深蓝色
                  ),
                ),
                Text(
                  '/ ${targetWater.toStringAsFixed(0)} ml',
                  style: TextStyle(
                    fontSize: size * 0.09,
                    color: Colors.blue.shade800.withOpacity(0.8), // 调整为深蓝色系
                    fontWeight: FontWeight.w600,
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
                // 达标用主界面的深蓝色 (blue.shade800)，未达标用白色半透明 (white.withOpacity(0.5)) 突出视觉层次
                color: amount >= targetWater
                    ? Colors.blue.shade900
                    : Colors.blue.shade800,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }),
      ),
    );
  }
}