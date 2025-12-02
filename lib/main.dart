import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:llm_flutter/src/llm.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qwen3 LLM Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const LlmChatScreen(),
    );
  }
}

// Message model
class ChatMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.content,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// LLM Status enum
enum LlmStatus { unloaded, loading, ready, generating, error }

class LlmChatScreen extends StatefulWidget {
  const LlmChatScreen({super.key});

  @override
  State<LlmChatScreen> createState() => _LlmChatScreenState();
}

class _LlmChatScreenState extends State<LlmChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  LlmStatus _status = LlmStatus.unloaded;
  String _statusMessage = 'Model not loaded';
  String? _errorMessage;
  Llm? _llm;
  String? _cachePath;

  // Model path - adjust this based on where the model is stored on the device
  String get _modelPath {
    if (Platform.isAndroid) {
      // On Android, the model should be in the app's files directory or external storage
      return '/data/local/tmp/Qwen3-4B-Instruct-2507-MNN/config.json';
    } else {
      // For development/desktop - note: iOS simulator can access macOS filesystem
      return '/Users/sanic/llm-flutter/Qwen3-4B-Instruct-2507-MNN/config.json';
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _llm?.dispose();
    super.dispose();
  }

  Future<String> _getCachePath() async {
    if (_cachePath != null) return _cachePath!;
    final cacheDir = await getTemporaryDirectory();
    _cachePath = '${cacheDir.path}/mnn_cache';
    // Create the directory if it doesn't exist
    await Directory(_cachePath!).create(recursive: true);
    return _cachePath!;
  }

  Future<void> _loadModel() async {
    setState(() {
      _status = LlmStatus.loading;
      _statusMessage = 'Preparing cache directory...';
      _errorMessage = null;
    });

    try {
      // Get the app's cache directory for mmap files
      final tmpPath = await _getCachePath();
      
      setState(() {
        _statusMessage = 'Creating LLM instance...';
      });
      await Future.delayed(const Duration(milliseconds: 100));

      // Create LLM - disable mmap on emulator due to disk space constraints
      // On real devices with sufficient storage, set useMmap: true
      _llm = Llm(_modelPath, useMmap: false, tmpPath: tmpPath);

      setState(() {
        _statusMessage = 'Loading model weights...';
      });
      await Future.delayed(const Duration(milliseconds: 50));

      if (!_llm!.load()) {
        throw Exception('Failed to load model weights');
      }

      setState(() {
        _statusMessage = 'Optimizing for device...';
      });
      await Future.delayed(const Duration(milliseconds: 50));

      _llm!.tune();

      setState(() {
        _status = LlmStatus.ready;
        _statusMessage = 'Qwen3-4B ready';
      });

      _addMessage(
        ChatMessage(
          content:
              '👋 Hello! I\'m Qwen3-4B, ready to assist you. How can I help?',
          isUser: false,
        ),
      );
    } catch (e) {
      setState(() {
        _status = LlmStatus.error;
        _statusMessage = 'Failed to load model';
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _status != LlmStatus.ready) return;

    _textController.clear();

    // Add user message
    _addMessage(ChatMessage(content: text, isUser: true));
    
    // Add placeholder for assistant message with loading indicator
    final assistantMessage = ChatMessage(content: '', isUser: false);
    _addMessage(assistantMessage);
    final messageIndex = _messages.length - 1;

    setState(() {
      _status = LlmStatus.generating;
      _statusMessage = 'Generating response...';
    });

    try {
      // Use streaming generation with isolate
      final buffer = StringBuffer();
      
      await for (final token in _llm!.generateStream(text)) {
        buffer.write(token);
        // Update the message content as tokens arrive
        setState(() {
          _messages[messageIndex] = ChatMessage(
            content: buffer.toString(),
            isUser: false,
            timestamp: assistantMessage.timestamp,
          );
        });
        _scrollToBottom();
      }
      
      // Ensure final state is set
      final response = buffer.toString();
      setState(() {
        _status = LlmStatus.ready;
        _statusMessage = 'Qwen3-4B ready';
        if (response.isEmpty) {
          _messages[messageIndex] = ChatMessage(
            content: '(empty response)',
            isUser: false,
            timestamp: assistantMessage.timestamp,
          );
        }
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _status = LlmStatus.ready;
        _statusMessage = 'Qwen3-4B ready';
        _messages[messageIndex] = ChatMessage(
          content: '❌ Error generating response: $e',
          isUser: false,
          timestamp: assistantMessage.timestamp,
        );
      });
    }
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _addMessage(ChatMessage message) {
    setState(() {
      _messages.add(message);
    });

    // Scroll to bottom after adding message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _resetConversation() {
    _llm?.reset();
    setState(() {
      _messages.clear();
    });

    if (_status == LlmStatus.ready) {
      _addMessage(
        ChatMessage(
          content: '🔄 Conversation reset. How can I help you?',
          isUser: false,
        ),
      );
    }
  }

  void _unloadModel() {
    _llm?.dispose();
    _llm = null;
    setState(() {
      _status = LlmStatus.unloaded;
      _statusMessage = 'Model not loaded';
      _messages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Qwen3-4B Chat'),
        backgroundColor: colorScheme.inversePrimary,
        actions: [
          if (_status == LlmStatus.ready || _status == LlmStatus.generating)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _status == LlmStatus.generating
                  ? null
                  : _resetConversation,
              tooltip: 'Reset conversation',
            ),
          if (_status == LlmStatus.ready)
            IconButton(
              icon: const Icon(Icons.power_settings_new),
              onPressed: _unloadModel,
              tooltip: 'Unload model',
            ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          _buildStatusBar(colorScheme),

          // Messages list
          Expanded(
            child: _status == LlmStatus.unloaded
                ? _buildUnloadedState(colorScheme)
                : _status == LlmStatus.loading
                ? _buildLoadingState(colorScheme)
                : _status == LlmStatus.error
                ? _buildErrorState(colorScheme)
                : _buildMessagesList(),
          ),

          // Input area
          if (_status == LlmStatus.ready || _status == LlmStatus.generating)
            _buildInputArea(colorScheme),
        ],
      ),
    );
  }

  Widget _buildStatusBar(ColorScheme colorScheme) {
    Color backgroundColor;
    Color textColor;
    IconData icon;

    switch (_status) {
      case LlmStatus.unloaded:
        backgroundColor = colorScheme.surfaceContainerHighest;
        textColor = colorScheme.onSurfaceVariant;
        icon = Icons.cloud_off;
        break;
      case LlmStatus.loading:
        backgroundColor = colorScheme.primaryContainer;
        textColor = colorScheme.onPrimaryContainer;
        icon = Icons.downloading;
        break;
      case LlmStatus.ready:
        backgroundColor = colorScheme.primaryContainer;
        textColor = colorScheme.onPrimaryContainer;
        icon = Icons.check_circle;
        break;
      case LlmStatus.generating:
        backgroundColor = colorScheme.tertiaryContainer;
        textColor = colorScheme.onTertiaryContainer;
        icon = Icons.auto_awesome;
        break;
      case LlmStatus.error:
        backgroundColor = colorScheme.errorContainer;
        textColor = colorScheme.onErrorContainer;
        icon = Icons.error;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: backgroundColor,
      child: Row(
        children: [
          if (_status == LlmStatus.loading || _status == LlmStatus.generating)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textColor,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(icon, size: 16, color: textColor),
            ),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(color: textColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnloadedState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 80,
              color: colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Qwen3-4B LLM',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A powerful 4B parameter language model\nrunning locally on your device',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _loadModel,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Load Model'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '⚠️ Loading may take a moment\nModel size: ~2.7GB',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                strokeWidth: 6,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Loading Qwen3-4B...',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: colorScheme.primary),
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a minute on first load',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            const _LoadingIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: colorScheme.error),
            const SizedBox(height: 24),
            Text(
              'Failed to Load Model',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: colorScheme.error),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadModel,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'Send a message to start chatting',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        return _ChatBubble(message: _messages[index]);
      },
    );
  }

  Widget _buildInputArea(ColorScheme colorScheme) {
    final isGenerating = _status == LlmStatus.generating;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                enabled: !isGenerating,
                decoration: InputDecoration(
                  hintText: isGenerating
                      ? 'Generating...'
                      : 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: isGenerating ? null : (_) => _sendMessage(),
                maxLines: null,
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              onPressed: isGenerating ? null : _sendMessage,
              mini: true,
              child: isGenerating
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                Icons.smart_toy,
                size: 18,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: SelectableText(
                message.content,
                style: TextStyle(
                  color: isUser
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.primary,
              child: Icon(Icons.person, size: 18, color: colorScheme.onPrimary),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadingIndicator extends StatefulWidget {
  const _LoadingIndicator();

  @override
  State<_LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<_LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _dotCount = 0;

  final List<String> _loadingSteps = [
    'Initializing MNN runtime...',
    'Loading model weights...',
    'Preparing tokenizer...',
    'Optimizing for device...',
  ];

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 500),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            setState(() {
              _dotCount = (_dotCount + 1) % 4;
            });
            _controller.reset();
            _controller.forward();
          }
        });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dots = '.' * _dotCount;
    final step = _loadingSteps[_dotCount % _loadingSteps.length];

    return Text(
      '$step$dots',
      style: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
