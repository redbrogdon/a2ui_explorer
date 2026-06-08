import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart' as genui;
import 'package:genui/genui.dart' hide TextPart;

import 'catalog/reps_card.dart';
import 'firebase_options.dart';
import 'message_bubble.dart';
import 'three_pane_layout.dart';

const taskDisplaySurfaceId = 'task_display';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Just Today',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

sealed class ConversationItem {}

class TextItem extends ConversationItem {
  final String text;
  final bool isUser;
  TextItem({required this.text, this.isUser = false});
}

class SurfaceItem extends ConversationItem {
  final String surfaceId;
  SurfaceItem({required this.surfaceId});
}

class _MyHomePageState extends State<MyHomePage> {
  final List<ConversationItem> _items = [];
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final ChatSession _chatSession;

  late final SurfaceController _controller;
  late final A2uiTransportAdapter _transport;
  late final Conversation _conversation;
  late final Catalog catalog;
  String _chronologicalLog = '';

  @override
  void initState() {
    super.initState();
    final model = FirebaseAI.googleAI().generativeModel(
      model: 'gemini-3.5-flash',
    );
    _chatSession = model.startChat();

    catalog = BasicCatalogItems.asCatalog();

    _controller = SurfaceController(catalogs: [catalog]);

    _transport = A2uiTransportAdapter(onSend: _sendAndReceive);

    _conversation = Conversation(
      controller: _controller,
      transport: _transport,
    );

    _conversation.events.listen((event) {
      setState(() {
        switch (event) {
          case ConversationSurfaceAdded added:
            if (added.surfaceId != taskDisplaySurfaceId) {
              _items.add(SurfaceItem(surfaceId: added.surfaceId));
              _scrollToBottom();
            }
          case ConversationSurfaceRemoved removed:
            _items.removeWhere(
              (item) =>
                  item is SurfaceItem && item.surfaceId == removed.surfaceId,
            );
          case ConversationContentReceived content:
            _items.add(TextItem(text: content.text, isUser: false));
            _scrollToBottom();
          case ConversationError error:
            debugPrint('GenUI Error: ${error.error}');
          default:
        }
      });
    });

    final promptBuilder = PromptBuilder.custom(
      catalog: catalog,
      allowedOperations: SurfaceOperations.all(dataModel: true),
      systemPromptFragments: [systemInstruction],
    );

    _conversation.sendRequest(
      ChatMessage.system(promptBuilder.systemPromptJoined()),
    );
  }

  void _scrollToBottom() {
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

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendAndReceive(ChatMessage msg) async {
    final buffer = StringBuffer();

    for (final part in msg.parts) {
      if (part.isUiInteractionPart) {
        buffer.write(part.asUiInteractionPart!.interaction);
      } else if (part is genui.TextPart) {
        buffer.write(part.text);
      }
    }

    if (buffer.isEmpty) {
      return;
    }

    final text = buffer.toString();
    setState(() {
      _chronologicalLog += text;
    });

    final response = await _chatSession.sendMessage(Content.text(text));

    if (response.text?.isNotEmpty ?? false) {
      final responseText = response.text!;
      setState(() {
        _chronologicalLog += responseText;
      });
      _transport.addChunk(responseText);
    }
  }

  Future<void> _addMessage() async {
    final text = _textController.text;

    if (text.trim().isEmpty) {
      return;
    }

    _textController.clear();

    setState(() {
      _items.add(TextItem(text: text, isUser: true));
    });

    _scrollToBottom();

    await _conversation.sendRequest(ChatMessage.user(text));
  }

  // Widget _buildDataModelWidgets() {
  //   final widgets = <Widget>[];

  //   for (final item in _items.whereType<SurfaceItem>()) {
  //     final model = _controller.store.getDataModel(item.surfaceId);
  //     final data = model.getValue<Object?>(DataPath.root);
  //     final prettyJson = const JsonEncoder.withIndent('  ').convert(data);
  //     widgets.add(Text(prettyJson));
  //   }

  //   return Column(spacing: 16, children: widgets);
  // }

  Widget _buildActiveSurfaces() {
    final surfaceItems = _items.whereType<SurfaceItem>().toList();
    if (surfaceItems.isEmpty) {
      return const Center(child: Text('No active surfaces'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final item in surfaceItems)
          Surface(
            key: ValueKey(item.surfaceId),
            surfaceContext: _controller.contextFor(item.surfaceId),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Just Today'),
      ),
      body: ThreePaneLayout(
        leftChild: _buildActiveSurfaces(),
        middleChild: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final item in _items)
                        if (item is TextItem)
                          MessageBubble(text: item.text, isUser: item.isUser),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: ValueListenableBuilder<ConversationState>(
                      valueListenable: _conversation.state,
                      builder: (context, state, child) {
                        return Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                onSubmitted: state.isWaiting
                                    ? null
                                    : (_) => _addMessage(),
                                decoration: const InputDecoration(
                                  hintText: 'Enter a message',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: state.isWaiting ? null : _addMessage,
                              child: const Text('Send'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            ValueListenableBuilder<ConversationState>(
              valueListenable: _conversation.state,
              builder: (context, state, child) {
                if (state.isWaiting) {
                  return const LinearProgressIndicator();
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        rightChild: Container(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              _chronologicalLog,
              style: const TextStyle(fontFamily: 'Courier', fontSize: 13.0),
            ),
          ),
        ),
      ),
    );
  }
}

const systemInstruction = '''
You're a helpful assistant. Don't create UI components unless I specifically ask you to.
''';
