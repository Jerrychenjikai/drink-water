import 'package:health/health.dart';

class WaterTrackingService {
  // 1. 实例化 Health 插件
  final Health _health = Health();

  // 定义我们需要操作的数据类型：饮水 (WATER)
  final List<HealthDataType> _types = [
    HealthDataType.WATER,
  ];

  // 定义读写权限
  final List<HealthDataAccess> _permissions = [
    HealthDataAccess.READ_WRITE,
  ];

  /// 初始化与权限请求
  Future<bool> requestPermissions() async {
    // 配置 Health 插件（支持 Android Health Connect）
    await _health.configure();

    // 检查/请求权限
    bool? hasPermission = await _health.hasPermissions(_types, permissions: _permissions);
    
    if (hasPermission != true) {
      try {
        hasPermission = await _health.requestAuthorization(_types, permissions: _permissions);
      } catch (error) {
        print("请求权限失败: $error");
        return false;
      }
    }
    return hasPermission ?? false;
  }

  /// 写入一次饮水记录
  /// [milliliters] 饮水量（毫升），系统 Health API 中以升 (Liters) 存储
  Future<bool> recordWaterIntake({
    required double milliliters,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    final double liters = milliliters / 1000.0;

    try {
      bool success = await _health.writeHealthData(
        value: liters,
        type: HealthDataType.WATER,
        startTime: now,
        endTime: now,
        unit: HealthDataUnit.LITER,
      );
      return success;
    } catch (e) {
      print("写入饮水数据失败: $e");
      return false;
    }
  }

  /// 读取今天总共喝了多少水（单位：毫升）
  Future<double> getTodayTotalWaterIntake() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);

    try {
      List<HealthDataPoint> healthData = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: startOfDay,
        endTime: now,
      );

      double totalLiters = 0.0;
      for (var point in healthData) {
        if (point.type == HealthDataType.WATER) {
          final value = point.value;
          if (value is NumericHealthValue) {
            totalLiters += value.numericValue.toDouble();
          }
        }
      }
      return totalLiters * 1000.0;
    } catch (e) {
      print("读取饮水数据失败: $e");
      return 0.0;
    }
  }

  /// 【新增】获取过去一周（包括今天）每天的饮水量
  /// 返回长度为 7 的 List<double>，顺序为：[6天前, 5天前, ..., 昨天, 今天]
  /// 单位：毫升 (ml)
  Future<List<double>> getPastWeekDailyWaterIntake() async {
    final now = DateTime.now();
    
    // 计算 6 天前的 00:00:00（即 7 天时间窗口的起点）
    final startOf7DaysAgo = DateTime(now.year, now.month, now.day - 6, 0, 0, 0);

    try {
      // 1. 一次性获取过去 7 天内的所有饮水原始记录
      List<HealthDataPoint> healthData = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: startOf7DaysAgo,
        endTime: now,
      );

      // 2. 初始化长度为 7 的列表，默认饮水量均为 0.0
      List<double> weeklyWater = List.filled(7, 0.0);

      // 3. 将取出的数据按日期进行归类统计
      for (var point in healthData) {
        if (point.type == HealthDataType.WATER) {
          final value = point.value;
          if (value is NumericHealthValue) {
            final double liters = value.numericValue.toDouble();
            final DateTime pointTime = point.dateFrom;

            // 计算该条数据属于这 7 天中的第几天（索引范围 0 ~ 6）
            final int dayIndex = DateTime(pointTime.year, pointTime.month, pointTime.day)
                .difference(startOf7DaysAgo)
                .inDays;

            // 防护：确保索引在 0 - 6 的合法范围内
            if (dayIndex >= 0 && dayIndex < 7) {
              weeklyWater[dayIndex] += liters * 1000.0; // 转换为毫升累计
            }
          }
        }
      }

      return weeklyWater;
    } catch (e) {
      print("获取过去一周饮水数据失败: $e");
      // 发生异常时返回全 0 的 7 元素列表
      return List.filled(7, 0.0);
    }
  }
}