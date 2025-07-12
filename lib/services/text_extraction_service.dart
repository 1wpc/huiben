import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// 支持的视觉模型类型
enum VisualModelType { doubao, glm }

/// 文本提取服务
/// 使用豆包模型从图片中提取朗读内容文字
class TextExtractionService {
  static const String _tag = 'TextExtractionService';
  
  // 豆包模型API配置
  static const String _doubaoApiUrl = 'https://ark.cn-beijing.volces.com/api/v3/chat/completions';
  static const String _doubaoModelId = 'doubao-seed-1-6-250615';
  // GLM视觉模型API配置（假设为本地或远程API，需用户配置）
  static const String _glmApiUrl = 'https://open.bigmodel.cn/api/paas/v4/chat/completions'; // 可根据实际情况修改
  
  late Dio _dio;
  String? _apiKey;
  VisualModelType _modelType = VisualModelType.doubao;
  String? _glmPrompt;
  
  // 回调函数
  Function(String)? onTextExtracted;
  Function(String)? onTextChunk;  // 流式文本片段回调
  Function(String)? onError;
  Function(String)? onStatusChanged;
  
  /// 初始化服务，支持选择模型类型
  Future<bool> init({required String apiKey, VisualModelType modelType = VisualModelType.doubao}) async {
    try {
      _apiKey = apiKey;
      _modelType = modelType;
      _dio = Dio();
      _dio.options = BaseOptions(
        baseUrl: modelType == VisualModelType.doubao ? _doubaoApiUrl : _glmApiUrl,
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
      debugPrint('$_tag: 服务初始化成功, 当前模型: $_modelType');
      return true;
      
    } catch (e) {
      debugPrint('$_tag: 服务初始化失败 - $e');
      onError?.call('服务初始化失败: $e');
      return false;
    }
  }
  
  /// 从相机图像中提取文本（根据模型类型自动选择API）
  Future<String?> extractTextFromCameraImage(CameraImage cameraImage) async {
    try {
      onStatusChanged?.call('正在处理图像...');
      debugPrint('$_tag: 开始处理相机图像 - 格式:  [32m${cameraImage.format.group} [0m, 尺寸: ${cameraImage.width}x${cameraImage.height}');
      
      // 将CameraImage转换为Uint8List
      final imageBytes = await _convertCameraImageToBytes(cameraImage);
      if (imageBytes == null) {
        throw Exception('图像转换失败');
      }
      
      debugPrint('$_tag: 图像转换成功 - JPEG字节数: ${imageBytes.length}');
      
      // 验证JPEG格式
      if (imageBytes.length < 10 || 
          imageBytes[0] != 0xFF || imageBytes[1] != 0xD8) {
        debugPrint('$_tag: 警告：生成的数据可能不是有效的JPEG格式');
      } else {
        debugPrint('$_tag: JPEG格式验证通过');
      }
      
      // 转换为base64
      final base64Image = base64Encode(imageBytes);
      debugPrint('$_tag: Base64编码完成 - 长度: ${base64Image.length}');
      
      String? extractedText;
      if (_modelType == VisualModelType.doubao) {
        extractedText = await _callDoubaoAPI(base64Image);
      } else {
        extractedText = await _callGLMAPI(base64Image);
      }
      
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
  
  /// 从图片文件中提取文本（根据模型类型自动选择API）
  Future<String?> extractTextFromImageBytes(Uint8List imageBytes) async {
    try {
      onStatusChanged?.call('正在分析图片...');
      
      // 转换为base64
      final base64Image = base64Encode(imageBytes);
      
      String? extractedText;
      if (_modelType == VisualModelType.doubao) {
        extractedText = await _callDoubaoAPI(base64Image);
      } else {
        extractedText = await _callGLMAPI(base64Image);
      }
      
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
        'model': _doubaoModelId,
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
        'stream': true
      };
      
      debugPrint('$_tag: 开始调用豆包模型API（流式）...');
      
      StringBuffer fullText = StringBuffer();
      
      try {
        // 发送流式请求
        final response = await _dio.post<ResponseBody>(
          '',
          data: requestData,
          options: Options(responseType: ResponseType.stream),
        );
        
        if (response.statusCode == 200 && response.data != null) {
          // 处理流式响应  
          await for (final bytes in response.data!.stream) {
            final chunk = utf8.decode(bytes);
            final lines = chunk.split('\n');
            
            for (final line in lines) {
              if (line.trim().isEmpty) continue;
              
              // 处理 Server-Sent Events 格式
              if (line.startsWith('data: ')) {
                final jsonString = line.substring(6).trim();
                if (jsonString == '[DONE]') {
                  debugPrint('$_tag: 流式响应完成');
                  break;
                }
                
                try {
                  final data = json.decode(jsonString);
                  if (data['choices'] != null && 
                      data['choices'].isNotEmpty &&
                      data['choices'][0]['delta'] != null &&
                      data['choices'][0]['delta']['content'] != null) {
                    
                    final content = data['choices'][0]['delta']['content'];
                    if (content != null && content.toString().isNotEmpty) {
                      fullText.write(content);
                      
                      // 触发流式文本片段回调
                      onTextChunk?.call(content.toString());
                      debugPrint('$_tag: 接收文本片段: "${content.toString()}"');
                    }
                  }
                } catch (e) {
                  debugPrint('$_tag: 解析流式响应失败: $e, 内容: $jsonString');
                }
              }
            }
          }
          
          final finalText = fullText.toString().trim();
          if (finalText.isNotEmpty) {
            debugPrint('$_tag: 流式文本提取成功，总长度: ${finalText.length}');
            return finalText;
          } else {
            throw Exception('流式API返回内容为空');
          }
        } else {
          throw Exception('流式API调用失败: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('$_tag: 流式API处理失败: $e');
        throw e;
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

  /// 调用GLM视觉模型API
  Future<String?> _callGLMAPI(String base64Image) async {
    try {
      onStatusChanged?.call('正在调用GLM视觉模型...');
      // 构建GLM官方API请求体
      final String modelName = 'glm-4v-flash'; // 可根据需要配置
      final String apiKey = _apiKey ?? '';
      final String imageData = 'data:image/jpeg;base64,$base64Image';
      final requestData = {
        'model': modelName,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': imageData}
              },
              {
                'type': 'text',
                'text': '请提取这张图中所示书或者绘本上的所有文字内容，并按照原文的格式整理输出，如果没有输出“没有文字”'
              }
            ]
          }
        ],
        'stream': true
      };
      debugPrint('$_tag: 开始调用GLM视觉模型API...');
      final response = await _dio.post(
        '',
        data: jsonEncode(requestData),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          responseType: ResponseType.stream,
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        // 处理流式响应
        StringBuffer fullText = StringBuffer();
        await for (final bytes in response.data!.stream) {
          final chunk = utf8.decode(bytes);
          final lines = chunk.split('\n');
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            if (line.startsWith('data: ')) {
              final jsonString = line.substring(6).trim();
              if (jsonString == '[DONE]') {
                debugPrint('$_tag: GLM流式响应完成');
                break;
              }
              try {
                final data = json.decode(jsonString);
                if (data['choices'] != null &&
                    data['choices'].isNotEmpty &&
                    data['choices'][0]['delta'] != null &&
                    data['choices'][0]['delta']['content'] != null) {
                  final content = data['choices'][0]['delta']['content'];
                  if (content != null && content.toString().isNotEmpty) {
                    fullText.write(content);
                    onTextChunk?.call(content.toString());
                    debugPrint('$_tag: GLM片段: ${content.toString()}');
                  }
                }
              } catch (e) {
                debugPrint('$_tag: 解析GLM流式响应失败: $e, 内容: $jsonString');
              }
            }
          }
        }
        final finalText = fullText.toString().trim();
        if (finalText.isNotEmpty) {
          debugPrint('$_tag: GLM流式文本提取成功，总长度: ${finalText.length}');
          return finalText;
        } else {
          throw Exception('GLM流式API返回内容为空');
        }
      } else {
        throw Exception('GLM API调用失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('$_tag: GLM API调用异常 - $e');
      throw Exception('GLM API调用异常: $e');
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
    try {
      final width = cameraImage.width;
      final height = cameraImage.height;
      
      // 创建RGB图像
      final image = img.Image(width: width, height: height);
      
      final yPlane = cameraImage.planes[0];
      final uPlane = cameraImage.planes[1];
      final vPlane = cameraImage.planes[2];
      
      final yData = yPlane.bytes;
      final uData = uPlane.bytes;
      final vData = vPlane.bytes;
      
      // YUV420转RGB
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIndex = y * yPlane.bytesPerRow + x;
          final uvIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2);
          
          if (yIndex < yData.length && uvIndex < uData.length && uvIndex < vData.length) {
            final yValue = yData[yIndex];
            final uValue = uData[uvIndex] - 128;
            final vValue = vData[uvIndex] - 128;
            
            // YUV到RGB转换
            int r = (yValue + 1.402 * vValue).round().clamp(0, 255);
            int g = (yValue - 0.344136 * uValue - 0.714136 * vValue).round().clamp(0, 255);
            int b = (yValue + 1.772 * uValue).round().clamp(0, 255);
            
            image.setPixelRgb(x, y, r, g, b);
          }
        }
      }
      
      // 编码为JPEG
      final jpegBytes = img.encodeJpg(image, quality: 85);
      return Uint8List.fromList(jpegBytes);
    } catch (e) {
      debugPrint('$_tag: YUV420转JPEG失败 - $e');
      // 降级方案：使用Y通道作为灰度图
      return _convertYUV420ToGrayscaleJPEG(cameraImage);
    }
  }
  
  /// 将BGRA8888格式转换为JPEG
  Uint8List _convertBGRA8888ToJPEG(CameraImage cameraImage) {
    try {
      final bytes = cameraImage.planes[0].bytes;
      final width = cameraImage.width;
      final height = cameraImage.height;
      
      // 创建RGB图像
      final image = img.Image(width: width, height: height);
      
      // 转换BGRA到RGB
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixelIndex = (y * width + x) * 4;
          
          if (pixelIndex + 3 < bytes.length) {
            final b = bytes[pixelIndex];
            final g = bytes[pixelIndex + 1];
            final r = bytes[pixelIndex + 2];
            // Alpha通道在pixelIndex + 3，我们忽略它
            
            image.setPixelRgb(x, y, r, g, b);
          }
        }
      }
      
      // 编码为JPEG
      final jpegBytes = img.encodeJpg(image, quality: 85);
      return Uint8List.fromList(jpegBytes);
    } catch (e) {
      debugPrint('$_tag: BGRA8888转JPEG失败 - $e');
      // 降级方案：创建空白图像
      final image = img.Image(width: 640, height: 480);
      img.fill(image, color: img.ColorRgb8(128, 128, 128));
      final jpegBytes = img.encodeJpg(image);
      return Uint8List.fromList(jpegBytes);
    }
  }

  /// YUV420转灰度JPEG（降级方案）
  Uint8List _convertYUV420ToGrayscaleJPEG(CameraImage cameraImage) {
    try {
      final width = cameraImage.width;
      final height = cameraImage.height;
      final yPlane = cameraImage.planes[0];
      
      // 创建灰度图像
      final image = img.Image(width: width, height: height);
      
      // 使用Y通道作为灰度值
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIndex = y * yPlane.bytesPerRow + x;
          if (yIndex < yPlane.bytes.length) {
            final grayValue = yPlane.bytes[yIndex];
            image.setPixelRgb(x, y, grayValue, grayValue, grayValue);
          }
        }
      }
      
      // 编码为JPEG
      final jpegBytes = img.encodeJpg(image, quality: 85);
      return Uint8List.fromList(jpegBytes);
    } catch (e) {
      debugPrint('$_tag: 灰度图转换失败 - $e');
      // 最后的降级方案：创建空白图像
      final image = img.Image(width: 640, height: 480);
      img.fill(image, color: img.ColorRgb8(128, 128, 128));
      final jpegBytes = img.encodeJpg(image);
      return Uint8List.fromList(jpegBytes);
    }
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