/// 票 09「shadcn_ui 聊天界面原型」入口。
///
/// 运行：`flutter run -t prototype/main.dart -d <设备>`
///
/// 这是一个一次性的粗原型：全部数据来自 [data.dart]，没有数据库、网络或真实
/// 状态机。目的只是回答「长什么样、怎么动」，生产实现仍按票 10 的规格来做。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'composer.dart';
import 'data.dart';
import 'messages.dart';
import 'theme.dart';

/// 截图与演示用：`--dart-define=PROTOTYPE_SCENARIO=streaming`。
const _initialScenarioName = String.fromEnvironment(
  'PROTOTYPE_SCENARIO',
  defaultValue: 'demo',
);
const _initialDark = bool.fromEnvironment('PROTOTYPE_DARK');

void main() {
  runApp(const PrototypeApp());
}

class PrototypeApp extends StatefulWidget {
  const PrototypeApp({super.key});

  @override
  State<PrototypeApp> createState() => _PrototypeAppState();
}

class _PrototypeAppState extends State<PrototypeApp> {
  bool _dark = _initialDark;

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: 'SeekChat 原型',
      debugShowCheckedModeBanner: false,
      theme: prototypeShadTheme(Brightness.light),
      darkTheme: prototypeShadTheme(Brightness.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: PrototypeHome(
        dark: _dark,
        onToggleTheme: () => setState(() => _dark = !_dark),
      ),
    );
  }
}

enum _StreamPhase { idle, streaming, stopped, done }

enum _SessionAction { rename, delete }

class PrototypeHome extends StatefulWidget {
  const PrototypeHome({
    super.key,
    required this.dark,
    required this.onToggleTheme,
  });

  final bool dark;
  final VoidCallback onToggleTheme;

  @override
  State<PrototypeHome> createState() => _PrototypeHomeState();
}

