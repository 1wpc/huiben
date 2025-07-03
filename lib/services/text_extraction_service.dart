import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// 文本提取服务
/// 使用豆包模型从图片中提取朗读内容文字
class TextExtractionService {
  static const String _tag = 'TextExtractionService';
  
  // 豆包模型API配置
  static const String _apiUrl = 'https://ark.cn-beijing.volces.com/api/v3/chat/completions';
  static const String _modelId = 'doubao-seed-1-6-250615';
  
  late Dio _dio;
  String? _apiKey;
  
  // 回调函数
  Function(String)? onTextExtracted;
  Function(String)? onError;
  Function(String)? onStatusChanged;
  
  /// 初始化服务
  Future<bool> init({required String apiKey}) async {
    try {
      _apiKey = apiKey;
      
      // 初始化Dio
      _dio = Dio();
      _dio.options = BaseOptions(
        baseUrl: _apiUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
      );
      
      // 添加拦截器用于日志
      if (kDebugMode) {
        _dio.interceptors.add(LogInterceptor(
          requestBody: true,
          responseBody: true,
          logPrint: (obj) => debugPrint('$_tag: $obj'),
        ));
      }
      
      onStatusChanged?.call('文本提取服务已初始化');
      debugPrint('$_tag: 服务初始化成功');
      return true;
      
    } catch (e) {
      debugPrint('$_tag: 服务初始化失败 - $e');
      onError?.call('服务初始化失败: $e');
      return false;
    }
  }
  
  /// 从相机图像中提取文本
  Future<String?> extractTextFromCameraImage(CameraImage cameraImage) async {
    try {
      onStatusChanged?.call('正在处理图像...');
      
      // 将CameraImage转换为Uint8List
      final imageBytes = await _convertCameraImageToBytes(cameraImage);
      if (imageBytes == null) {
        throw Exception('图像转换失败');
      }
      
      // 转换为base64
      final base64Image = base64Encode(imageBytes);
      
      // 调用豆包模型API
      final extractedText = await _callDoubaoAPI(base64Image);
      
      if (extractedText != null) {
        onTextExtracted?.call(extractedText);
        onStatusChanged?.call('文本提取成功');
        return extractedText;
      } else {
        throw Exception('文本提取失败');
      }
      
    } catch (e) {
      debugPrint('$_tag: 文本提取失败 - $e');
      onError?.call('文本提取失败: $e');
      onStatusChanged?.call('文本提取失败');
      return null;
    }
  }
  
  /// 从图片文件中提取文本
  Future<String?> extractTextFromImageBytes(Uint8List imageBytes) async {
    try {
      onStatusChanged?.call('正在分析图片...');
      
      // 转换为base64
      final base64Image = base64Encode(imageBytes);
      
      // 调用豆包模型API
      final extractedText = await _callDoubaoAPI(base64Image);
      
      if (extractedText != null) {
        onTextExtracted?.call(extractedText);
        onStatusChanged?.call('文本提取成功');
        return extractedText;
      } else {
        throw Exception('文本提取失败');
      }
      
    } catch (e) {
      debugPrint('$_tag: 文本提取失败 - $e');
      onError?.call('文本提取失败: $e');
      onStatusChanged?.call('文本提取失败');
      return null;
    }
  }
  
