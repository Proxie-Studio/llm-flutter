/// MNN-LLM Flutter bindings
/// 
/// High-level Dart API for on-device LLM inference using MNN-LLM.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'llm_bindings_generated.dart';

export 'llm_bindings_generated.dart' show LlmContextInfo;

/// Loads the native library for the current platform
DynamicLibrary _loadLibrary() {
  if (Platform.isAndroid) {
    // Load C++ runtime first (required by Rust code)
    DynamicLibrary.open('libc++_shared.so');
    // Load MNN dependencies (order matters!)
    DynamicLibrary.open('libMNN.so');
    DynamicLibrary.open('libMNN_Express.so');
    DynamicLibrary.open('libllm.so');
    DynamicLibrary.open('libMNNOpenCV.so');
    // Now load our Rust wrapper
    return DynamicLibrary.open('libmnn_llm_rust.so');
  } else if (Platform.isIOS) {
    // In debug mode, Flutter links native code into Runner.debug.dylib
    // In release mode, it's statically linked into the main executable
    // Try loading from the debug dylib first, fall back to process()
    try {
      return DynamicLibrary.open('@executable_path/Runner.debug.dylib');
    } catch (_) {
      // Release build - symbols are in main executable
      return DynamicLibrary.process();
    }
  } else if (Platform.isMacOS) {
    return DynamicLibrary.open('libmnn_llm_rust.dylib');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('libmnn_llm_rust.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('mnn_llm_rust.dll');
  } else {
    throw UnsupportedError('Unsupported platform');
  }
}

/// Global bindings instance (lazy initialization)
MnnLlmBindings? _bindingsInstance;
MnnLlmBindings get _bindings => _bindingsInstance ??= MnnLlmBindings(_loadLibrary());

/// Callback type for streaming tokens
typedef OnTokenCallback = void Function(String token);

/// High-level LLM wrapper with streaming support
class Llm {
  Pointer<Void> _handle;
  bool _disposed = false;
  bool _loaded = false;

  Llm._(this._handle);

  /// Create an LLM instance from a config path.
  /// 
  /// [configPath] - Path to llm_config.json
  /// [useMmap] - Enable memory-mapped file loading (reduces RAM usage)
  /// [tmpPath] - Directory for cache files (recommended for Android)
  factory Llm(String configPath, {bool useMmap = true, String? tmpPath}) {
    final pathPtr = configPath.toNativeUtf8();
    try {
      final handle = _bindings.llm_create_ffi(pathPtr.cast());
      if (handle == nullptr) {
        throw Exception('Failed to create LLM instance');
      }
      final llm = Llm._(handle);
      
      // Configure mmap and tmp_path
      final config = <String, dynamic>{};
      if (useMmap) config['use_mmap'] = true;
      if (tmpPath != null) config['tmp_path'] = tmpPath;
      if (config.isNotEmpty) {
        llm.setConfig(_jsonEncode(config));
      }
      
      return llm;
    } finally {
      malloc.free(pathPtr);
    }
  }

  void _checkDisposed() {
    if (_disposed) throw StateError('LLM instance disposed');
  }

  void _checkLoaded() {
    if (!_loaded) throw StateError('Model not loaded. Call load() first.');
  }

  /// Set configuration options (JSON format). Call before load().
  void setConfig(String configJson) {
    _checkDisposed();
    final jsonPtr = configJson.toNativeUtf8();
    try {
      _bindings.llm_set_config_ffi(_handle, jsonPtr.cast());
    } finally {
      malloc.free(jsonPtr);
    }
  }

  /// Get current configuration as JSON string.
  String dumpConfig() {
    _checkDisposed();
    final ptr = _bindings.llm_dump_config_ffi(_handle);
    if (ptr == nullptr) return '{}';
    final result = ptr.cast<Utf8>().toDartString();
    _bindings.llm_free_string_ffi(ptr);
    return result;
  }

  /// Load the model weights. Must be called before generate().
  bool load() {
    _checkDisposed();
    _loaded = _bindings.llm_load_ffi(_handle);
    return _loaded;
  }

  /// Tune/optimize the model for the current device. Call after load().
  void tune() {
    _checkDisposed();
    _checkLoaded();
    _bindings.llm_tune_ffi(_handle);
  }

  /// Set thinking mode (for models with chain-of-thought support).
  void setThinking(bool thinking) {
    _checkDisposed();
    _bindings.llm_set_thinking_ffi(_handle, thinking);
  }

  /// Generate a response (non-streaming).
  String generate(String prompt) {
    _checkDisposed();
    _checkLoaded();
    
    final promptPtr = prompt.toNativeUtf8();
    try {
      final resultPtr = _bindings.llm_generate_ffi(_handle, promptPtr.cast());
      if (resultPtr == nullptr) {
        throw Exception('Generation failed');
      }
      final result = resultPtr.cast<Utf8>().toDartString();
      _bindings.llm_free_string_ffi(resultPtr);
      return result;
    } finally {
      malloc.free(promptPtr);
    }
  }

  /// Generate a response with streaming using a callback.
  /// The callback is called for each token as it's generated.
  /// This runs synchronously and blocks until generation is complete.
  /// 
  /// **Note**: This will block the UI thread. The callback is invoked
  /// for each token, but UI won't update until generation completes.
  void generateStreamSync(String prompt, OnTokenCallback onToken) {
    _checkDisposed();
    _checkLoaded();

    final promptPtr = prompt.toNativeUtf8();
    
    // Store callback in a way accessible from static function
    final callbackId = _registerCallback(onToken);
    
    try {
      final callback = Pointer.fromFunction<LlmStreamCallbackFunction>(
        _streamCallbackStatic,
        false,
      );
      
      _bindings.llm_generate_stream_ffi(
        _handle,
        promptPtr.cast(),
        callback,
        Pointer.fromAddress(callbackId),
      );
    } finally {
      _unregisterCallback(callbackId);
      malloc.free(promptPtr);
    }
  }

  /// Generate a response with streaming in a background isolate.
  /// Returns a Stream that yields tokens as they are generated.
  /// 
  /// This runs the generation in a separate isolate, allowing the UI
  /// to update as tokens arrive.
  Stream<String> generateStream(String prompt) {
    _checkDisposed();
    _checkLoaded();

    final controller = StreamController<String>();
    final receivePort = ReceivePort();
    
    receivePort.listen((message) {
      if (message == null) {
        // Generation complete
        receivePort.close();
        controller.close();
      } else if (message is String) {
        controller.add(message);
      } else if (message is List && message.length == 2 && message[0] == 'error') {
        controller.addError(Exception(message[1]));
        receivePort.close();
        controller.close();
      }
    });
    
    // Spawn isolate for generation
    Isolate.spawn(
      _generateInIsolate,
      _IsolateParams(
        handleAddress: _handle.address,
        prompt: prompt,
        sendPort: receivePort.sendPort,
      ),
    ).catchError((e) {
      controller.addError(e);
      receivePort.close();
      controller.close();
    });
    
    return controller.stream;
  }

  /// Generate a response asynchronously (non-streaming).
  /// Returns a Future that completes with the full response.
  /// 
  /// This wraps the synchronous generate call in a Future.
  /// The call still blocks, but allows await syntax.
  Future<String> generateAsync(String prompt) async {
    return generate(prompt);
  }

  /// Check if generation has stopped.
  bool get stopped {
    _checkDisposed();
    return _bindings.llm_stopped_ffi(_handle);
  }

  /// Check if KV cache reuse is enabled.
  bool get reuseKv {
    _checkDisposed();
    return _bindings.llm_reuse_kv_ffi(_handle);
  }

  /// Get the generated string from context.
  String getGeneratedString() {
    _checkDisposed();
    final ptr = _bindings.llm_get_generated_string_ffi(_handle);
    if (ptr == nullptr) return '';
    final result = ptr.cast<Utf8>().toDartString();
    _bindings.llm_free_string_ffi(ptr);
    return result;
  }

  /// Reset conversation context/history.
  void reset() {
    _checkDisposed();
    _bindings.llm_reset_ffi(_handle);
  }

  /// Apply chat template to a user message.
  String applyChatTemplate(String userContent) {
    _checkDisposed();
    final contentPtr = userContent.toNativeUtf8();
    try {
      final ptr = _bindings.llm_apply_chat_template_ffi(_handle, contentPtr.cast());
      if (ptr == nullptr) return userContent;
      final result = ptr.cast<Utf8>().toDartString();
      _bindings.llm_free_string_ffi(ptr);
      return result;
    } finally {
      malloc.free(contentPtr);
    }
  }

  /// Apply chat template to a JSON array of messages.
  String applyChatTemplateJson(String messagesJson) {
    _checkDisposed();
    final jsonPtr = messagesJson.toNativeUtf8();
    try {
      final ptr = _bindings.llm_apply_chat_template_json_ffi(_handle, jsonPtr.cast());
      if (ptr == nullptr) return '';
      final result = ptr.cast<Utf8>().toDartString();
      _bindings.llm_free_string_ffi(ptr);
      return result;
    } finally {
      malloc.free(jsonPtr);
    }
  }

  /// Encode text to token IDs.
  List<int> tokenizerEncode(String text) {
    _checkDisposed();
    final textPtr = text.toNativeUtf8();
    try {
      // First call to get size
      final size = _bindings.llm_tokenizer_encode_ffi(
        _handle,
        textPtr.cast(),
        nullptr,
        0,
      );
      if (size == 0) return [];
      
      // Allocate buffer and get tokens
      final output = malloc<Int32>(size);
      try {
        _bindings.llm_tokenizer_encode_ffi(
          _handle,
          textPtr.cast(),
          output,
          size,
        );
        return List.generate(size, (i) => output[i]);
      } finally {
        malloc.free(output);
      }
    } finally {
      malloc.free(textPtr);
    }
  }

  /// Decode a single token ID to string.
  String tokenizerDecode(int token) {
    _checkDisposed();
    final ptr = _bindings.llm_tokenizer_decode_ffi(_handle, token);
    if (ptr == nullptr) return '';
    final result = ptr.cast<Utf8>().toDartString();
    _bindings.llm_free_string_ffi(ptr);
    return result;
  }

  /// Check if a token is a stop token.
  bool isStopToken(int token) {
    _checkDisposed();
    return _bindings.llm_is_stop_ffi(_handle, token);
  }

  /// Get current history length.
  int get currentHistory {
    _checkDisposed();
    return _bindings.llm_get_current_history_ffi(_handle);
  }

  /// Erase history in range [begin, end).
  void eraseHistory(int begin, int end) {
    _checkDisposed();
    _bindings.llm_erase_history_ffi(_handle, begin, end);
  }

  /// Get context info (token counts and timing metrics).
  LlmContextInfo getContextInfo() {
    _checkDisposed();
    return _bindings.llm_get_context_info_ffi(_handle);
  }

  /// Format a vision prompt with image(s).
  /// [imagePaths] can be comma-separated for multiple images.
  String formatVisionPrompt(
    String prompt,
    String imagePaths, {
    int width = 0,
    int height = 0,
  }) {
    _checkDisposed();
    final promptPtr = prompt.toNativeUtf8();
    final pathsPtr = imagePaths.toNativeUtf8();
    try {
      final ptr = _bindings.llm_format_vision_prompt_ffi(
        _handle,
        promptPtr.cast(),
        pathsPtr.cast(),
        width,
        height,
      );
      if (ptr == nullptr) return prompt;
      final result = ptr.cast<Utf8>().toDartString();
      _bindings.llm_free_string_ffi(ptr);
      return result;
    } finally {
      malloc.free(promptPtr);
      malloc.free(pathsPtr);
    }
  }

  /// Dispose of the LLM instance.
  void dispose() {
    if (!_disposed) {
      _bindings.llm_destroy_ffi(_handle);
      _disposed = true;
    }
  }
}

// ============================================================================
// Callback management for streaming
// ============================================================================

int _nextCallbackId = 1;
final Map<int, OnTokenCallback> _activeCallbacks = {};

int _registerCallback(OnTokenCallback callback) {
  final id = _nextCallbackId++;
  _activeCallbacks[id] = callback;
  return id;
}

void _unregisterCallback(int id) {
  _activeCallbacks.remove(id);
}

// Static callback function for streaming
bool _streamCallbackStatic(
  Pointer<Char> token,
  int len,
  Pointer<Void> userData,
) {
  final callbackId = userData.address;
  final callback = _activeCallbacks[callbackId];
  if (callback == null) return false;
  
  // Convert token to Dart string
  if (len > 0) {
    final bytes = token.cast<Uint8>().asTypedList(len);
    final str = String.fromCharCodes(bytes);
    callback(str);
  }
  
  return true; // Continue generation
}

// ============================================================================
// Isolate-based streaming
// ============================================================================

/// Parameters for isolate-based generation
class _IsolateParams {
  final int handleAddress;
  final String prompt;
  final SendPort sendPort;
  
  _IsolateParams({
    required this.handleAddress,
    required this.prompt,
    required this.sendPort,
  });
}

/// Isolate entry point for streaming generation
void _generateInIsolate(_IsolateParams params) {
  try {
    // Re-initialize bindings in this isolate
    final bindings = MnnLlmBindings(_loadLibrary());
    final handle = Pointer<Void>.fromAddress(params.handleAddress);
    
    final promptPtr = params.prompt.toNativeUtf8();
    
    // Register callback that sends tokens to main isolate
    final sendPort = params.sendPort;
    final callbackId = _registerCallback((token) {
      sendPort.send(token);
    });
    
    try {
      final callback = Pointer.fromFunction<LlmStreamCallbackFunction>(
        _streamCallbackStatic,
        false,
      );
      
      bindings.llm_generate_stream_ffi(
        handle,
        promptPtr.cast(),
        callback,
        Pointer.fromAddress(callbackId),
      );
      
      // Signal completion
      sendPort.send(null);
    } finally {
      _unregisterCallback(callbackId);
      malloc.free(promptPtr);
    }
  } catch (e) {
    params.sendPort.send(['error', e.toString()]);
  }
}

// ============================================================================
// Utilities
// ============================================================================

// Simple JSON encoder
String _jsonEncode(Map<String, dynamic> map) {
  final parts = <String>[];
  for (final entry in map.entries) {
    final value = entry.value;
    if (value is bool) {
      parts.add('"${entry.key}": $value');
    } else if (value is String) {
      parts.add('"${entry.key}": "${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"');
    } else {
      parts.add('"${entry.key}": $value');
    }
  }
  return '{${parts.join(', ')}}';
}