class _PrototypeHomeState extends State<PrototypeHome> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _input = TextEditingController();

  final List<FakeSession> _sessions = [...fakeSessions];
  String _sessionTitle = fakeSessions.first.title;
  int _selectedSessionId = fakeSessions.first.id;
  int _nextSessionId = fakeSessions.length + 1;

  PrototypeScenario _scenario = PrototypeScenario.demo;
  bool _thinking = true;
  bool _search = true;
  bool _recording = false;
  bool _thinkingExpanded = false;
  bool _streamThinkingExpanded = true;
  bool _longExpanded = false;
  int _branch = 1;
  int _branchCount = 2;
  String _model = 'deepseek-flash';

  _StreamPhase _phase = _StreamPhase.idle;
  String _streamText = '';
  int _chunkIndex = 0;
  int _thinkingSeconds = 0;
  Timer? _streamTimer;
  Timer? _thinkingTimer;

  String _sentText = '';
  List<FakeAttachment> _sentAttachments = [];
  List<FakeAttachment> _draft = [...demoDraftAttachments];
  Timer? _uploadTimer;

  bool get _hasLiveReply => _sentText.isNotEmpty;
  bool get _busy =>
      _phase == _StreamPhase.streaming &&
      (_hasLiveReply || _scenario == PrototypeScenario.streaming);

  @override
  void initState() {
    super.initState();
    _applyScenario(
      PrototypeScenario.values.firstWhere(
        (scenario) => scenario.name == _initialScenarioName,
        orElse: () => PrototypeScenario.demo,
      ),
    );
    _ensureUploadTicker();
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _thinkingTimer?.cancel();
    _uploadTimer?.cancel();
    _input.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 场景切换

  void _selectScenario(PrototypeScenario scenario) {
    _streamTimer?.cancel();
    _thinkingTimer?.cancel();
    setState(() {
      _applyScenario(scenario);
    });
    _ensureUploadTicker();
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _applyScenario(PrototypeScenario scenario) {
    _scenario = scenario;
    _sentText = '';
    _sentAttachments = [];
    _recording = false;
    _longExpanded = false;
    _chunkIndex = 0;
    _streamText = scenario == PrototypeScenario.streaming
        ? demoStreamingPartial
        : '';
    _phase = scenario == PrototypeScenario.streaming
        ? _StreamPhase.streaming
        : _StreamPhase.idle;
    _draft = scenario == PrototypeScenario.demo
        ? [...demoDraftAttachments]
        : [];
    _input.clear();
  }

  // ------------------------------------------------------------------ 生成流

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _streamTimer?.cancel();
    _thinkingTimer?.cancel();
    setState(() {
      _sentText = text;
      _sentAttachments = [..._draft];
      _draft = [];
      _phase = _StreamPhase.streaming;
      _streamText = '';
      _chunkIndex = 0;
      _thinkingSeconds = 0;
    });
    _startStream();
  }

  void _startStream() {
    _streamTimer?.cancel();
    _startThinkingTimer();
    _streamTimer = Timer.periodic(const Duration(milliseconds: 260), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_chunkIndex >= streamChunks.length) {
          timer.cancel();
          _phase = _StreamPhase.done;
        } else {
          _streamText += streamChunks[_chunkIndex];
          _chunkIndex += 1;
        }
      });
    });
  }

  void _stop() {
    _streamTimer?.cancel();
    _thinkingTimer?.cancel();
    setState(() => _phase = _StreamPhase.stopped);
  }

  void _startThinkingTimer() {
    _thinkingTimer?.cancel();
    _thinkingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _phase != _StreamPhase.streaming) {
        timer.cancel();
        return;
      }
      setState(() => _thinkingSeconds += 1);
    });
  }

  void _continue() {
    _streamTimer?.cancel();
    if (_chunkIndex >= streamChunks.length) _chunkIndex = 0;
    setState(() => _phase = _StreamPhase.streaming);
    _startStream();
  }

  void _regenerate() {
    setState(() {
      _branchCount += 1;
      _branch = _branchCount;
    });
  }

  void _copy() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制到剪贴板（原型占位）')));
  }

  void _readAloud() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('开始朗读（原型占位）')));
  }

  // ------------------------------------------------------------------- 附件

  void _attach() {
    setState(() {
      _draft = [
        ..._draft,
        FakeAttachment(
          name: '新图片-${_draft.length + 1}.jpg',
          isImage: true,
          uploadProgress: 0,
        ),
      ];
    });
    _ensureUploadTicker();
  }

  void _removeAttachment(int index) {
    setState(() {
      _draft = [..._draft]..removeAt(index);
    });
  }

  void _retryAttachment(int index) {
    final attachment = _draft[index];
    setState(() {
      _draft = [..._draft]
        ..[index] = FakeAttachment(
          name: attachment.name,
          isImage: attachment.isImage,
          uploadProgress: 0,
        );
    });
    _ensureUploadTicker();
  }

  void _ensureUploadTicker() {
    if (_uploadTimer?.isActive ?? false) return;
    final hasUploading =
        _draft.any((item) => item.uploadProgress != null) ||
        _sentAttachments.any((item) => item.uploadProgress != null);
    if (!hasUploading) return;
    _uploadTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final stillUploading =
          _draft.any((item) => item.uploadProgress != null) ||
          _sentAttachments.any((item) => item.uploadProgress != null);
      if (!stillUploading) {
        timer.cancel();
        return;
      }
      setState(() {
        _draft = _tickUpload(_draft);
        _sentAttachments = _tickUpload(_sentAttachments);
      });
    });
  }

  List<FakeAttachment> _tickUpload(List<FakeAttachment> items) {
    return [
      for (final item in items)
        if (item.uploadProgress == null)
          item
        else if (item.uploadProgress! + 0.12 >= 1)
          FakeAttachment(name: item.name, isImage: item.isImage)
        else
          item.copyWith(uploadProgress: item.uploadProgress! + 0.12),
    ];
  }

  // ------------------------------------------------------------------- 会话

  void _newChat() {
    setState(() {
      final session = FakeSession(_nextSessionId++, '新对话', '刚刚');
      _sessions.insert(0, session);
      _sessionTitle = session.title;
      _selectedSessionId = session.id;
      _applyScenario(PrototypeScenario.empty);
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _openSession(FakeSession session) {
    _streamTimer?.cancel();
    setState(() {
      _sessionTitle = session.title;
      _selectedSessionId = session.id;
      _applyScenario(PrototypeScenario.demo);
    });
    _ensureUploadTicker();
    _scaffoldKey.currentState?.closeDrawer();
  }

  Future<void> _renameSession(FakeSession session) async {
    final field = TextEditingController(text: session.title);
    final title = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('重命名会话'),
        description: const Text('只修改本地标题，消息内容不受影响。'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: const Text('保存'),
          ),
        ],
        child: ShadInput(controller: field, autofocus: true),
      ),
    );
    field.dispose();
    if (title == null || title.trim().isEmpty || !mounted) return;
    setState(() {
      final index = _sessions.indexWhere((item) => item.id == session.id);
      if (index >= 0) {
        _sessions[index] = FakeSession(session.id, title.trim(), session.time);
      }
      if (_selectedSessionId == session.id) _sessionTitle = title.trim();
    });
  }

  Future<void> _deleteSession(FakeSession session) async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('删除会话？'),
        description: Text('「${session.title}」及其消息将从本地移除。'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _sessions.removeWhere((item) => item.id == session.id);
      if (_selectedSessionId == session.id) {
        if (_sessions.isEmpty) {
          _selectedSessionId = -1;
          _sessionTitle = '新对话';
        } else {
          _selectedSessionId = _sessions.first.id;
          _sessionTitle = _sessions.first.title;
        }
        _applyScenario(PrototypeScenario.empty);
      }
    });
  }

  // ------------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colors.background,
      drawer: _SessionDrawer(
        colors: colors,
        sessions: _sessions,
        selectedId: _selectedSessionId,
        dark: widget.dark,
        scenario: _scenario,
        model: _model,
        onScenario: _selectScenario,
        onModelChanged: (value) => setState(() => _model = value),
        onNewChat: _newChat,
        onOpen: _openSession,
        onRename: _renameSession,
        onDelete: _deleteSession,
        onToggleTheme: widget.onToggleTheme,
        onClose: () => _scaffoldKey.currentState?.closeDrawer(),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: _scenario == PrototypeScenario.empty && !_hasLiveReply
                  ? ''
                  : _sessionTitle,
              onMenu: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                children: _content(),
              ),
            ),
            Composer(
              controller: _input,
              attachments: _draft,
              thinking: _thinking,
              search: _search,
              recording: _recording,
              busy: _busy,
              onThinkingChanged: (value) => setState(() => _thinking = value),
              onSearchChanged: (value) => setState(() => _search = value),
              onAttach: _attach,
              onRemoveAttachment: _removeAttachment,
              onRetryAttachment: _retryAttachment,
              onVoice: () => setState(() => _recording = !_recording),
              onReadAloud: _readAloud,
              onSend: _send,
              onStop: _stop,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '内容由 AI 生成，请仔细甄别',
                style: TextStyle(fontSize: 10.5, color: colors.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content() {
    if (_hasLiveReply) {
      return [
        _gap(
          UserBubble(
            text: _sentText,
            attachments: _sentAttachments,
            onEdit: _editPlaceholder,
          ),
        ),
        _gap(_liveReply()),
      ];
    }
    switch (_scenario) {
      case PrototypeScenario.demo:
        return [
          _gap(
            UserBubble(
              text: demoUserQuestion,
              attachments: demoUserAttachments,
              onEdit: () => ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('编辑提问（原型占位）'))),
            ),
          ),
          _gap(_completedReply()),
        ];
      case PrototypeScenario.empty:
        return [
          SizedBox(
            height: 430,
            child: Center(
              child: Text(
                '今天有什么可以帮到你？',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: ShadTheme.of(context).colorScheme.foreground,
                ),
              ),
            ),
          ),
        ];
      case PrototypeScenario.loading:
        return [const LoadingView()];
      case PrototypeScenario.error:
        return [
          _gap(const UserBubble(text: '帮我查一下这周 AI 领域的重要发布。')),
          ErrorCard(onRetry: () => _selectScenario(PrototypeScenario.demo)),
        ];
      case PrototypeScenario.stopped:
        return [
          _gap(UserBubble(text: demoFollowUp, onEdit: _editPlaceholder)),
          _gap(
            AssistantView(
              text: demoStreamingPartial,
              thinking: demoStreamingThinking,
              thinkingExpanded: _streamThinkingExpanded,
              onThinkingToggle: () => setState(
                () => _streamThinkingExpanded = !_streamThinkingExpanded,
              ),
              showActions: false,
            ),
          ),
          StoppedNotice(onContinue: _retryStream),
        ];
      case PrototypeScenario.dropped:
        return [
          _gap(UserBubble(text: demoFollowUp, onEdit: _editPlaceholder)),
          _gap(
            AssistantView(
              text: demoStreamingPartial,
              thinking: demoStreamingThinking,
              thinkingExpanded: _streamThinkingExpanded,
              onThinkingToggle: () => setState(
                () => _streamThinkingExpanded = !_streamThinkingExpanded,
              ),
              showActions: false,
            ),
          ),
          ShadAlert(
            icon: const Icon(LucideIcons.wifiOff),
            title: const Text('连接中断'),
            description: const Text(droppedDescription),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ShadButton.outline(
              key: const Key('retry-stream-button'),
              onPressed: _retryStream,
              foregroundColor: ShadTheme.of(context).colorScheme.foreground,
              height: 30,
              child: const Text('重试'),
            ),
          ),
        ];
      case PrototypeScenario.refusal:
        return [
          _gap(const UserBubble(text: '帮我写一段绕过审核的营销文案。')),
          const RefusalCard(),
        ];
      case PrototypeScenario.long:
        return [
          _gap(const UserBubble(text: '把上面那篇评测整理成一份详细报告。')),
          _gap(
            LongAnswerView(
              text: longAnswer,
              expanded: _longExpanded,
              onToggle: () => setState(() => _longExpanded = !_longExpanded),
            ),
          ),
        ];
      case PrototypeScenario.streaming:
        return [
          _gap(UserBubble(text: demoFollowUp, onEdit: _editPlaceholder)),
          _gap(_liveReply()),
        ];
    }
  }

  void _editPlaceholder() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('编辑提问（原型占位）')));
  }

  void _retryStream() {
    setState(() {
      _scenario = PrototypeScenario.streaming;
      _streamText = demoStreamingPartial;
      _chunkIndex = 0;
      _thinkingSeconds = 0;
      _phase = _StreamPhase.streaming;
    });
    _startStream();
  }

  Widget _gap(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 16), child: child);

  Widget _completedReply() {
    return AssistantView(
      text: _branch == 1 ? demoAnswer : demoBranchTwo,
      thinking: demoThinking,
      thinkingSeconds: 12,
      thinkingExpanded: _thinkingExpanded,
      onThinkingToggle: () =>
          setState(() => _thinkingExpanded = !_thinkingExpanded),
      citationCount: 2,
      sources: demoSources,
      onRegenerate: _regenerate,
      onCopy: _copy,
      onReadAloud: _readAloud,
      onStop: null,
      branchSwitcher: BranchSwitcher(
        branch: _branch,
        count: _branchCount,
        onPrev: () => setState(() => _branch -= 1),
        onNext: () => setState(() => _branch += 1),
      ),
    );
  }

  Widget _liveReply() {
    final streaming = _phase == _StreamPhase.streaming;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AssistantView(
          text: _streamText,
          thinking: demoStreamingThinking,
          thinkingSeconds: _thinkingSeconds,
          thinkingExpanded: _streamThinkingExpanded,
          onThinkingToggle: () => setState(
            () => _streamThinkingExpanded = !_streamThinkingExpanded,
          ),
          streaming: streaming,
          showSearchProgress: streaming && _search,
          showActions: !streaming,
          citationCount: streaming ? 0 : 1,
          sources: streaming ? const [] : [demoSources.first],
          onRegenerate: _regenerate,
          onCopy: _copy,
          onReadAloud: _readAloud,
          onStop: streaming ? _stop : null,
        ),
        if (_phase == _StreamPhase.stopped)
          StoppedNotice(onContinue: _continue),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onMenu});

  final String title;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          const SizedBox(width: 8),
          ShadIconButton.ghost(
            key: const Key('menu-button'),
            onPressed: onMenu,
            icon: const Icon(LucideIcons.menu),
            width: 36,
            height: 36,
            iconSize: 19,
            foregroundColor: colors.foreground,
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: colors.foreground,
                ),
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _ScenarioPill extends StatelessWidget {
  const _ScenarioPill({
    required this.scenario,
    required this.selected,
    required this.onTap,
  });

  final PrototypeScenario scenario;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return GestureDetector(
      key: Key('scenario-${scenario.name}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? colors.foreground : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? colors.foreground : colors.border,
          ),
        ),
        child: Text(
          scenario.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? colors.background : colors.foreground,
          ),
        ),
      ),
    );
  }
}

