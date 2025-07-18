# 慧本 (HuiBen)

一个基于 Flutter 的智能阅读应用。

## 功能特性

- 📖 智能翻页检测：使用 MobileNetV2 模型进行实时翻页识别
- 📱 跨平台支持：支持 Android、iOS平台
- 🎯 高性能设计：优化了模型推理和图像处理流程

## 翻页检测性能优化

为了解决模型检测时越来越卡的问题，我们做了以下关键优化：

### 1. 帧率控制
- **跳帧处理**：只处理每第 5 帧，减少 80% 的计算量
- **时间间隔控制**：确保处理间隔至少 3000ms
- **自适应频率**：根据设备性能动态调整

### 2. 异步处理优化
- **防并发处理**：确保同时只有一个推理任务运行
- **超时机制**：单次处理最长 1 秒，防止卡死
- **资源管理**：每次处理后立即释放 ONNX 张量

### 3. 内存优化
- **预分配内存**：避免频繁的内存分配和回收
- **边界检查**：防止数组越界导致的崩溃
- **及时释放**：使用 try-finally 确保资源释放


## 项目结构

```
lib/
├── main.dart              # 应用入口
├── pages/                 # 页面文件
│   ├── home_page.dart    # 主页
│   ├── reading_page.dart # 阅读页面
│   └── profile_page.dart # 个人资料页
└── services/             # 服务层
    └── page_turn_detector.dart # 翻页检测服务
```

## 开发环境

- Flutter SDK >= 3.0.0
- Dart >= 3.0.0
- Camera plugin
- ONNX Runtime

## 安装和运行

1. 克隆项目：
```bash
git clone <repository-url>
cd huiben
```

2. 获取依赖：
```bash
flutter pub get
```

3. 配置密钥：
   参考http://neuronx.top/2025/07/04/Flutter%E5%BC%80%E5%8F%91-%E5%AF%86%E9%92%A5%E4%BF%9D%E6%8A%A4/
   配置自己的apikey等

4. 运行应用：
```bash
flutter run
```

## 故障排除

### 翻页检测卡顿问题

如果仍然遇到性能问题，可以尝试以下方法：

1. **调整跳帧数**：
```dart
// 在 page_turn_detector.dart 中修改
static const int _maxFrameSkip = 10; // 增加跳帧数
```

2. **降低相机分辨率**：
在相机配置中使用较低的分辨率

3. **调整相似度阈值**：
```dart
static const double _similarityThreshold = 0.6; // 降低阈值
```

### 内存使用过高

1. 定期调用 `detector.dispose()` 释放资源
2. 在应用后台时停止检测：`detector.stopDetection()`
3. 监控内存使用，必要时重启检测器

