import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'text_extraction_service.dart';

/// 翻页检测服务
/// 使用 MobileNetV2 模型提取图像特征，通过比较特征向量检测翻页
/// 同时支持HSV特征检测作为备用方案（适用于鸿蒙平台）
class PageTurnDetector {
  static const String _tag = 'PageTurnDetector';
  static const int _inputSize = 224; // MobileNetV2输入尺寸
  static const double _similarityThreshold = 0.7; // 相似度阈值
  static const int _maxFrameSkip = 10; // 最大跳帧数（控制处理频率）
  static const int _maxProcessingTime = 500; // 最大处理时间（毫秒）
  
  // HSV检测相关常量
  static const double _hsvThreshold = 0.15; // HSV相似度阈值（0-1，值越大差异越大）
  static const int _histogramBins = 50; // 直方图bin数量
  
  // ONNX Runtime 相关
  OrtSession? _session;
  bool _isModelLoaded = false;
  
  // 检测状态
  bool _isDetecting = false;
  bool _isProcessing = false; // 防止异步累积
  List<double>? _previousFeature;
  double _currentSimilarity = 1.0;
  
  // HSV检测相关状态
  img.Image? _previousImage; // 保存上一帧图像用于HSV比较
  double _currentHsvSimilarity = 0.0; // HSV相似度
  bool _useHsvDetection = false; // 是否启用HSV检测
  
  // 帧率控制
  int _frameCounter = 0;
  DateTime? _lastProcessTime;
  int _consecutiveTimeouts = 0; // 连续超时计数
  
  // 文本提取服务
  TextExtractionService? _textExtractionService;
  CameraImage? _lastCameraImage; // 保存当前相机图像用于文本提取
  bool _isExtractingText = false; // 防止重复文本提取
  
  // ImageNet标准化参数
  static const List<double> _mean = [0.485, 0.456, 0.406];
  static const List<double> _std = [0.229, 0.224, 0.225];
  
  // 回调函数
  Function(String)? onPageTurnDetected;
  Function(double)? onSimilarityUpdated;
  Function(String)? onStatusChanged;
  Function(String)? onTextExtracted; // 文本提取完成回调
  Function(String)? onTextExtractionError; // 文本提取错误回调

  /// 设置文本提取服务
  void setTextExtractionService(TextExtractionService textExtractionService) {
    _textExtractionService = textExtractionService;
    
    // 设置文本提取服务的回调
    _textExtractionService!.onTextExtracted = (text) {
      onTextExtracted?.call(text);
      _isExtractingText = false;
    };
    
    _textExtractionService!.onError = (error) {
      onTextExtractionError?.call(error);
      _isExtractingText = false;
    };
    
    debugPrint('$_tag: 文本提取服务已设置');
  }

  /// 设置是否使用HSV检测（备用方案，适用于鸿蒙等不支持ONNX的平台）
  void setUseHsvDetection(bool useHsv) {
    _useHsvDetection = useHsv;
    debugPrint('$_tag: HSV检测已${useHsv ? "启用" : "禁用"}');
  }

  /// 初始化模型
  Future<bool> initModel() async {
    try {
      OrtEnv.instance.init();
      onStatusChanged?.call('正在加载模型...');
      debugPrint('$_tag: 开始加载ONNX模型');
      
      // 从assets加载模型文件
      final modelData = await rootBundle.load('assets/models/mymobilenetv2.onnx');
      final modelBytes = modelData.buffer.asUint8List();
      debugPrint('$_tag: 模型文件加载成功，大小: ${modelBytes.length} bytes');
      
      // 创建ONNX session
      final sessionOptions = OrtSessionOptions();
      debugPrint('$_tag: 使用默认ONNX配置初始化');
      
      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
      
      // 验证模型输入输出
      final inputNames = _session!.inputNames;
      final outputNames = _session!.outputNames;
      debugPrint('$_tag: 模型输入: $inputNames');
      debugPrint('$_tag: 模型输出: $outputNames');
      
      // 简单测试推理（用随机数据）
      // if (await _testModelInference()) {
      //   _isModelLoaded = true;
      //   onStatusChanged?.call('模型加载并验证成功');
      //   debugPrint('$_tag: 模型加载并验证成功');
      //   return true;
      // } else {
      //   throw Exception('模型验证失败');
      // }
      _isModelLoaded = true;
      onStatusChanged?.call('模型加载成功');
      return true;
    } catch (e) {
      _isModelLoaded = false;
      onStatusChanged?.call('模型加载失败: $e');
      debugPrint('$_tag: 模型加载失败 - $e');
      return false;
    }
  }

