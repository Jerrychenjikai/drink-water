import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'ui_basic.dart';
import 'ui_asset.dart';
import 'health_basic.dart';
import 'secondary_page_template.dart'; // 引入上面封装的模板文件

class WaterRecordPage extends StatefulWidget {
  final ui.Image snapshotImage;

  const WaterRecordPage({super.key, required this.snapshotImage});

  /// 一行代码实现页面跳转（包含截图、模糊处理、Fade 进入动画）
  static Future<void> push(BuildContext context, GlobalKey backgroundKey) {
    return FluidRoute.push(
      context: context,
      backgroundKey: backgroundKey,
      pageBuilder: (context, processedSnapshot) => WaterRecordPage(snapshotImage: processedSnapshot),
    );
  }

  @override
  State<WaterRecordPage> createState() => _WaterRecordPageState();
}

class _WaterRecordPageState extends State<WaterRecordPage> {
  final GlobalKey _backgroundKey = GlobalKey();
  final WaterTrackingService _waterTracking = WaterTrackingService();

  late Future<List<double>> _weeklyWaterFuture;
  late Future<double> _todayWaterFuture;

  @override
  void initState() {
    super.initState();
    _initHealthData();
  }

  void _initHealthData() {
    _weeklyWaterFuture = _waterTracking.requestPermissions().then((granted) {
      if (granted) return _waterTracking.getPastWeekDailyWaterIntake();
      return List.filled(7, 0.0);
    });
    _todayWaterFuture = _waterTracking.requestPermissions().then((granted) {
      if (granted) return _waterTracking.getTodayTotalWaterIntake();
      return 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 直接使用 FluidPageWrapper 包裹页面
    return FluidPageWrapper(
      snapshotImage: widget.snapshotImage,
      backgroundKey: _backgroundKey,
      topChildBuilder: (context, handlePop) => _buildTopSection(context, handlePop),
      bottomChildBuilder: (context, handlePop) => _buildBottomSection(context),
    );
  }

  /// 构建从上方滑入的内容（标题与周图表）
  Widget _buildTopSection(BuildContext context, VoidCallback handlePop) {
    final screenSize = MediaQuery.sizeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        GestureDetector(
          onTap: handlePop, // 点击返回，直接执行反向退出动画
          child: const Icon(Icons.arrow_back_ios, color: Colors.black87, size: 28),
        ),
        const SizedBox(height: 16),
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
        LiquidGlassContainer(
          height: 260,
          borderRadius: 36,
          backgroundImage: widget.snapshotImage,
          bgSize: screenSize,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "This Week",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black),
                ),
                const Spacer(),
                FutureBuilder<List<double>>(
                  future: _weeklyWaterFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 140,
                        child: Center(child: CircularProgressIndicator.adaptive()),
                      );
                    }
                    return WaterBarChart(waterData: snapshot.data ?? List.filled(7, 0.0));
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建从下方滑入的内容（今日饮水与打卡按钮）
  Widget _buildBottomSection(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LiquidGlassContainer(
          height: 260,
          borderRadius: 36,
          backgroundImage: widget.snapshotImage,
          bgSize: screenSize,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Today",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black),
                ),
                const Spacer(),
                FutureBuilder<double>(
                  future: _todayWaterFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 140,
                        child: Center(child: CircularProgressIndicator.adaptive()),
                      );
                    }
                    return Center(child:WaterRingProgress(currentWater: snapshot.data ?? 0.0));
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        liquidButton(
          child: const Text(
            "Record hydration",
            style: TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.bold),
          ),
          onPressed: () => _showRecordDialog(context),
        ),
      ],
    );
  }

  void _showRecordDialog(BuildContext context) {
    final TextEditingController waterController = TextEditingController();
    showLiquidGlassPopup(
      context: context,
      backgroundKey: _backgroundKey,
      width: 280,
      height: 220,
      borderRadius: 24.0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: waterController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'Volume (ml)',
                hintText: 'e.g. 250',
                filled: true,
                fillColor: Colors.white.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: liquidButton(
                child: const Text(
                  "Record hydration",
                  style: TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  final text = waterController.text.trim();
                  final double? milliliters = double.tryParse(text);

                  if (milliliters != null && milliliters > 0) {
                    bool success = await _waterTracking.recordWaterIntake(milliliters: milliliters);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success ? 'Sucecessfully recorded ${milliliters.toInt()} ml！' : 'Recording failed',
                          ),
                        ),
                      );
                      _initHealthData();
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Incorrect number')),
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}