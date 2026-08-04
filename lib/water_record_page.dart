import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';

import 'ui_basic.dart'; 
import 'ui_asset.dart';
import 'health_basic.dart';

class WaterRecordPage extends StatefulWidget {
  // 此时接收到的 snapshotImage 已经是预处理（高斯模糊+变暗）后的图片
  final ui.Image snapshotImage; 

  const WaterRecordPage({super.key, required this.snapshotImage});  

  static Future<void> push(BuildContext context, GlobalKey backgroundKey) async {
    // 1. 截取上级页面图像
    final rawSnapshot = await captureBackground(context, backgroundKey);

    if (rawSnapshot == null || !context.mounted) return;

    // 2. 直接对图片进行离屏预处理（模糊 + 变暗）
    final processedSnapshot = await processSnapshotImage(
      rawSnapshot,
      blurSigma: 16.0,      // 模糊程度
      darkenOpacity: 0.05,  // 变暗程度
    );

    if (!context.mounted) return;

    // 3. 跳转页面，传入处理好的图片
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: WaterRecordPage(snapshotImage: processedSnapshot),
          );
        },
      ),
    );
  }

  @override
  State<WaterRecordPage> createState() => _WaterRecordPagState();
}

class _WaterRecordPagState extends State<WaterRecordPage> with SingleTickerProviderStateMixin {
  final GlobalKey _backgroundKey = GlobalKey();
  final WaterTrackingService _waterTracking = WaterTrackingService();
  
  late Future<List<double>> _weeklyWaterFuture;
  late Future<double> _todayWaterFuture;

  late AnimationController _controller;
  late Animation<Offset> _card1SlideAnim;
  late Animation<Offset> _card2SlideAnim;
  late Animation<double> _scaleAnim;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    _initHealthData();
    _initAnimations();
  }

  void _initHealthData() {
    _weeklyWaterFuture = _waterTracking.requestPermissions().then((granted) {
      if (granted) {
        return _waterTracking.getPastWeekDailyWaterIntake();
      }
      return List.filled(7, 0.0);
    });
    _todayWaterFuture = _waterTracking.requestPermissions().then((granted) {
      if (granted) {
        return _waterTracking.getTodayTotalWaterIntake();
      }
      return 0.0;
    });
  }

  void _initAnimations() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // 模仿 iOS 系统流体曲线
    const iosCurve = Cubic(0.16, 1.0, 0.3, 1.0);

    _card1SlideAnim = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: iosCurve,
    ));

    _card2SlideAnim = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: iosCurve,
    ));

    _scaleAnim = Tween<double>(begin: 1.08, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: iosCurve),
    );

    _controller.forward();
  }

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
    widget.snapshotImage.dispose();
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
          key: _backgroundKey,
          child: Stack(
            children: [
              // 1. 底层：直接渲染预处理（模糊+变暗）好的截图，无需额外组件和遮罩！
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
                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Transform.translate(
                          offset: _card1SlideAnim.value * screenSize.height,
                          child: Transform.scale(
                            scale: _scaleAnim.value,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 16),
                                GestureDetector(
                                  onTap: _handlePop,
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
                                // 传给 LiquidGlassContainer 的就是处理后的统一背景
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
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const Spacer(),
                                        FutureBuilder<List<double>>(
                                          future: _weeklyWaterFuture,
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState == ConnectionState.waiting) {
                                              return const SizedBox(
                                                height: 140,
                                                child: Center(
                                                  child: CircularProgressIndicator.adaptive(),
                                                ),
                                              );
                                            }
                                            final data = snapshot.data ?? List.filled(7, 0.0);
                                            return WaterBarChart(waterData: data);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        Transform.translate(
                          offset: _card2SlideAnim.value * screenSize.height,
                          child: Transform.scale(
                            scale: _scaleAnim.value,
                            child: Column(
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
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const Spacer(),
                                        FutureBuilder<double>(
                                          future: _todayWaterFuture,
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState == ConnectionState.waiting) {
                                              return const SizedBox(
                                                height: 140,
                                                child: Center(
                                                  child: CircularProgressIndicator.adaptive(),
                                                ),
                                              );
                                            }
                                            final data = snapshot.data ?? 0.0;
                                            return WaterRingProgress(currentWater: data);
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
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () {
                                    // 实例化输入框控制器
                                    final TextEditingController waterController = TextEditingController();

                                    showLiquidGlassPopup(
                                      context: context,
                                      backgroundKey: _backgroundKey,
                                      width: 280,
                                      height: 220, // 调整高度以适配文本框和提交按钮
                                      borderRadius: 24.0,
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // 毫升数字输入框
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
                                                contentPadding: const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            // 弹窗内的 Liquid Button 记录按钮
                                            SizedBox(
                                              width: double.infinity,
                                              child: liquidButton(
                                                child: const Text(
                                                  "Record hydration",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.black87,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                onPressed: () async {
                                                  final text = waterController.text.trim();
                                                  final double? milliliters = double.tryParse(text);

                                                  if (milliliters != null && milliliters > 0) {
                                                    // 调用 WaterTrackingService 的 recordWaterIntake 写入数据
                                                    bool success = await _waterTracking.recordWaterIntake(
                                                      milliliters: milliliters,
                                                    );

                                                    if (context.mounted) {
                                                      Navigator.of(context).pop(); // 关闭弹窗
                                                      
                                                      // 提示结果
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            success
                                                                ? 'Sucecessfully recorded ${milliliters.toInt()} ml！'
                                                                : 'Recording failed',
                                                          ),
                                                        ),
                                                      );
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
                                  },
                                ),
                              ],
                            ),
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