import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/rust/api.dart';
import 'src/rust/frb_generated.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize FRB with platform-specific library loading
  await RustLib.init(externalLibrary: await _loadLibrary());
  
  runApp(const MyApp());
}

/// Load the native library based on platform
Future<ExternalLibrary> _loadLibrary() async {
  if (Platform.isIOS) {
    // On iOS, symbols are statically linked into the executable
    // Try loading from the debug dylib first (debug builds)
    // Fall back to process() for release builds
    try {
      return ExternalLibrary.open('@executable_path/Runner.debug.dylib');
    } catch (_) {
      return ExternalLibrary.process(iKnowHowToUseIt: true);
    }
  } else if (Platform.isAndroid) {
    // Use different name to avoid conflict with MNN's libllm.so
    return ExternalLibrary.open('libmnn_llm_frb.so');
  } else if (Platform.isMacOS) {
    return ExternalLibrary.open('libmnn_llm_frb.dylib');
  } else if (Platform.isLinux) {
    return ExternalLibrary.open('libmnn_llm_frb.so');
  } else if (Platform.isWindows) {
    return ExternalLibrary.open('mnn_llm_frb.dll');
  }
  throw UnsupportedError('Unsupported platform');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NorrChat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String role;
  final String content;
  final String? imagePath;

  ChatMessage({required this.role, required this.content, this.imagePath});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  
  MnnLlm? _llm;
  bool _isLoading = false;
  bool _isGenerating = false;
  String _currentResponse = '';
  String? _modelPath;
  String? _selectedImagePath;
  bool _isVisionModel = false;
  bool _useMmap = true;
  StreamSubscription<String>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // Request storage permissions on Android
    if (Platform.isAndroid) {
      await _requestStoragePermissions();
    }
    
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _modelPath = prefs.getString('model_path');
      _useMmap = prefs.getBool('use_mmap') ?? true;
    });
  }

  Future<void> _requestStoragePermissions() async {
    // For Android 11+ (API 30+), we need MANAGE_EXTERNAL_STORAGE
    // For older versions, READ/WRITE_EXTERNAL_STORAGE is enough
    if (await Permission.manageExternalStorage.isGranted) {
      return;
    }
    
    // Try requesting manage external storage first (Android 11+)
    var status = await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      return;
    }
    
    // Fall back to regular storage permission
    status = await Permission.storage.request();
    if (!status.isGranted) {
      debugPrint('Storage permission denied');
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_modelPath != null) {
      await prefs.setString('model_path', _modelPath!);
    }
    await prefs.setBool('use_mmap', _useMmap);
  }

  Future<void> _pickModelFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Model Folder',
    );
    
    if (result != null) {
      // Check for llm_config.json or config.json
      final configFile = File('$result/llm_config.json');
      final altConfigFile = File('$result/config.json');
      
      if (await configFile.exists() || await altConfigFile.exists()) {
        setState(() {
          _modelPath = result;
        });
        await _saveSettings();
        await _checkVisionSupport(result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No config.json or llm_config.json found in folder'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _checkVisionSupport(String modelPath) async {
    try {
      final configFile = File('$modelPath/llm_config.json');
      final altConfigFile = File('$modelPath/config.json');
      
      File? existingConfig;
      if (await configFile.exists()) {
        existingConfig = configFile;
      } else if (await altConfigFile.exists()) {
        existingConfig = altConfigFile;
      }
      
      if (existingConfig != null) {
        final content = await existingConfig.readAsString();
        final config = jsonDecode(content) as Map<String, dynamic>;
        setState(() {
          _isVisionModel = config['is_visual'] == true;
        });
      }
    } catch (e) {
      debugPrint('Error checking vision support: $e');
    }
  }

  Future<void> _loadModel() async {
    if (_modelPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a model folder first')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create LLM instance
      _llm = MnnLlm.create(configPath: _modelPath!);
      
      // Configure mmap and tmp_path
      final tmpDir = await getTemporaryDirectory();
      final config = jsonEncode({
        'use_mmap': _useMmap,
        'tmp_path': tmpDir.path,
      });
      await _llm!.setConfig(configJson: config);
      
      // Load model
      final success = await _llm!.load();
      if (!success) {
        throw Exception('Model loading returned false');
      }
      
      // Tune for performance
      await _llm!.tune();
      
      // Check vision support from model config
      final dumpedConfig = _llm!.dumpConfig();
      try {
        final configMap = jsonDecode(dumpedConfig) as Map<String, dynamic>;
        setState(() {
          _isVisionModel = configMap['is_visual'] == true;
        });
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Model loaded successfully${_isVisionModel ? ' (Vision enabled)' : ''}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading model: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      _llm = null;
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImagePath = image.path;
      });
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _selectedImagePath = image.path;
      });
    }
  }

  void _clearImage() {
    setState(() {
      _selectedImagePath = null;
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _llm == null || _isGenerating) return;

    _textController.clear();
    
    final userMessage = ChatMessage(
      role: 'user',
      content: text,
      imagePath: _selectedImagePath,
    );
    
    setState(() {
      _messages.add(userMessage);
      _isGenerating = true;
      _currentResponse = '';
      _selectedImagePath = null;
    });

    _scrollToBottom();

    try {
      Stream<String> stream;
      
      if (userMessage.imagePath != null && _isVisionModel) {
        // Vision model with image
        stream = _llm!.visionGenerateStream(
          prompt: text,
          imagePaths: userMessage.imagePath!,
        );
      } else {
        // Text-only generation
        stream = _llm!.generateStream(prompt: text);
      }
      
      _streamSubscription = stream.listen(
        (chunk) {
          setState(() {
            _currentResponse += chunk;
          });
          _scrollToBottom();
        },
        onDone: () {
          setState(() {
            if (_currentResponse.isNotEmpty) {
              _messages.add(ChatMessage(
                role: 'assistant',
                content: _currentResponse,
              ));
            }
            _currentResponse = '';
            _isGenerating = false;
          });
          _streamSubscription = null;
        },
        onError: (error) {
          setState(() {
            _messages.add(ChatMessage(
              role: 'assistant',
              content: 'Error: $error',
            ));
            _currentResponse = '';
            _isGenerating = false;
          });
          _streamSubscription = null;
        },
      );
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          role: 'assistant',
          content: 'Error: $e',
        ));
        _isGenerating = false;
      });
    }
  }

  void _stopGeneration() {
    _streamSubscription?.cancel();
    setState(() {
      if (_currentResponse.isNotEmpty) {
        _messages.add(ChatMessage(
          role: 'assistant',
          content: _currentResponse,
        ));
      }
      _currentResponse = '';
      _isGenerating = false;
    });
    _streamSubscription = null;
  }

  Future<void> _resetChat() async {
    await _llm?.reset();
    setState(() {
      _messages.clear();
      _currentResponse = '';
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Settings',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Model Path'),
                subtitle: Text(_modelPath ?? 'Not selected'),
                trailing: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _pickModelFolder();
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('Use Memory Mapping'),
                subtitle: const Text('Reduces RAM usage for large models'),
                value: _useMmap,
                onChanged: (value) {
                  setModalState(() {
                    _useMmap = value;
                  });
                  setState(() {
                    _useMmap = value;
                  });
                  _saveSettings();
                },
              ),
              if (_isVisionModel)
                const ListTile(
                  leading: Icon(Icons.visibility, color: Colors.green),
                  title: Text('Vision Model'),
                  subtitle: Text('Image input is enabled'),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _llm != null
                      ? () {
                          Navigator.pop(context);
                          _resetChat();
                        }
                      : null,
                  child: const Text('Clear Chat History'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _streamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showLoadingOverlay = _llm == null;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('NorrChat'),
        actions: [
          if (_llm == null)
            TextButton.icon(
              onPressed: _isLoading ? null : _loadModel,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isLoading ? 'Loading...' : 'Load'),
            )
          else
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: null,
              tooltip: 'Model loaded',
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
        children: [
          // Messages list
          Expanded(
            child: _messages.isEmpty && _currentResponse.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _llm == null
                              ? 'Select a model folder and load it to start'
                              : 'Send a message to start chatting',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_currentResponse.isNotEmpty ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _currentResponse.isNotEmpty) {
                        // Streaming response
                        return _MessageBubble(
                          message: ChatMessage(
                            role: 'assistant',
                            content: _currentResponse,
                          ),
                          isStreaming: true,
                        );
                      }
                      return _MessageBubble(message: _messages[index]);
                    },
                  ),
          ),
          
          // Image preview
          if (_selectedImagePath != null)
            Container(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_selectedImagePath!),
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Image attached',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _clearImage,
                  ),
                ],
              ),
            ),
          
          // Input area
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  if (_isVisionModel && _llm != null) ...[
                    IconButton(
                      icon: const Icon(Icons.image),
                      onPressed: _isGenerating ? null : _pickImage,
                      tooltip: 'Pick image',
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt),
                      onPressed: _isGenerating ? null : _takePhoto,
                      tooltip: 'Take photo',
                    ),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: _llm == null
                            ? 'Load a model first...'
                            : 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      enabled: _llm != null && !_isGenerating,
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isGenerating)
                    IconButton(
                      icon: const Icon(Icons.stop),
                      onPressed: _stopGeneration,
                      tooltip: 'Stop generation',
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _llm != null ? _sendMessage : null,
                      tooltip: 'Send message',
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
          // Full-screen loading overlay until model is loaded
          if (showLoadingOverlay)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/icon.png',
                      width: 120,
                      height: 120,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.chat_bubble_rounded,
                        size: 120,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'NorrChat',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'On-device AI Assistant',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 48),
                    if (_isLoading) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Loading model...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ] else ...[
                      FilledButton.icon(
                        onPressed: _modelPath != null ? _loadModel : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Load Model'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _pickModelFolder,
                        icon: const Icon(Icons.folder_open),
                        label: Text(_modelPath != null ? 'Change Model' : 'Select Model Folder'),
                      ),
                      if (_modelPath != null) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _modelPath!.split('/').last,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isStreaming;

  const _MessageBubble({
    required this.message,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imagePath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(message.imagePath!),
                    width: 200,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: SelectableText(
                    message.content,
                    style: TextStyle(
                      color: isUser
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
