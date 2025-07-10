import 'dart:async';
import 'package:flutter/foundation.dart';

/// 句子分段器
/// 将流式文本收集成完整句子，确保TTS朗读的流畅性
class SentenceSegmenter {
  static const String _tag = 'SentenceSegmenter';
  
  // 句子结束标点符号
  static const List<String> _sentenceEnders = [
    '。', '！', '？', '.', '!', '?', 
    '；', ';', '…', '......',
    '\n\n'  // 双换行也视为句子结束
  ];
  
  // 停顿标点符号（会产生短暂停顿，但不结束句子）
  static const List<String> _pauseMarkers = [
    '，', ',', '、', '：', ':', '（', '）', '(', ')',
    '"', '"', ''', '''
  ];
  
  String _buffer = '';
  Timer? _timeoutTimer;
  
  // 配置参数
  final int minSentenceLength;      // 最短句子长度
  final int maxSentenceLength;      // 最长句子长度
  final Duration timeoutDuration;   // 超时时间（如果长时间没有句子结束符，强制输出）
  
  // 回调函数
  Function(String sentence)? onSentenceComplete;
  Function(String text)? onPartialText;  // 部分文本回调（可用于显示）
  Function(String error)? onError;
  
  SentenceSegmenter({
    this.minSentenceLength = 5,
    this.maxSentenceLength = 200,
    this.timeoutDuration = const Duration(seconds: 3),
  });
  
  /// 添加文本片段
  void addText(String text) {
    if (text.trim().isEmpty) return;
    
    _buffer += text;
    debugPrint('$_tag: 添加文本: "$text", 当前缓冲区长度: ${_buffer.length}');
    
    // 触发部分文本回调
    onPartialText?.call(_buffer);
    
    // 检查是否有完整句子
    _checkForCompleteSentences();
    
    // 重置超时计时器
    _resetTimeoutTimer();
  }
  
  /// 检查是否有完整句子
  void _checkForCompleteSentences() {
    while (_buffer.isNotEmpty) {
      String? sentence = _extractSentence();
      if (sentence != null) {
        _emitSentence(sentence);
      } else {
        break;
      }
    }
  }
  
  /// 提取句子
  String? _extractSentence() {
    // 查找句子结束标点
    int endIndex = -1;
    String endMarker = '';
    
    for (String ender in _sentenceEnders) {
      int index = _buffer.indexOf(ender);
      if (index != -1 && (endIndex == -1 || index < endIndex)) {
        endIndex = index;
        endMarker = ender;
      }
    }
    
    if (endIndex != -1) {
      // 找到句子结束符
      String sentence = _buffer.substring(0, endIndex + endMarker.length).trim();
      _buffer = _buffer.substring(endIndex + endMarker.length);
      
      // 检查句子长度
      if (sentence.length >= minSentenceLength) {
        return sentence;
      } else {
        // 句子太短，继续积累
        debugPrint('$_tag: 句子太短，继续积累: "$sentence"');
        return null;
      }
    }
    
    // 检查是否超过最大长度，强制分割
    if (_buffer.length >= maxSentenceLength) {
      // 尝试在停顿标点处分割
      int splitIndex = _findBestSplitPoint();
      if (splitIndex > 0) {
        String sentence = _buffer.substring(0, splitIndex).trim();
        _buffer = _buffer.substring(splitIndex);
        return sentence;
      } else {
        // 强制在最大长度处分割
        String sentence = _buffer.substring(0, maxSentenceLength).trim();
        _buffer = _buffer.substring(maxSentenceLength);
        debugPrint('$_tag: 强制分割长句: "$sentence"');
        return sentence;
      }
    }
    
    return null;
  }
  
  /// 查找最佳分割点（在停顿标点处）
  int _findBestSplitPoint() {
    int bestIndex = -1;
    
    // 从后往前查找停顿标点
    for (int i = _buffer.length - 1; i >= minSentenceLength; i--) {
      String char = _buffer[i];
      if (_pauseMarkers.contains(char)) {
        bestIndex = i + 1;
        break;
      }
    }
    
    // 如果找不到停顿标点，查找空格
    if (bestIndex == -1) {
      for (int i = _buffer.length - 1; i >= minSentenceLength; i--) {
        String char = _buffer[i];
        if (char == ' ' || char == '\n') {
          bestIndex = i + 1;
          break;
        }
      }
    }
    
    return bestIndex;
  }
  
  /// 发出句子
  void _emitSentence(String sentence) {
    if (sentence.trim().isEmpty) return;
    
    // 清理句子
    sentence = _cleanSentence(sentence);
    
    if (sentence.length >= minSentenceLength) {
      debugPrint('$_tag: 输出完整句子: "$sentence"');
      onSentenceComplete?.call(sentence);
    }
  }
  
  /// 清理句子文本
  String _cleanSentence(String sentence) {
    // 移除多余的空白字符
    sentence = sentence.replaceAll(RegExp(r'\s+'), ' ');
    
    // 移除行首行尾空白
    sentence = sentence.trim();
    
    // 处理特殊情况：如果句子只有标点符号，忽略
    if (RegExp(r'^[^\w\u4e00-\u9fff]+$').hasMatch(sentence)) {
      return '';
    }
    
    return sentence;
  }
  
  /// 重置超时计时器
  void _resetTimeoutTimer() {
    _timeoutTimer?.cancel();
    
    if (_buffer.isNotEmpty) {
      _timeoutTimer = Timer(timeoutDuration, () {
        if (_buffer.isNotEmpty) {
          debugPrint('$_tag: 超时强制输出: "${_buffer.trim()}"');
          String sentence = _buffer.trim();
          _buffer = '';
          
          if (sentence.length >= minSentenceLength) {
            _emitSentence(sentence);
          }
        }
      });
    }
  }
  
  /// 强制输出当前缓冲区内容
  void flush() {
    _timeoutTimer?.cancel();
    
    if (_buffer.isNotEmpty) {
      String sentence = _buffer.trim();
      _buffer = '';
      
      if (sentence.length >= minSentenceLength) {
        debugPrint('$_tag: 强制输出缓冲区内容: "$sentence"');
        _emitSentence(sentence);
      }
    }
  }
  
  /// 清空缓冲区
  void clear() {
    _timeoutTimer?.cancel();
    _buffer = '';
    debugPrint('$_tag: 缓冲区已清空');
  }
  
  /// 获取当前缓冲区内容
  String get currentBuffer => _buffer;
  
  /// 获取缓冲区长度
  int get bufferLength => _buffer.length;
  
  /// 检查缓冲区是否为空
  bool get isEmpty => _buffer.isEmpty;
  
  /// 释放资源
  void dispose() {
    _timeoutTimer?.cancel();
    _buffer = '';
    debugPrint('$_tag: 资源已释放');
  }
} 