class _SessionDrawer extends StatelessWidget {
  const _SessionDrawer({
    required this.colors,
    required this.sessions,
    required this.selectedId,
    required this.dark,
    required this.scenario,
    required this.model,
    required this.onScenario,
    required this.onModelChanged,
    required this.onNewChat,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onToggleTheme,
    required this.onClose,
  });

  final ShadColorScheme colors;
  final List<FakeSession> sessions;
  final int selectedId;
  final bool dark;
  final PrototypeScenario scenario;
  final String model;
  final ValueChanged<PrototypeScenario> onScenario;
  final ValueChanged<String> onModelChanged;
  final VoidCallback onNewChat;
  final ValueChanged<FakeSession> onOpen;
  final ValueChanged<FakeSession> onRename;
  final ValueChanged<FakeSession> onDelete;
  final VoidCallback onToggleTheme;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 304,
      backgroundColor: colors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colors.foreground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      LucideIcons.sparkles,
                      size: 16,
                      color: colors.background,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SeekChat',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.foreground,
                    ),
                  ),
                  const Spacer(),
                  ShadIconButton.ghost(
                    onPressed: onClose,
                    icon: const Icon(LucideIcons.x),
                    width: 30,
                    height: 30,
                    iconSize: 15,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ShadButton.outline(
                  key: const Key('drawer-new-chat'),
                  onPressed: onNewChat,
                  foregroundColor: colors.foreground,
                  leading: const Icon(LucideIcons.plus, size: 15),
                  height: 36,
                  child: const Text('新对话'),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '最近会话',
                style: TextStyle(fontSize: 11, color: colors.mutedForeground),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final selected = session.id == selectedId;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: selected ? colors.muted : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: InkWell(
                        onTap: () => onOpen(session),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.messageSquare,
                                size: 14,
                                color: selected
                                    ? colors.foreground
                                    : colors.mutedForeground,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      session.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colors.foreground,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                    Text(
                                      session.time,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colors.mutedForeground,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<_SessionAction>(
                                icon: Icon(
                                  LucideIcons.ellipsis,
                                  size: 14,
                                  color: colors.mutedForeground,
                                ),
                                tooltip: '会话操作',
                                onSelected: (action) {
                                  switch (action) {
                                    case _SessionAction.rename:
                                      onRename(session);
                                    case _SessionAction.delete:
                                      onDelete(session);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: _SessionAction.rename,
                                    child: Text('重命名'),
                                  ),
                                  PopupMenuItem(
                                    value: _SessionAction.delete,
                                    child: Text('删除'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Divider(height: 20, color: colors.border),
              GestureDetector(
                key: const Key('drawer-model'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onModelChanged(
                  model == 'deepseek-flash'
                      ? 'deepseek-reasoner'
                      : 'deepseek-flash',
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.sparkles,
                        size: 14,
                        color: colors.mutedForeground,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '模型',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.mutedForeground,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        model == 'deepseek-flash'
                            ? 'DeepSeek V3.2'
                            : 'DeepSeek R1',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.foreground,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 13,
                        color: colors.mutedForeground,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '原型场景',
                style: TextStyle(fontSize: 11, color: colors.mutedForeground),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final item in PrototypeScenario.values)
                    _ScenarioPill(
                      scenario: item,
                      selected: item == scenario,
                      onTap: () => onScenario(item),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    dark ? '深色主题' : '浅色主题',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.mutedForeground,
                    ),
                  ),
                  const Spacer(),
                  ShadSwitch(
                    key: const Key('drawer-theme-switch'),
                    value: dark,
                    onChanged: (_) => onToggleTheme(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
