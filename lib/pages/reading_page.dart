import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/page_turn_detector.dart';
import '../services/text_extraction_service.dart';
import '../utilis/env.dart';

// 阅读页面 - 包含摄像头功能和翻页检测
class ReadingPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const ReadingPage({super.key, required this.cameras});

  @override
  State<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<ReadingPage> {
  CameraController? _controller;
  PageTurnDetector? _pageTurnDetector;
  TextExtractionService? _textExtractionService;
  
  bool _isReading = false;
  String _statusText = '准备开始阅读';
  bool _isInitialized = false;
  bool _isModelLoaded = false;
  double _currentSimilarity = 1.0;
  int _pageCount = 1;
  String _lastDetectionTime = '';
  String _extractedText = ''; // 存储提取的文本
  bool _isTextExtractionEnabled = false; // 文本提取服务是否可用

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _initializeCamera();
    await _initializeTextExtractionService();
    await _initializePageTurnDetector();
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() {
        _statusText = '未找到摄像头';
      });
      return;
    }

    // 请求摄像头权限
    var status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _statusText = '摄像头权限被拒绝';
      });
      return;
    }

    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.medium,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _statusText = '摄像头已就绪';
        });
      }
    } catch (e) {
      setState(() {
        _statusText = '摄像头初始化失败: $e';
      });
    }
  }

  Future<void> _initializeTextExtractionService() async {
    try {
      _textExtractionService = TextExtractionService();
      
      final apiKey = Env.doubaoApiKey; 
      
      final success = await _textExtractionService!.init(apiKey: apiKey);
      
      setState(() {
        _isTextExtractionEnabled = success;
        if (success) {
          _statusText = '文本提取服务已就绪';
        } else {
          _statusText = '文本提取服务初始化失败';
        }
      });
      
      if (success) {
        debugPrint('文本提取服务初始化成功');
      } else {
        debugPrint('文本提取服务初始化失败');
      }
    } catch (e) {
      setState(() {
        _isTextExtractionEnabled = false;
        _statusText = '文本提取服务初始化异常: $e';
      });
      debugPrint('文本提取服务初始化异常: $e');
    }
  }

  Future<void> _initializePageTurnDetector() async {
    _pageTurnDetector = PageTurnDetector();
    
    // 设置回调函数
    _pageTurnDetector!.onPageTurnDetected = (message) {
      setState(() {
        _pageCount++;
        _lastDetectionTime = DateTime.now().toString().substring(11, 19);
        _statusText = '✅ 检测到翻页 - 继续监测中';
      });
      // 静默记录翻页，不显示弹窗
      print('翻页检测: 第 $_pageCount 页，时间: $_lastDetectionTime');
      
      // 3秒后恢复正常状态文本
      Future.delayed(const Duration(seconds: 3), () {
        if (_isReading && mounted) {
          setState(() {
            _statusText = '智能翻页检测中 - 正在静默监测翻页动作';
          });
        }
      });
    };
    
    _pageTurnDetector!.onSimilarityUpdated = (similarity) {
      setState(() {
        _currentSimilarity = similarity;
      });
    };
    
    _pageTurnDetector!.onStatusChanged = (status) {
      setState(() {
        _statusText = status;
      });
    };

    // 设置文本提取回调
    _pageTurnDetector!.onTextExtracted = (text) {
      setState(() {
        _extractedText = text;
      });
      print('提取的文本: $text');
      // 可以在这里添加更多的文本处理逻辑，比如语音朗读
    };

    _pageTurnDetector!.onTextExtractionError = (error) {
      setState(() {
        _extractedText = '文本提取失败: $error';
      });
      print('文本提取错误: $error');
    };

    // 设置文本提取服务（如果可用）
    if (_isTextExtractionEnabled && _textExtractionService != null) {
      _pageTurnDetector!.setTextExtractionService(_textExtractionService!);
    }

    // 初始化模型
    final success = await _pageTurnDetector!.initModel();
    setState(() {
      _isModelLoaded = success;
      if (success) {
        _statusText = '翻页检测已就绪';
      }
    });
  }

  void _startReading() {
    if (!_isInitialized || !_isModelLoaded) {
      _showErrorDialog('请等待系统初始化完成');
      return;
    }

    setState(() {
      _isReading = true;
      _statusText = '智能翻页检测中 - 正在静默监测翻页动作';
      _pageCount = 1;
      _lastDetectionTime = ''; // 重置检测时间
    });

    // 开始翻页检测
    _pageTurnDetector?.startDetection();
    
    // 开始图像流处理
    _controller?.startImageStream((CameraImage image) {
      if (_isReading) {
        _pageTurnDetector?.processFrame(image);
      }
    });
  }

  void _stopReading() {
    setState(() {
      _isReading = false;
      _statusText = '阅读已停止 - 共检测到 $_pageCount 页';
    });

    // 停止翻页检测
    _pageTurnDetector?.stopDetection();
    
    // 停止图像流
    _controller?.stopImageStream();
  }



  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('错误'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _pageTurnDetector?.dispose();
    _textExtractionService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // 摄像头预览区域
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: _isInitialized && _controller != null
                  ? CameraPreview(_controller!)
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 20),
                          Text(
                            _statusText,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          
          // 检测信息显示区域
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              children: [                
                if (_isReading) ...[
                  // 页面计数和检测状态
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          const Icon(Icons.book, color: Colors.blue),
                          const SizedBox(height: 4),
                          Text('第 $_pageCount 页', 
                               style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        children: [
                          const Icon(Icons.analytics, color: Colors.orange),
                          const SizedBox(height: 4),
                          Text('相似度: ${(_currentSimilarity * 100).toStringAsFixed(1)}%',
                               style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      Column(
                        children: [
                          Icon(
                            _isModelLoaded ? Icons.check_circle : Icons.error,
                            color: _isModelLoaded ? Colors.green : Colors.red,
                          ),
                          const SizedBox(height: 4),
                          Text(_isModelLoaded ? '模型就绪' : '模型未加载',
                               style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      Column(
                        children: [
                          Icon(
                            _isTextExtractionEnabled ? Icons.text_fields : Icons.text_fields_outlined,
                            color: _isTextExtractionEnabled ? Colors.purple : Colors.grey,
                          ),
                          const SizedBox(height: 4),
                          Text(_isTextExtractionEnabled ? '文本提取' : '文本未启用',
                               style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  
                  // 最后检测时间显示
                  if (_lastDetectionTime.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule, size: 16, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            '最后检测: $_lastDetectionTime',
                            style: const TextStyle(fontSize: 12, color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  
                  // 相似度进度条
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('页面稳定度:', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: _currentSimilarity,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _currentSimilarity > 0.7 ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          
          // 提取文本显示区域
          if (_extractedText.isNotEmpty) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.text_fields, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '提取的文本内容:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      _extractedText,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // 控制按钮区域
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isReading ? null : _startReading,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow),
                        SizedBox(width: 8),
                        Text('开始阅读', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: !_isReading ? null : _stopReading,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.stop),
                        SizedBox(width: 8),
                        Text('停止', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 