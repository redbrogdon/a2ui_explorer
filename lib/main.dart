import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart' as genui;
import 'package:genui/genui.dart' hide TextPart;

import 'catalog/reps_card.dart';
import 'firebase_options.dart';
import 'message_bubble.dart';

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
  double _splitRatio = 0.5;

  @override
  void initState() {
    super.initState();
    final model = FirebaseAI.googleAI().generativeModel(
      model: 'gemini-3.5-flash',
    );
    _chatSession = model.startChat();

    catalog = Catalog([repsCard], catalogId: 'workout-catalog');

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
      systemPromptFragments: [
        '''
        You are a helpful workout assistant that tracks my workouts.
        Please create a RepsCard (from the 'workout-catalog' catalog)
        displaying a particular exercise that
        can be measured in reps. When I have completed the exercise,
        give me another RepsCard with a new exercise. After three
        exercises, tell me I'm done and praise my effort.
      ''',
      ],
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

    final response = await _chatSession.sendMessage(Content.text(text));

    if (response.text?.isNotEmpty ?? false) {
      _transport.addChunk(response.text!);
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

  Widget _buildDataModelWidgets() {
    final widgets = <Widget>[];

    for (final item in _items.whereType<SurfaceItem>()) {
      final model = _controller.store.getDataModel(item.surfaceId);
      final data = model.getValue<Object?>(DataPath.root);
      final prettyJson = const JsonEncoder.withIndent('  ').convert(data);
      widgets.add(Text(prettyJson));
    }

    return Column(spacing: 16, children: widgets);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Just Today'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final leftWidth = (_splitRatio * totalWidth).clamp(
            150.0,
            totalWidth - 150.0,
          );
          return Row(
            children: [
              SizedBox(
                width: leftWidth,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          child: ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            children: [
                              for (final item in _items)
                                switch (item) {
                                  TextItem() => MessageBubble(
                                    text: item.text,
                                    isUser: item.isUser,
                                  ),
                                  SurfaceItem() => Surface(
                                    surfaceContext: _controller.contextFor(
                                      item.surfaceId,
                                    ),
                                  ),
                                },
                            ],
                          ),
                        ),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
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
                                      onPressed: state.isWaiting
                                          ? null
                                          : _addMessage,
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
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _splitRatio += details.delta.dx / totalWidth;
                    _splitRatio = _splitRatio.clamp(0.15, 0.85);
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    width: 8.0,
                    color: Theme.of(context).dividerColor,
                    child: Center(
                      child: Container(
                        width: 2.0,
                        height: 30.0,
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  child: _buildDataModelWidgets(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

const systemInstruction =
    '''
  ## PERSONA
  You are an expert task planner.

  ## GOAL
  Work with me to produce a list of tasks that I should do today, and then track
  the completion status of each one.

  ## RULES
  Talk with me only about tasks that I should do today.
  Do not engage in conversation about any other topic.
  Do not offer suggestions unless I ask for them.
  Do not offer encouragement unless I ask for it.
  Do not offer advice unless I ask for it.
  Do not offer opinions unless I ask for them.

  ## PROCESS
  ### Planning
  *   Ask me for information about tasks that I should do today.
  *   Synthesize a list of tasks from that information.
  *   Ask clarifying questions if you need to.
  *   When you have a list of tasks that you think I should do today, present it
    to me for review.
  *   Respond to my suggestions for changes, if I have any, until I accept the
    list.

  ### Tracking
  *   Once the list is accepted, ask me to let you know when individual tasks are
    complete.
  *   If I tell you a task is complete, mark it as complete.
  *   Once all tasks are complete, send a message acknowledging that, and then
    end the conversation.

  ## USER INTERFACE
  * To display the list of tasks create one and only one instance of the
    TaskDisplay catalog item. Use "$taskDisplaySurfaceId" as its surface ID.
    **YOU ARE NOT ALLOWED TO CREATE ANY OTHER UI COMPONENTS TO DISPLAY THE LIST
    OF TASKS. ALWAYS USE THIS ONE AND ONLY INSTANCE OF TaskDisplay.**
  * Update "$taskDisplaySurfaceId" as necessary when the list changes.
  * "$taskDisplaySurfaceId" must include a button for each task that I can use
    to mark it complete. When I use that button to mark a task complete, it
    should send you a message indicating what I've done.
  * Avoid repeating the same information in a single message.
  * When responding with text, rather than A2UI messages, be brief.
''';