  /// 测试模型推理（无时间限制）
  Future<bool> _testModelInference() async {
    try {
      debugPrint('$_tag: ==========================================');
      debugPrint('$_tag: 开始模型推理测试（无时间限制）...');
      debugPrint('$_tag: ==========================================');
      
      // 创建测试数据：224x224x3的随机数据（Float32类型）
      debugPrint('$_tag: 正在生成测试数据...');
      final testDataDouble = List.generate(
        _inputSize * _inputSize * 3, 
        (index) => (index % 255) / 255.0 - 0.5
      );
      
      // 转换为Float32类型以匹配模型期望
      final testData = Float32List.fromList(testDataDouble);
      debugPrint('$_tag: 测试数据生成完成，数据量: ${testData.length}，类型: Float32');
      
      debugPrint('$_tag: 正在创建输入张量...');
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        testData,
        [1, 3, _inputSize, _inputSize],
      );
      debugPrint('$_tag: 输入张量创建完成');
      
      debugPrint('$_tag: 准备输入数据映射...');
      final inputs = {'input': inputTensor};
      debugPrint('$_tag: 输入数据映射完成');
      
      debugPrint('$_tag: ==========================================');
      debugPrint('$_tag: 开始ONNX推理（这可能需要较长时间）...');
      debugPrint('$_tag: 开始时间: ${DateTime.now()}');
      debugPrint('$_tag: ==========================================');
      
      final startTime = DateTime.now();
      
      // 调用ONNX推理
      final outputs = await _session!.runAsync(OrtRunOptions(), inputs);
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;
      
      debugPrint('$_tag: ==========================================');
      debugPrint('$_tag: ONNX推理完成！');
      debugPrint('$_tag: 总耗时: ${duration}ms (${(duration/1000).toStringAsFixed(2)}秒)');
      debugPrint('$_tag: 结束时间: ${DateTime.now()}');
      debugPrint('$_tag: ==========================================');
      
      debugPrint('$_tag: 正在处理输出结果...');
      if (outputs != null) {
        debugPrint('$_tag: 输出不为空，数量: ${outputs.length}');
        for (int i = 0; i < outputs.length; i++) {
          if (outputs[i] != null) {
            debugPrint('$_tag: 输出[$i]: ${outputs[i]!.value.runtimeType}');
            outputs[i]?.release();
          }
        }
      } else {
        debugPrint('$_tag: 警告：输出为空');
      }
      
      debugPrint('$_tag: 正在释放输入张量...');
      inputTensor.release();
      debugPrint('$_tag: 资源清理完成');
      
      debugPrint('$_tag: ==========================================');
      debugPrint('$_tag: 模型测试成功！耗时: ${duration}ms');
      debugPrint('$_tag: ==========================================');
      return true;
    } catch (e) {
      debugPrint('$_tag: ==========================================');
      debugPrint('$_tag: 模型测试失败 - ${e.runtimeType}: $e');
      debugPrint('$_tag: 失败时间: ${DateTime.now()}');
      debugPrint('$_tag: ==========================================');
      return false;
    }
  }

  /// 开始翻页检测
  void startDetection() {
    if (!_isModelLoaded && !_useHsvDetection) {
      debugPrint('$_tag: 模型未加载且HSV检测未启用，无法开始检测');
      return;
    }
    
    _isDetecting = true;
    _isProcessing = false;
    _previousFeature = null;
    _previousImage = null;
    _currentSimilarity = 1.0;
    _currentHsvSimilarity = 0.0;
    _frameCounter = 0;
    _lastProcessTime = null;
    
    String detectionMode = '';
    if (_isModelLoaded && _useHsvDetection) {
      detectionMode = '(ONNX+HSV模式)';
    } else if (_isModelLoaded) {
      detectionMode = '(ONNX模式)';
    } else if (_useHsvDetection) {
      detectionMode = '(HSV模式)';
    }
    
    onStatusChanged?.call('翻页检测已启动$detectionMode');
    debugPrint('$_tag: 开始翻页检测$detectionMode');
  }

  /// 停止翻页检测
  void stopDetection() {
    _isDetecting = false;
    _isProcessing = false;
    _previousFeature = null;
    _previousImage = null;
    _currentSimilarity = 1.0;
    _currentHsvSimilarity = 0.0;
    _frameCounter = 0;
    _lastProcessTime = null;
    onStatusChanged?.call('翻页检测已停止');
    print('$_tag: 停止翻页检测');
  }

  /// 处理相机帧进行翻页检测（优化版本）
  Future<void> processFrame(CameraImage cameraImage) async {
    if (!_isDetecting || (!_isModelLoaded && !_useHsvDetection) || (_session == null && !_useHsvDetection)) {
      return;
    }

    // 保存当前相机图像，用于翻页时的文本提取
    _lastCameraImage = cameraImage;

    // 防止异步处理累积
    if (_isProcessing) {
      debugPrint('$_tag: 跳过帧 - 上一帧仍在处理中');
      return;
    }

    // 检查模型状态
    if (_session == null) {
      print('$_tag: ONNX 会话为空，停止处理');
      return;
    }

    // 帧率控制 - 只处理每第N帧
    _frameCounter++;
    if (_frameCounter % _maxFrameSkip != 0) {
      return;
    }

    // 时间间隔控制 - 确保最小处理间隔
    final now = DateTime.now();
    if (_lastProcessTime != null) {
      final timeDiff = now.difference(_lastProcessTime!).inMilliseconds;
      if (timeDiff < 3000) { // 最小3s间隔
        return;
      }
    }

    _isProcessing = true;
    _lastProcessTime = now;
    print('$_tag: 开始处理帧...');

    try {
      List<double>? result;
      
      // 只有在模型加载时才进行ONNX推理
      if (_isModelLoaded && _session != null) {
        print('$_tag: 调用 _processFrameInternal...');
        result = await _processFrameInternal(cameraImage).timeout(
          Duration(milliseconds: _maxProcessingTime),
          onTimeout: () {
            _consecutiveTimeouts++;
            print('$_tag: 处理超时! 连续超时次数: $_consecutiveTimeouts');
            
            // 如果连续超时超过3次，重新初始化模型
            if (_consecutiveTimeouts >= 3) {
              print('$_tag: 连续超时过多，将重新初始化模型');
              _scheduleModelReinit();
            }
            
            return null;
          },
        );
        
        print('$_tag: _processFrameInternal 返回结果: ${result != null ? "成功" : "失败"}');
      }
      
      // 检测逻辑：结合ONNX特征检测和HSV检测
      bool isPageChangedFeature = false;
      bool isPageChangedHSV = false;
      
      // ONNX特征检测
      if (result != null && _isModelLoaded) {
        isPageChangedFeature = _isPageChangedFeature(_previousFeature, result);
        _previousFeature = result;
      }
      
      // HSV特征检测（如果启用）
      if (_useHsvDetection) {
        final currentImage = await _convertCameraImageToImage(cameraImage);
        if (currentImage != null) {
          isPageChangedHSV = _isPageChangedHSV(_previousImage, currentImage);
          _previousImage = currentImage;
        }
      }
      
      // 综合判断：任一方式检测到翻页都认为是翻页
      final isPageChanged = isPageChangedFeature || isPageChangedHSV;
      
      if (isPageChanged) {
        String detectionMethod = '';
        if (isPageChangedFeature && isPageChangedHSV) {
          detectionMethod = 'ONNX+HSV';
        } else if (isPageChangedFeature) {
          detectionMethod = 'ONNX';
        } else if (isPageChangedHSV) {
          detectionMethod = 'HSV';
        }
        
        print('$_tag: 检测到翻页动作 ($detectionMethod) - ONNX相似度: ${_currentSimilarity.toStringAsFixed(3)}, HSV相似度: ${_currentHsvSimilarity.toStringAsFixed(3)}');
        onPageTurnDetected?.call('检测到翻页动作 ($detectionMethod)');
        
        // 自动进行文本提取
        _performTextExtraction();
      }
      
      // 回调相似度更新（优先使用ONNX，其次使用HSV）
      final displaySimilarity = _isModelLoaded ? _currentSimilarity : _currentHsvSimilarity;
      onSimilarityUpdated?.call(displaySimilarity);
      
      // 打印处理完成的信息
      print('$_tag: 处理完成 - ONNX相似度: ${_currentSimilarity.toStringAsFixed(3)}, HSV相似度: ${_currentHsvSimilarity.toStringAsFixed(3)}, 是否翻页: $isPageChanged');
      
      // 处理成功，重置超时计数
      _consecutiveTimeouts = 0;
      
    } catch (e) {
      print('$_tag: 处理帧异常 - ${e.runtimeType}: $e');
    } finally {
      print('$_tag: 处理完成，设置 _isProcessing = false');
      _isProcessing = false;
    }
  }

  /// 执行文本提取
  void _performTextExtraction() {
    // 检查是否有文本提取服务和当前图像
    if (_textExtractionService == null) {
      print('$_tag: 文本提取服务未设置，跳过文本提取');
      return;
    }

    if (_lastCameraImage == null) {
      print('$_tag: 没有可用的相机图像，跳过文本提取');
      return;
    }

    if (_isExtractingText) {
      print('$_tag: 正在进行文本提取，跳过新的请求');
      return;
    }

    _isExtractingText = true;
    print('$_tag: 开始自动文本提取...');

    // 异步执行文本提取，避免阻塞检测流程
    Future.delayed(Duration(milliseconds: 500), () async {
      try {
        final extractedText = await _textExtractionService!.extractTextFromCameraImage(_lastCameraImage!);
        if (extractedText != null && extractedText.isNotEmpty) {
          print('$_tag: 文本提取成功，内容长度: ${extractedText.length}');
          onTextExtracted?.call(extractedText);
        } else {
          print('$_tag: 未提取到文本内容');
          onTextExtracted?.call('没有文字');
        }
      } catch (e) {
        print('$_tag: 文本提取失败 - $e');
        onTextExtractionError?.call('文本提取失败: $e');
      } finally {
        _isExtractingText = false;
      }
    });
  }

  /// 安排模型重新初始化
  void _scheduleModelReinit() {
    // 异步重新初始化，避免阻塞当前流程
    Future.delayed(Duration(milliseconds: 100), () async {
      try {
        print('$_tag: 开始重新初始化模型...');
        
        // 停止当前检测
        final wasDetecting = _isDetecting;
        stopDetection();
        
        // 释放当前session
        _session?.release();
        _session = null;
        _isModelLoaded = false;
        
        // 重新初始化
        final success = await initModel();
        
        if (success && wasDetecting) {
          // 如果之前在检测，重新开始检测
          startDetection();
          print('$_tag: 模型重新初始化完成，恢复检测');
        } else if (success) {
          print('$_tag: 模型重新初始化完成');
        } else {
          print('$_tag: 模型重新初始化失败');
        }
        
        // 重置超时计数
        _consecutiveTimeouts = 0;
        
      } catch (e) {
        print('$_tag: 模型重新初始化异常 - $e');
      }
    });
  }

  /// 内部处理方法（分离超时控制）
  Future<List<double>?> _processFrameInternal(CameraImage cameraImage) async {
    OrtValueTensor? inputTensor;
    List<OrtValue?>? outputs;
    
    try {
      print('$_tag: 开始图像预处理...');
      // 1. 将CameraImage转换为可处理的格式
      final imageData = _preprocessCameraImage(cameraImage);
      if (imageData == null) {
        print('$_tag: 图像预处理失败');
        return null;
      }
      print('$_tag: 图像预处理完成，数据长度: ${imageData.length}');
      
      print('$_tag: 创建输入张量...');
      // 2. 转换为Float32类型并创建输入张量
      final float32Data = Float32List.fromList(imageData);
      inputTensor = OrtValueTensor.createTensorWithDataList(
        float32Data,
        [1, 3, _inputSize, _inputSize],
      );
      print('$_tag: 输入张量创建完成，数据类型: Float32');
      
      print('$_tag: 开始 ONNX 推理...');
      final startTime = DateTime.now();
      
      // 3. 运行推理
      final inputs = {'input': inputTensor};
      outputs = await _session!.runAsync(OrtRunOptions(), inputs);
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;
      print('$_tag: ONNX 推理完成，耗时: ${duration}ms');
      
      // 4. 获取输出特征
      if (outputs != null && outputs.isNotEmpty && outputs[0] != null) {
        final outputValue = outputs[0]!.value;
        List<double> features;
        
        print('$_tag: 处理输出格式: ${outputValue.runtimeType}');
        // 处理不同的输出格式
        if (outputValue is List<List<double>>) {
          features = outputValue[0];
        } else if (outputValue is List<double>) {
          features = outputValue;
        } else {
          print('$_tag: 不支持的输出格式: ${outputValue.runtimeType}');
          return null;
        }
        
        print('$_tag: 特征提取成功，特征长度: ${features.length}');
        return features;
      }
      
      print('$_tag: 输出为空或格式错误');
      return null;
    } catch (e) {
      print('$_tag: 特征提取异常 - ${e.runtimeType}: $e');
      return null;
    } finally {
      print('$_tag: 开始资源清理...');
      try {
        // 确保资源释放
        inputTensor?.release();
        if (outputs != null) {
          for (var output in outputs) {
            output?.release();
          }
        }
        print('$_tag: 资源清理完成');
      } catch (e) {
        print('$_tag: 资源清理失败 - $e');
      }
    }
  }

  /// 预处理相机图像数据（优化版本）
  List<double>? _preprocessCameraImage(CameraImage cameraImage) {
    try {
      // 简化处理：从YUV420或BGRA格式中提取亮度信息
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _preprocessYUV420(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _preprocessBGRA8888(cameraImage);
      } else {
        print('$_tag: 不支持的图像格式 - ${cameraImage.format.group}');
        return null;
      }
    } catch (e) {
      print('$_tag: 图像预处理失败 - $e');
      return null;
    }
  }

  /// 处理YUV420格式（优化版本）
  List<double> _preprocessYUV420(CameraImage cameraImage) {
    final yPlane = cameraImage.planes[0];
    final width = cameraImage.width;
    final height = cameraImage.height;
    
    // 计算缩放参数
    final scaleX = width / _inputSize;
    final scaleY = height / _inputSize;
    
    // 预分配内存
    final inputData = List<double>.filled(_inputSize * _inputSize * 3, 0.0);
    int dataIndex = 0;
    
    // 提取和缩放Y通道数据（亮度）
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final srcX = (x * scaleX).floor().clamp(0, width - 1);
        final srcY = (y * scaleY).floor().clamp(0, height - 1);
        final srcIndex = srcY * yPlane.bytesPerRow + srcX;
        
        double yValue = 0.0;
        if (srcIndex < yPlane.bytes.length) {
          yValue = yPlane.bytes[srcIndex] / 255.0;
        }
        
        // 归一化并复制到RGB三个通道
        final normalizedValue = (yValue - _mean[0]) / _std[0];
        inputData[dataIndex++] = normalizedValue; // R
        inputData[dataIndex++] = normalizedValue; // G  
        inputData[dataIndex++] = normalizedValue; // B
      }
    }
    
    return inputData;
  }

  /// 处理BGRA8888格式（优化版本）
  List<double> _preprocessBGRA8888(CameraImage cameraImage) {
    final bytes = cameraImage.planes[0].bytes;
    final width = cameraImage.width;
    final height = cameraImage.height;
    
    final scaleX = width / _inputSize;
    final scaleY = height / _inputSize;
    
    // 预分配内存
    final inputSize = _inputSize * _inputSize;
    final rChannel = List<double>.filled(inputSize, 0.0);
    final gChannel = List<double>.filled(inputSize, 0.0);
    final bChannel = List<double>.filled(inputSize, 0.0);
    
    int channelIndex = 0;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final srcX = (x * scaleX).floor().clamp(0, width - 1);
        final srcY = (y * scaleY).floor().clamp(0, height - 1);
        final srcIndex = (srcY * width + srcX) * 4;
        
        double r = 0.0, g = 0.0, b = 0.0;
        if (srcIndex + 3 < bytes.length) {
          b = bytes[srcIndex] / 255.0;
          g = bytes[srcIndex + 1] / 255.0;
          r = bytes[srcIndex + 2] / 255.0;
        }
        
        // ImageNet标准化
        rChannel[channelIndex] = (r - _mean[0]) / _std[0];
        gChannel[channelIndex] = (g - _mean[1]) / _std[1];
        bChannel[channelIndex] = (b - _mean[2]) / _std[2];
        channelIndex++;
      }
    }
    
    // 按CHW格式组织数据
    final inputData = <double>[];
    inputData.addAll(rChannel);
    inputData.addAll(gChannel);
    inputData.addAll(bChannel);
    
    return inputData;
  }

  /// 计算余弦相似度
  double _calculateCosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) return 0.0;
    
    double dotProduct = 0;
    double norm1 = 0;
    double norm2 = 0;
    
    for (int i = 0; i < v1.length; i++) {
      dotProduct += v1[i] * v2[i];
      norm1 += v1[i] * v1[i];
      norm2 += v2[i] * v2[i];
    }
    
    if (norm1 == 0 || norm2 == 0) return 0;
    
    return dotProduct / (math.sqrt(norm1) * math.sqrt(norm2));
  }

  /// 检测页面是否变化 (基于特征相似度)
  bool _isPageChangedFeature(List<double>? previousFeature, List<double> currentFeature) {
    // 如果没有前一帧特征，认为是页面变化
    if (previousFeature == null) {
      _currentSimilarity = 0.0;
      return true;
    }
    
    // 计算余弦相似度
    final similarity = _calculateCosineSimilarity(previousFeature, currentFeature);
    _currentSimilarity = similarity;
    
    // 如果相似度小于阈值，认为是页面变化
    return similarity < _similarityThreshold;
  }

  /// 将CameraImage转换为Image对象（用于HSV处理）
  Future<img.Image?> _convertCameraImageToImage(CameraImage cameraImage) async {
    try {
      img.Image? image;
      
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        // YUV420转换为RGB
        final yPlane = cameraImage.planes[0];
        final uPlane = cameraImage.planes[1];
        final vPlane = cameraImage.planes[2];
        
        final width = cameraImage.width;
        final height = cameraImage.height;
        
        // 创建RGB图像
        image = img.Image(width: width, height: height);
        
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final yIndex = y * yPlane.bytesPerRow + x;
            final uvIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2);
            
            if (yIndex < yPlane.bytes.length && uvIndex < uPlane.bytes.length && uvIndex < vPlane.bytes.length) {
              final yValue = yPlane.bytes[yIndex];
              final uValue = uPlane.bytes[uvIndex];
              final vValue = vPlane.bytes[uvIndex];
              
              // YUV到RGB转换
              final r = (yValue + 1.402 * (vValue - 128)).clamp(0, 255).toInt();
              final g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).clamp(0, 255).toInt();
              final b = (yValue + 1.772 * (uValue - 128)).clamp(0, 255).toInt();
              
              image.setPixelRgb(x, y, r, g, b);
            }
          }
        }
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        // BGRA8888转换
        final bytes = cameraImage.planes[0].bytes;
        final width = cameraImage.width;
        final height = cameraImage.height;
        
        image = img.Image(width: width, height: height);
        
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final index = (y * width + x) * 4;
            if (index + 3 < bytes.length) {
              final b = bytes[index];
              final g = bytes[index + 1];
              final r = bytes[index + 2];
              // Alpha通道被忽略
              
              image.setPixelRgb(x, y, r, g, b);
            }
          }
        }
      }
      
      return image;
    } catch (e) {
      print('$_tag: 图像转换失败 - $e');
      return null;
    }
  }

  /// 中心裁剪图像
  img.Image _centerCrop(img.Image image) {
    final width = image.width;
    final height = image.height;
    final size = math.min(width, height);
    
    final startX = (width - size) ~/ 2;
    final startY = (height - size) ~/ 2;
    
    return img.copyCrop(image, x: startX, y: startY, width: size, height: size);
  }

  /// 计算HSV直方图
  List<int> _calculateHsvHistogram(img.Image image) {
    final histogram = List<int>.filled(_histogramBins, 0);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r / 255.0;
        final g = pixel.g / 255.0;
        final b = pixel.b / 255.0;
        
        // RGB转HSV
        final max = math.max(r, math.max(g, b));
        final min = math.min(r, math.min(g, b));
        final delta = max - min;
        
        double h = 0.0;
        if (delta != 0) {
          if (max == r) {
            h = 60 * (((g - b) / delta) % 6);
          } else if (max == g) {
            h = 60 * (((b - r) / delta) + 2);
          } else {
            h = 60 * (((r - g) / delta) + 4);
          }
        }
        
        if (h < 0) h += 360;
        
        // 将H值映射到直方图bin
        final bin = (h / 360.0 * _histogramBins).floor().clamp(0, _histogramBins - 1);
        histogram[bin]++;
      }
    }
    
    return histogram;
  }

  /// 比较两个直方图的相似度（巴氏系数）
  double _compareHistograms(List<int> hist1, List<int> hist2) {
    if (hist1.length != hist2.length) return 1.0;
    
    // 归一化直方图
    final sum1 = hist1.reduce((a, b) => a + b);
    final sum2 = hist2.reduce((a, b) => a + b);
    
    if (sum1 == 0 || sum2 == 0) return 1.0;
    
    final normalized1 = hist1.map((e) => e / sum1).toList();
    final normalized2 = hist2.map((e) => e / sum2).toList();
    
    // 计算巴氏系数
    double bhattacharyya = 0.0;
    for (int i = 0; i < normalized1.length; i++) {
      bhattacharyya += math.sqrt(normalized1[i] * normalized2[i]);
    }
    
    // 巴氏距离 = -ln(巴氏系数)
    return -math.log(bhattacharyya.clamp(1e-10, 1.0));
  }

  /// 基于HSV特征检测页面是否变化
  bool _isPageChangedHSV(img.Image? previousImage, img.Image currentImage) {
    final startTime = DateTime.now();
    
    try {
      // 如果没有前一帧图像，认为是页面变化
      if (previousImage == null) {
        _currentHsvSimilarity = 1.0;
        return true;
      }
      
      // 裁剪中央区域
      final prevCenter = _centerCrop(previousImage);
      final currentCenter = _centerCrop(currentImage);
      
      // 计算HSV直方图
      final hist1 = _calculateHsvHistogram(prevCenter);
      final hist2 = _calculateHsvHistogram(currentCenter);
      
      // 比较直方图相似度
      final similarity = _compareHistograms(hist1, hist2);
      _currentHsvSimilarity = similarity;
      
      final endTime = DateTime.now();
      final elapsed = endTime.difference(startTime).inMilliseconds;
      
      print('$_tag: HSV相似度: ${similarity.toStringAsFixed(3)}, 耗时: ${elapsed}ms');
      
      // 如果相似度大于阈值，认为是页面变化
      return similarity > _hsvThreshold;
      
    } catch (e) {
      print('$_tag: HSV检测失败 - $e');
      _currentHsvSimilarity = 0.0;
      return false;
    }
  }

  /// 释放资源
  void dispose() {
    stopDetection();
    _session?.release();
    _session = null;
    _isModelLoaded = false;
    _textExtractionService = null;
    _lastCameraImage = null;
    _isExtractingText = false;
    _previousImage = null;
    _useHsvDetection = false;
    print('$_tag: 资源已释放');
  }

  // Getters
  bool get isModelLoaded => _isModelLoaded;
  bool get isDetecting => _isDetecting;
  bool get isProcessing => _isProcessing; // 新增：检查是否正在处理
  bool get useHsvDetection => _useHsvDetection; // HSV检测是否启用
  double get lastSimilarity => _currentSimilarity;
  double get lastHsvSimilarity => _currentHsvSimilarity; // HSV相似度
  double get averageSimilarity => _currentSimilarity;
} 