  /// 调用豆包模型API
  Future<String?> _callDoubaoAPI(String base64Image) async {
    try {
      onStatusChanged?.call('正在调用豆包模型...');
      
      // 构建请求体
      final requestData = {
        'model': _modelId,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个专业的文字识别助手。请仔细分析图片中的所有文字内容，准确提取出所有可读的文本。请按照原文的格式和顺序输出，保持文本的完整性和可读性。如果是书页或文档，请按照从左到右、从上到下的阅读顺序提取文字。'
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': '请提取这张图中所示书或者绘本上的所有文字内容，并按照原文的格式整理输出，如果没有输出“没有文字”'
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$base64Image'
                }
              }
            ]
          }
        ],
        'max_tokens': 4000,
        'temperature': 0.1,
        'top_p': 0.9,
        'stream': false
      };
      
      debugPrint('$_tag: 开始调用豆包模型API...');
      
      // 发送请求
      final response = await _dio.post(
        '',
        data: requestData,
      );
      
      debugPrint('$_tag: API调用成功，状态码: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final responseData = response.data;
        
        // 解析响应
        if (responseData['choices'] != null && 
            responseData['choices'].isNotEmpty &&
            responseData['choices'][0]['message'] != null) {
          
          final content = responseData['choices'][0]['message']['content'];
          
          if (content != null && content.toString().trim().isNotEmpty) {
            debugPrint('$_tag: 文本提取成功，内容长度: ${content.toString().length}');
            return content.toString().trim();
          } else {
            throw Exception('API返回内容为空');
          }
        } else {
          throw Exception('API返回格式错误');
        }
      } else {
        throw Exception('API调用失败: ${response.statusCode}');
      }
      
    } catch (e) {
      if (e is DioException) {
        debugPrint('$_tag: 网络请求失败 - ${e.message}');
        if (e.response != null) {
          debugPrint('$_tag: 响应数据: ${e.response?.data}');
        }
        throw Exception('网络请求失败: ${e.message}');
      } else {
        debugPrint('$_tag: API调用异常 - $e');
        throw Exception('API调用异常: $e');
      }
    }
  }
  
  /// 将CameraImage转换为Uint8List
  Future<Uint8List?> _convertCameraImageToBytes(CameraImage cameraImage) async {
    try {
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420ToJPEG(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888ToJPEG(cameraImage);
      } else {
        debugPrint('$_tag: 不支持的图像格式: ${cameraImage.format.group}');
        return null;
      }
    } catch (e) {
      debugPrint('$_tag: 图像转换失败 - $e');
      return null;
    }
  }
  
  /// 将YUV420格式转换为JPEG
  Uint8List _convertYUV420ToJPEG(CameraImage cameraImage) {
    final int width = cameraImage.width;
    final int height = cameraImage.height;
    final int ySize = width * height;
    final int uvSize = ySize ~/ 4;
    
    final Uint8List yuvBytes = Uint8List(ySize + uvSize * 2);
    
    // Y plane
    final yPlane = cameraImage.planes[0];
    yuvBytes.setRange(0, ySize, yPlane.bytes);
    
    // U and V planes
    final uPlane = cameraImage.planes[1];
    final vPlane = cameraImage.planes[2];
    
    for (int i = 0; i < uvSize; i++) {
      yuvBytes[ySize + i] = uPlane.bytes[i];
      yuvBytes[ySize + uvSize + i] = vPlane.bytes[i];
    }
    
    // 这里简化处理，实际应用中可能需要使用图像处理库
    // 返回Y通道作为灰度图像的简化版本
    return yuvBytes.sublist(0, ySize);
  }
  
  /// 将BGRA8888格式转换为JPEG
  Uint8List _convertBGRA8888ToJPEG(CameraImage cameraImage) {
    final bytes = cameraImage.planes[0].bytes;
    final width = cameraImage.width;
    final height = cameraImage.height;
    
    // 转换BGRA到RGB
    final rgbBytes = Uint8List(width * height * 3);
    for (int i = 0; i < bytes.length; i += 4) {
      final b = bytes[i];
      final g = bytes[i + 1];
      final r = bytes[i + 2];
      // 跳过Alpha通道
      
      final pixelIndex = i ~/ 4;
      rgbBytes[pixelIndex * 3] = r;
      rgbBytes[pixelIndex * 3 + 1] = g;
      rgbBytes[pixelIndex * 3 + 2] = b;
    }
    
    return rgbBytes;
  }
  
  /// 处理提取的文本（可以添加文本后处理逻辑）
  String processExtractedText(String text) {
    // 基本的文本清理
    String processedText = text.trim();
    
    // 移除多余的空行
    processedText = processedText.replaceAll(RegExp(r'\n\s*\n'), '\n\n');
    
    // 移除行首行尾的空白字符
    processedText = processedText.split('\n')
        .map((line) => line.trim())
        .join('\n');
    
    return processedText;
  }
  
  /// 释放资源
  void dispose() {
    _dio.close();
    debugPrint('$_tag: 资源已释放');
  }
}

/// 文本提取结果
class TextExtractionResult {
  final String text;
  final DateTime timestamp;
  final bool success;
  final String? error;
  
  TextExtractionResult({
    required this.text,
    required this.timestamp,
    required this.success,
    this.error,
  });
  
  factory TextExtractionResult.success(String text) {
    return TextExtractionResult(
      text: text,
      timestamp: DateTime.now(),
      success: true,
    );
  }
  
  factory TextExtractionResult.error(String error) {
    return TextExtractionResult(
      text: '',
      timestamp: DateTime.now(),
      success: false,
      error: error,
    );
  }
} 