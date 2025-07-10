import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 讯飞TTS语音合成服务
class XunfeiTTSService {
  static const String _tag = 'XunfeiTTSService';
  
  // Base URL for Xunfei TTS WebSocket API
  static const String _baseUrl = 'wss://tts-api.xfyun.cn/v2/tts';
  
  String? _appId;
  String? _apiKey;
  String? _apiSecret;
  
  WebSocketChannel? _channel;
  AudioPlayer? _audioPlayer;
  List<int> _audioBuffer = [];
  
  // 回调函数
  Function(String)? onStatusChanged;
  Function(String)? onError;
  Function()? onSynthesisComplete;
  Function()? onPlaybackComplete;
  
  bool _isConnected = false;
  bool _isPlaying = false;
  
  /// 初始化服务
  Future<bool> init({
    required String appId,
    required String apiKey,
    required String apiSecret,
  }) async {
    try {
      // 验证参数
      if (appId.isEmpty || apiKey.isEmpty || apiSecret.isEmpty) {
        throw Exception('appId、apiKey 和 apiSecret 不能为空');
      }
      
      if (apiKey == 'your_api_key' || apiSecret == 'your_api_secret') {
        throw Exception('请设置正确的 apiKey 和 apiSecret');
      }

      _appId = appId;
      _apiKey = apiKey;
      _apiSecret = apiSecret;
      
      // 初始化音频播放器
      _audioPlayer = AudioPlayer();
      _audioPlayer!.onPlayerComplete.listen((_) {
        _isPlaying = false;
        onPlaybackComplete?.call();
        debugPrint('$_tag: 音频播放完成');
      });
      
      onStatusChanged?.call('TTS服务已初始化');
      debugPrint('$_tag: 服务初始化成功 - AppID: ${_appId!.substring(0, 4)}..., ApiKey: ${_apiKey!.substring(0, 4)}...');
      return true;
      
    } catch (e) {
      debugPrint('$_tag: 服务初始化失败 - $e');
      onError?.call('TTS服务初始化失败: $e');
      return false;
    }
  }
  
  /// 合成并播放文本
  Future<bool> synthesizeAndPlay(String text) async {
    if (text.trim().isEmpty) {
      debugPrint('$_tag: 文本为空，跳过合成');
      return false;
    }
    
    try {
      onStatusChanged?.call('正在合成语音...');
      
      // 连接WebSocket
      if (!await _connectWebSocket()) {
        throw Exception('WebSocket连接失败');
      }
      
      // 发送合成请求
      await _sendSynthesisRequest(text);
      
      return true;
      
    } catch (e) {
      debugPrint('$_tag: 语音合成失败 - $e');
      onError?.call('语音合成失败: $e');
      _cleanup();
      return false;
    }
  }
  
  /// 连接WebSocket
  Future<bool> _connectWebSocket() async {
    try {
      if (_isConnected && _channel != null) {
        return true;
      }
      
      // 生成鉴权URL
      final authUri = _generateAuthUri();
      debugPrint('$_tag: 正在连接WebSocket...');
      debugPrint('$_tag: 授权信息 - AppID: ${_appId!.substring(0, 4)}...');
      debugPrint('$_tag: 目标URL: $authUri');
      
      // 建立WebSocket连接
      final socket = await WebSocket.connect(authUri.toString());
      _channel = IOWebSocketChannel(socket);
      
      // 监听消息
      _channel!.stream.listen(
        _onWebSocketMessage,
        onError: _onWebSocketError,
        onDone: _onWebSocketDone,
      );
      
      _isConnected = true;
      debugPrint('$_tag: WebSocket连接成功');
      return true;
      
    } catch (e) {
      debugPrint('$_tag: WebSocket连接失败 - $e');
      return false;
    }
  }
  
  /// 生成鉴权URL
  Uri _generateAuthUri() {
    // 生成RFC1123格式的时间戳
    final date = HttpDate.format(DateTime.now().toUtc());
    
    // 生成签名字符串
    final signatureOrigin = 'host: tts-api.xfyun.cn\n'
        'date: $date\n'
        'GET /v2/tts HTTP/1.1';
    
    // 计算签名
    final signatureBytes = utf8.encode(signatureOrigin);
    final secretBytes = utf8.encode(_apiSecret!);
    final hmac = Hmac(sha256, secretBytes);
    final digest = hmac.convert(signatureBytes);
    final signature = base64.encode(digest.bytes);
    
    // 生成authorization
    final authorization = 'api_key="$_apiKey", '
        'algorithm="hmac-sha256", '
        'headers="host date request-line", '
        'signature="$signature"';
    
    final authorizationBase64 = base64.encode(utf8.encode(authorization));
    
    // 构建最终URL，注意不要添加额外的参数或修改格式
    return Uri.parse(
      'wss://tts-api.xfyun.cn/v2/tts'
      '?authorization=$authorizationBase64'
      '&date=${Uri.encodeComponent(date)}'
      '&host=tts-api.xfyun.cn'
    );
  }
  
  /// 发送合成请求
  Future<void> _sendSynthesisRequest(String text) async {
    final request = {
      'common': {
        'app_id': _appId,
      },
      'business': {
        'aue': 'lame',         // 音频编码格式：lame代表mp3
        'auf': 'audio/L16;rate=16000',  // 音频采样率
        'vcn': 'xiaoyan',      // 发音人
        'speed': 50,           // 语速
        'volume': 80,          // 音量
        'pitch': 50,           // 音高
        'sfl': 1,              // 开启流式返回
        'bgs': 0,              // 背景音
        'tte': 'UTF8',         // 文本编码
      },
      'data': {
        'status': 2,           // 数据状态：2表示一次性传输
        'text': base64.encode(utf8.encode(text)),
      },
    };
    
    _channel!.sink.add(json.encode(request));
    debugPrint('$_tag: 发送合成请求，文本长度: ${text.length}');
  }
  
  /// 处理WebSocket消息
  void _onWebSocketMessage(dynamic message) {
    try {
      final data = json.decode(message);
      
      if (data['code'] != 0) {
        throw Exception('TTS错误: ${data['message']}');
      }
      
      // 处理音频数据
      if (data['data'] != null && data['data']['audio'] != null) {
        final audioBase64 = data['data']['audio'];
        final audioBytes = base64.decode(audioBase64);
        
        _audioBuffer.addAll(audioBytes);
        debugPrint('$_tag: 接收音频数据，大小: ${audioBytes.length}');
      }
      
      // 检查是否为最后一帧
      if (data['data'] != null && data['data']['status'] == 2) {
        debugPrint('$_tag: 音频合成完成，总大小: ${_audioBuffer.length}');
        _playAudio();
        _cleanup();
      }
      
    } catch (e) {
      debugPrint('$_tag: 处理WebSocket消息失败 - $e');
      onError?.call('处理音频数据失败: $e');
    }
  }
  
  /// 播放合成的音频
  Future<void> _playAudio() async {
    if (_audioBuffer.isEmpty) {
      debugPrint('$_tag: 音频缓冲区为空');
      return;
    }
    
    try {
      onStatusChanged?.call('正在播放语音...');
      _isPlaying = true;
      
      // 转换为音频格式并播放
      final audioData = Uint8List.fromList(_audioBuffer);
      
      // 使用内存播放音频
      await _audioPlayer!.play(
        BytesSource(audioData),
        mode: PlayerMode.mediaPlayer,
      );
      
      debugPrint('$_tag: 开始播放音频');
      
    } catch (e) {
      debugPrint('$_tag: 音频播放失败 - $e');
      onError?.call('音频播放失败: $e');
      _isPlaying = false;
    }
  }
  
  /// WebSocket错误处理
  void _onWebSocketError(error) {
    debugPrint('$_tag: WebSocket错误 - $error');
    onError?.call('WebSocket错误: $error');
    _cleanup();
  }
  
  /// WebSocket连接关闭
  void _onWebSocketDone() {
    debugPrint('$_tag: WebSocket连接已关闭');
    _isConnected = false;
  }
  
  /// 停止播放
  Future<void> stopPlayback() async {
    if (_isPlaying && _audioPlayer != null) {
      await _audioPlayer!.stop();
      _isPlaying = false;
      debugPrint('$_tag: 音频播放已停止');
    }
  }
  
  /// 清理资源
  void _cleanup() {
    _isConnected = false;
    _audioBuffer.clear();
    
    _channel?.sink.close();
    _channel = null;
  }
  
  /// 释放资源
  void dispose() {
    _cleanup();
    _audioPlayer?.dispose();
    debugPrint('$_tag: 资源已释放');
  }
  
  // Getter方法
  bool get isPlaying => _isPlaying;
  bool get isConnected => _isConnected;
} 