import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:system_tray/system_tray.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

const int discoveryPort = 45678;
const int messagePort = 45679;
const int filePort = 45681;
const int singleInstancePort = 45680;
const String groupId = 'group:lan';
const String appTitle = 'LanChat';
const MethodChannel _androidFileChannel = MethodChannel('lanchat/open_file');
SystemTray? globalSystemTray;
Timer? globalTrayBlinkTimer;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    final canStart = await _ensureSingleInstance();
    if (!canStart) return;
    await windowManager.ensureInitialized();
    await windowManager.setTitle(appTitle);
    await localNotifier.setup(appName: appTitle);
  }
  runApp(const LanChatApp());
}

Future<bool> _ensureSingleInstance() async {
  try {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, singleInstancePort, shared: false);
    server.listen((socket) async {
      await socket.drain<void>();
      await windowManager.show();
      await windowManager.focus();
      await windowManager.restore();
    });
    return true;
  } catch (_) {
    try {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, singleInstancePort, timeout: const Duration(milliseconds: 500));
      socket.write('show');
      await socket.close();
    } catch (_) {}
    return false;
  }
}

class LanChatApp extends StatelessWidget {
  const LanChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F7CFF)),
        scaffoldBackgroundColor: const Color(0xFFF2F5FA),
        useMaterial3: true,
      ),
      home: const ChatHomePage(),
    );
  }
}

class AppSettings {
  AppSettings({
    required this.deviceId,
    required this.nickname,
    required this.saveDir,
    required this.cacheDir,
    this.enterToSend = true,
    this.askOnClose = true,
    this.minimizeOnClose = true,
    this.notificationsEnabled = true,
  });

  String deviceId;
  String nickname;
  String saveDir;
  String cacheDir;
  bool enterToSend;
  bool askOnClose;
  bool minimizeOnClose;
  bool notificationsEnabled;

      Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'nickname': nickname,
        'saveDir': saveDir,
        'cacheDir': cacheDir,
        'enterToSend': enterToSend,
        'askOnClose': askOnClose,
        'minimizeOnClose': minimizeOnClose,
        'notificationsEnabled': notificationsEnabled,
      };

  static AppSettings fromJson(Map<String, dynamic> json, AppSettings fallback) {
    return AppSettings(
      deviceId: json['deviceId'] as String? ?? fallback.deviceId,
      nickname: json['nickname'] as String? ?? fallback.nickname,
      saveDir: json['saveDir'] as String? ?? fallback.saveDir,
      cacheDir: json['cacheDir'] as String? ?? fallback.cacheDir,
      enterToSend: json['enterToSend'] as bool? ?? fallback.enterToSend,
      askOnClose: json['askOnClose'] as bool? ?? fallback.askOnClose,
      minimizeOnClose: json['minimizeOnClose'] as bool? ?? fallback.minimizeOnClose,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? fallback.notificationsEnabled,
    );
  }
}

class Peer {
  Peer({required this.id, required this.name, required this.address, required this.deviceType, required this.lastSeen});

  final String id;
  final String name;
  final InternetAddress address;
  final String deviceType;
  DateTime lastSeen;
}

class WireMessage {
  WireMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.targetId,
    required this.type,
    required this.createdAt,
    this.text,
    this.fileName,
    this.fileSize,
    this.fileBase64,
    this.transferId,
    this.localPath,
    this.transferStatus,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String targetId;
  String type;
  final DateTime createdAt;
  String? text;
  String? fileName;
  int? fileSize;
  String? fileBase64;
  String? transferId;
  String? localPath;
  String? transferStatus;

  Uint8List? get bytes => fileBase64 == null ? null : base64Decode(fileBase64!);

  Map<String, dynamic> toJson() => {
        'kind': 'message',
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'targetId': targetId,
        'type': type,
        'createdAt': createdAt.toIso8601String(),
        'text': text,
        'fileName': fileName,
        'fileSize': fileSize,
        'fileBase64': fileBase64,
        'transferId': transferId,
        'localPath': localPath,
        'transferStatus': transferStatus,
      };

  static WireMessage? fromJson(Map<String, dynamic> json) {
    if (json['kind'] != 'message') return null;
    return WireMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      targetId: json['targetId'] as String,
      type: json['type'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      text: json['text'] as String?,
      fileName: json['fileName'] as String?,
      fileSize: json['fileSize'] as int?,
      fileBase64: json['fileBase64'] as String?,
      transferId: json['transferId'] as String?,
      localPath: json['localPath'] as String?,
      transferStatus: json['transferStatus'] as String?,
    );
  }
}

class PendingFile {
  PendingFile({required this.peerId, required this.name, required this.fileSize, this.localPath, this.bytes});
  final String peerId;
  final String name;
  final int fileSize;
  final String? localPath;
  final Uint8List? bytes;
}

class IncomingFileRequest {
  IncomingFileRequest({required this.senderId, required this.fileName, required this.fileSize});
  final String senderId;
  final String fileName;
  final int fileSize;
}

class _SessionEntry {
  _SessionEntry({required this.id, required this.title, required this.subtitle, required this.deviceType});
  final String id;
  final String title;
  final String subtitle;
  final String deviceType;
}

class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key});

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> with WidgetsBindingObserver, WindowListener {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final Map<String, Peer> _peers = {};
  final Map<String, int> _unread = {};
  final Map<String, PendingFile> _pendingFiles = {};
  final Map<String, IncomingFileRequest> _incomingFileRequests = {};
  final List<WireMessage> _messages = [];
  final Set<String> _seenMessageIds = {};
  final Map<String, String> _receivedFiles = {};
  String _deviceId = '';
  late AppSettings _settings;
  String _selectedTargetId = groupId;
  RawDatagramSocket? _discoverySocket;
  ServerSocket? _serverSocket;
  ServerSocket? _fileServerSocket;
  Timer? _announceTimer;
  Timer? _cleanupTimer;
  String? _trayIconPath;
  String _status = '正在启动...';
  bool _ready = false;
  int _mobileTabIndex = 0;
  final List<VoidCallback> _mobileChatListeners = [];

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    for (final listener in List<VoidCallback>.from(_mobileChatListeners)) {
      listener();
    }
  }

  bool _isChatNearBottom() {
    if (!_chatScrollController.hasClients) return true;
    final position = _chatScrollController.position;
    return position.pixels <= 160;
  }

  void _scheduleScrollToBottom({bool stabilize = false}) {
    void jump() {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      if (stabilize) {
        Future<void>.delayed(const Duration(milliseconds: 80), jump);
        Future<void>.delayed(const Duration(milliseconds: 250), jump);
      }
    });
  }

  void _resetChatScrollPosition() {
    if (!_chatScrollController.hasClients) return;
    _chatScrollController.jumpTo(0);
  }

  String get _deviceType => Platform.isWindows ? 'pc' : 'phone';
  String get _deviceName => _settings.nickname;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
      _initTray();
    }
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows) windowManager.removeListener(this);
    _messageController.dispose();
    _chatScrollController.dispose();
    _stopNetworking();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restartDiscovery();
    }
  }

  @override
  Future<void> onWindowClose() async {
    if (!_settings.askOnClose) {
      if (_settings.minimizeOnClose) {
        await windowManager.hide();
      } else {
        _exitNow();
      }
      return;
    }
    if (!mounted) return;
    var dontAsk = false;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('关闭 LanChat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('你想完全关闭，还是隐藏到后台？'),
              CheckboxListTile(
                value: dontAsk,
                onChanged: (value) => setDialogState(() => dontAsk = value ?? false),
                title: const Text('不再提醒'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'hide'), child: const Text('隐藏到后台')),
            FilledButton(onPressed: () => Navigator.pop(context, 'exit'), child: const Text('完全关闭')),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (dontAsk) {
      _settings.askOnClose = false;
      _settings.minimizeOnClose = action == 'hide';
      await _saveSettings();
    }
    if (action == 'hide') {
      await windowManager.hide();
    } else {
      _exitNow();
    }
  }

  void _exitNow() {
    unawaited(Future<void>(() async {
      try {
        await windowManager.hide();
      } catch (_) {}
      try {
        await windowManager.setPreventClose(false);
      } catch (_) {}
      try {
        await _destroyTray();
      } catch (_) {}
      unawaited(Future<void>(() async {
        _broadcastOffline();
        _stopNetworking();
      }));
      try {
        await windowManager.destroy();
      } catch (_) {
        exit(0);
      }
    }));
  }

  Future<void> _initTray() async {
    final tray = SystemTray();
    final menu = Menu();
    final iconPath = Platform.resolvedExecutable.replaceFirst(RegExp(r'[^\\/]+$'), 'app_icon.ico');
    _trayIconPath = iconPath;
    await tray.initSystemTray(title: appTitle, iconPath: iconPath);
    await tray.setToolTip(appTitle);
    await menu.buildFrom([
      MenuItemLabel(label: '打开 LanChat', onClicked: (_) => _showMainWindow()),
      MenuItemLabel(label: '退出', onClicked: (_) => _exitNow()),
    ]);
    await tray.setContextMenu(menu);
    tray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick || eventName == kSystemTrayEventDoubleClick) {
        _showMainWindow();
      } else if (eventName == kSystemTrayEventRightClick) {
        tray.popUpContextMenu();
      }
    });
    globalSystemTray = tray;
  }

  Future<void> _showMainWindow() async {
    if (!Platform.isWindows) return;
    _stopTrayBlink();
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  void _startTrayBlink(String tip) {
    if (!Platform.isWindows || globalSystemTray == null || _trayIconPath == null) return;
    globalSystemTray!.setToolTip(tip);
    globalTrayBlinkTimer?.cancel();
    var visible = true;
    globalTrayBlinkTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      visible = !visible;
      globalSystemTray!.setToolTip(visible ? tip : appTitle);
    });
  }

  void _stopTrayBlink() {
    globalTrayBlinkTimer?.cancel();
    globalTrayBlinkTimer = null;
    if (Platform.isWindows && globalSystemTray != null && _trayIconPath != null) {
      globalSystemTray!.setImage(_trayIconPath!);
      globalSystemTray!.setToolTip(appTitle);
    }
  }

  Future<void> _showWindowsNotification(String title, String body, {String? sessionId}) async {
    if (!Platform.isWindows || !_settings.notificationsEnabled) return;
    final notification = LocalNotification(title: title, body: body);
    notification.onClick = () {
      if (sessionId != null) {
        setState(() {
          _selectedTargetId = sessionId;
          _unread.remove(sessionId);
        });
      }
      _showMainWindow();
    };
    await notification.show();
  }

  Future<void> _destroyTray() async {
    globalTrayBlinkTimer?.cancel();
    globalTrayBlinkTimer = null;
    final tray = globalSystemTray;
    globalSystemTray = null;
    if (tray != null) {
      try {
        await tray.destroy();
      } catch (_) {}
    }
  }

  static String _makeId() {
    final random = Random.secure();
    final values = List<int>.generate(12, (_) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  Future<void> _init() async {
    final support = await getApplicationSupportDirectory();
    final docs = await getApplicationDocumentsDirectory();
    final externalDir = Platform.isAndroid ? await getExternalStorageDirectory() : null;
    final baseDir = externalDir?.path ?? docs.path;
    final cacheBase = Platform.isAndroid ? (await getTemporaryDirectory()).path : support.path;
    final generatedDeviceId = _makeId();
    final fallback = AppSettings(
      deviceId: generatedDeviceId,
      nickname: '${Platform.isWindows ? '电脑' : '手机'}-${generatedDeviceId.substring(0, 4)}',
      saveDir: '$baseDir${Platform.pathSeparator}LanChat Received',
      cacheDir: '$cacheBase${Platform.pathSeparator}cache',
    );
    final settingsFile = File('${support.path}${Platform.pathSeparator}settings.json');
    if (await settingsFile.exists()) {
      _settings = AppSettings.fromJson(jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>, fallback);
    } else {
      _settings = fallback;
      await _saveSettings();
    }
    if (Platform.isAndroid) {
      if (_settings.saveDir.contains('app_flutter')) _settings.saveDir = fallback.saveDir;
      if (_settings.cacheDir.contains('app_flutter')) _settings.cacheDir = fallback.cacheDir;
    }
    _deviceId = _settings.deviceId;
    await _saveSettings();
    await Directory(_settings.saveDir).create(recursive: true);
    await Directory(_settings.cacheDir).create(recursive: true);
    setState(() => _ready = true);
    await _startNetworking();
  }

  Future<void> _saveSettings() async {
    final support = await getApplicationSupportDirectory();
    await Directory(support.path).create(recursive: true);
    await File('${support.path}${Platform.pathSeparator}settings.json').writeAsString(jsonEncode(_settings.toJson()));
  }

  Future<void> _startNetworking() async {
    try {
      _serverSocket ??= await ServerSocket.bind(InternetAddress.anyIPv4, messagePort, shared: true);
      _serverSocket!.listen(_handleClient, onError: (_) => _setStatus('消息监听失败'));
      _fileServerSocket ??= await ServerSocket.bind(InternetAddress.anyIPv4, filePort, shared: true);
      _fileServerSocket!.listen(_handleFileClient, onError: (_) => _setStatus('文件监听失败'));
      await _startDiscoverySocket();
      _announceTimer ??= Timer.periodic(const Duration(seconds: 2), (_) => _announce());
      _cleanupTimer ??= Timer.periodic(const Duration(seconds: 5), (_) => _cleanupPeers());
      _announceBurst();
      _setStatus('在线，等待局域网设备加入');
    } catch (error) {
      _setStatus('启动失败：$error');
    }
  }

  Future<void> _startDiscoverySocket() async {
    _discoverySocket?.close();
    _discoverySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true);
    _discoverySocket!.broadcastEnabled = true;
    _discoverySocket!.listen(_handleDiscoveryEvent);
  }

  void _stopNetworking() {
    _announceTimer?.cancel();
    _cleanupTimer?.cancel();
    _announceTimer = null;
    _cleanupTimer = null;
    _discoverySocket?.close();
    _serverSocket?.close();
    _fileServerSocket?.close();
    _discoverySocket = null;
    _serverSocket = null;
    _fileServerSocket = null;
  }

  Future<void> _restartDiscovery() async {
    await _startDiscoverySocket();
    _announceBurst();
    _setStatus('已重新广播在线状态');
  }

  void _announceBurst() {
    for (var i = 0; i < 5; i++) {
      Future<void>.delayed(Duration(milliseconds: 250 * i), _announce);
    }
  }

  void _setStatus(String status) {
    if (!mounted) return;
    setState(() => _status = status);
  }

  void _announce() {
    final socket = _discoverySocket;
    if (socket == null || !_ready) return;
    final payload = utf8.encode(jsonEncode({
      'kind': 'announce',
      'id': _deviceId,
      'name': _deviceName,
      'deviceType': _deviceType,
      'port': messagePort,
    }));
    socket.send(payload, InternetAddress('255.255.255.255'), discoveryPort);
  }

  void _broadcastOffline() {
    final socket = _discoverySocket;
    if (socket == null || _deviceId.isEmpty) return;
    final payload = utf8.encode(jsonEncode({
      'kind': 'bye',
      'id': _deviceId,
    }));
    for (var i = 0; i < 3; i++) {
      socket.send(payload, InternetAddress('255.255.255.255'), discoveryPort);
    }
  }

  void _handleDiscoveryEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    Datagram? datagram;
    while ((datagram = _discoverySocket?.receive()) != null) {
      try {
        final data = jsonDecode(utf8.decode(datagram!.data)) as Map<String, dynamic>;
        final kind = data['kind'];
        final id = data['id'] as String?;
        if (id == null || id == _deviceId) continue;
        if (kind == 'bye') {
          setState(() {
            _peers.remove(id);
            if (_selectedTargetId == id) _selectedTargetId = groupId;
          });
          continue;
        }
        if (kind != 'announce') continue;
        final peer = Peer(
          id: id,
          name: data['name'] as String? ?? '未知设备',
          deviceType: data['deviceType'] as String? ?? 'phone',
          address: datagram.address,
          lastSeen: DateTime.now(),
        );
        final old = _peers[peer.id];
        if (old == null || old.name != peer.name || old.address.address != peer.address.address || old.deviceType != peer.deviceType) {
          setState(() => _peers[peer.id] = peer);
        } else {
          old.lastSeen = DateTime.now();
        }
      } catch (_) {}
    }
  }

  void _cleanupPeers() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 20));
    final removedSelected = _selectedTargetId != groupId && (_peers[_selectedTargetId]?.lastSeen.isBefore(cutoff) ?? true);
    final goneIds = _peers.entries.where((e) => e.value.lastSeen.isBefore(cutoff)).map((e) => e.key).toList();
    setState(() {
      _peers.removeWhere((_, peer) => peer.lastSeen.isBefore(cutoff));
      if (removedSelected) _selectedTargetId = groupId;
    });
    for (final peerId in goneIds) {
      final pendingTransferIds = _pendingFiles.entries.where((e) => e.value.peerId == peerId).map((e) => e.key).toList();
      for (final transferId in pendingTransferIds) {
        _pendingFiles.remove(transferId);
        _updateTransferStatus(transferId, 'rejected');
      }
      final incomingTransferIds = _incomingFileRequests.entries.where((e) => e.value.senderId == peerId).map((e) => e.key).toList();
      for (final transferId in incomingTransferIds) {
        _incomingFileRequests.remove(transferId);
        _updateTransferStatus(transferId, 'canceled');
      }
    }
  }

  Future<void> _handleClient(Socket socket) async {
    final buffer = BytesBuilder();
    await for (final data in socket) {
      buffer.add(data);
    }
    socket.destroy();
    try {
      final message = WireMessage.fromJson(jsonDecode(utf8.decode(buffer.takeBytes())) as Map<String, dynamic>);
      if (message == null || message.senderId == _deviceId || _seenMessageIds.contains(message.id)) return;
      if (message.targetId != groupId && message.targetId != _deviceId) return;
      _seenMessageIds.add(message.id);
      await _handleIncomingMessage(message);
    } catch (_) {
      _setStatus('收到无法解析的消息');
    }
  }

  Future<void> _handleFileClient(Socket socket) async {
    final headerBytes = <int>[];
    var headerDone = false;
    WireMessage? meta;
    IOSink? sink;
    String? path;
    try {
      await for (final data in socket) {
        var start = 0;
        if (!headerDone) {
          final newline = data.indexOf(10);
          if (newline == -1) {
            headerBytes.addAll(data);
            continue;
          }
          headerBytes.addAll(data.sublist(0, newline));
          meta = WireMessage.fromJson(jsonDecode(utf8.decode(headerBytes)) as Map<String, dynamic>);
          if (meta == null || meta.type != 'file_stream' || meta.targetId != _deviceId || meta.fileName == null) {
            throw const FormatException('invalid file stream header');
          }
          final request = _incomingFileRequests.remove(meta.transferId);
          final safeName = meta.fileName!.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          await Directory(_settings.saveDir).create(recursive: true);
          path = '${_settings.saveDir}${Platform.pathSeparator}$safeName';
          sink = File(path).openWrite();
          headerDone = true;
          start = newline + 1;
          if (request == null) {
            // Keep receiving only if the user explicitly accepted this transfer.
            throw const FormatException('unexpected file stream');
          }
        }
        if (start < data.length) {
          sink?.add(data.sublist(start));
        }
      }
      await sink?.flush();
      await sink?.close();
      if (meta != null && path != null) {
        _updateTransferStatus(meta.transferId, 'completed', localPath: path);
        _setStatus('文件已保存到：$path');
      }
    } catch (_) {
      await sink?.close();
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      socket.destroy();
      return;
    }
  }

  Future<void> _handleIncomingMessage(WireMessage message) async {
    if (message.type == 'file_request') {
      _onIncomingFileRequest(message);
      return;
    }
    if (message.type == 'file_accept') {
      final pending = _pendingFiles.remove(message.transferId);
      _updateTransferStatus(message.transferId, 'accepted');
      if (pending != null) await _sendFileData(pending, message.transferId!);
      return;
    }
    if (message.type == 'file_reject') {
      _pendingFiles.remove(message.transferId);
      _updateTransferStatus(message.transferId, 'rejected');
      return;
    }
    final sessionId = message.targetId == groupId ? groupId : message.senderId;
    final shouldFollow = _selectedTargetId == sessionId && _isChatNearBottom();
    setState(() {
      _messages.add(message);
      if (_selectedTargetId != sessionId) {
        _unread[sessionId] = (_unread[sessionId] ?? 0) + 1;
        final preview = message.type == 'image' ? '[图片]' : message.text ?? '[新消息]';
        _startTrayBlink('${message.senderName}: $preview');
        unawaited(_showWindowsNotification(message.senderName, preview, sessionId: sessionId));
      }
    });
    if (shouldFollow) _scheduleScrollToBottom(stabilize: message.type == 'image');
  }

  void _onIncomingFileRequest(WireMessage message) {
    if (message.transferId == null || message.fileName == null) return;
    _incomingFileRequests[message.transferId!] = IncomingFileRequest(
      senderId: message.senderId,
      fileName: message.fileName!,
      fileSize: message.fileSize ?? 0,
    );
    final bubble = WireMessage(
      id: message.id,
      senderId: message.senderId,
      senderName: message.senderName,
      targetId: _deviceId,
      type: 'file_request',
      createdAt: message.createdAt,
      fileName: message.fileName,
      fileSize: message.fileSize,
      transferId: message.transferId,
      transferStatus: 'pending',
    );
    final sessionId = message.senderId;
    final shouldFollow = _selectedTargetId == sessionId && _isChatNearBottom();
    setState(() {
      _messages.add(bubble);
      if (_selectedTargetId != sessionId) {
        _unread[sessionId] = (_unread[sessionId] ?? 0) + 1;
      }
    });
    if (shouldFollow) _scheduleScrollToBottom();
    final preview = '请求发送文件：${message.fileName}';
    _startTrayBlink('${message.senderName}: $preview');
    unawaited(_showWindowsNotification(message.senderName, preview, sessionId: message.senderId));
  }

  void _updateTransferStatus(String? transferId, String status, {String? localPath}) {
    if (transferId == null) return;
    final index = _messages.indexWhere((m) => m.transferId == transferId && (m.type == 'file_request' || m.type == 'file'));
    if (index < 0) return;
    setState(() {
      final msg = _messages[index];
      msg.transferStatus = status;
      if (status == 'completed') {
        msg.type = 'file';
        if (localPath != null) {
          msg.localPath = localPath;
          _receivedFiles[msg.id] = localPath;
        }
      }
    });
  }

  Future<void> _acceptIncomingFile(WireMessage bubble) async {
    if (bubble.transferId == null) return;
    _incomingFileRequests[bubble.transferId!] = IncomingFileRequest(
      senderId: bubble.senderId,
      fileName: bubble.fileName ?? '',
      fileSize: bubble.fileSize ?? 0,
    );
    setState(() => bubble.transferStatus = 'accepted');
    await _sendControl(bubble.senderId, 'file_accept', transferId: bubble.transferId);
  }

  Future<void> _rejectIncomingFile(WireMessage bubble) async {
    if (bubble.transferId == null) return;
    _incomingFileRequests.remove(bubble.transferId);
    setState(() => bubble.transferStatus = 'rejected');
    await _sendControl(bubble.senderId, 'file_reject', transferId: bubble.transferId);
  }

  Future<void> _cancelOutgoingFile(WireMessage bubble) async {
    if (bubble.transferId == null) return;
    _pendingFiles.remove(bubble.transferId);
    setState(() => bubble.transferStatus = 'canceled');
    await _sendControl(bubble.targetId, 'file_reject', transferId: bubble.transferId);
  }

  Future<void> _sendControl(String targetId, String type, {String? transferId}) async {
    await _sendMessage(WireMessage(
      id: _makeId(),
      senderId: _deviceId,
      senderName: _deviceName,
      targetId: targetId,
      type: type,
      createdAt: DateTime.now(),
      transferId: transferId,
    ), addLocal: false);
  }

  Future<void> _sendText() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await _sendMessage(WireMessage(
      id: _makeId(),
      senderId: _deviceId,
      senderName: _deviceName,
      targetId: _selectedTargetId,
      type: 'text',
      createdAt: DateTime.now(),
      text: text,
    ));
  }

  Future<void> _sendImage() async {
    XFile? file;
    Uint8List bytes;
    try {
      file = await openFile(acceptedTypeGroups: [const XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'])]);
      if (file == null) return;
      bytes = await file.readAsBytes();
    } catch (error) {
      _setStatus('选择图片失败：$error');
      return;
    }
    if (bytes.length > 4 * 1024 * 1024) {
      _setStatus('图片超过 4MB，首版暂不发送');
      return;
    }
    await _sendMessage(WireMessage(
      id: _makeId(),
      senderId: _deviceId,
      senderName: _deviceName,
      targetId: _selectedTargetId,
      type: 'image',
      createdAt: DateTime.now(),
      fileName: file.name,
      fileBase64: base64Encode(bytes),
    ));
  }

  Future<void> _sendFileRequest() async {
    if (_selectedTargetId == groupId) {
      _setStatus('文件发送仅支持私聊');
      return;
    }
    String fileName;
    String? localPath;
    Uint8List? bytes;
    int fileSize;
    try {
      final result = await FilePicker.platform.pickFiles(withData: false, allowMultiple: false);
      final picked = result?.files.single;
      if (picked == null) return;
      fileName = picked.name;
      localPath = picked.path;
      fileSize = picked.size;
      if (localPath == null) bytes = picked.bytes;
    } catch (error) {
      _setStatus('选择文件失败：$error');
      return;
    }
    if (localPath == null && bytes == null) {
      _setStatus('无法读取所选文件');
      return;
    }
    final transferId = _makeId();
    final messageId = _makeId();
    _pendingFiles[transferId] = PendingFile(peerId: _selectedTargetId, name: fileName, fileSize: fileSize, bytes: bytes, localPath: localPath);
    final bubble = WireMessage(
      id: messageId,
      senderId: _deviceId,
      senderName: _deviceName,
      targetId: _selectedTargetId,
      type: 'file_request',
      createdAt: DateTime.now(),
      fileName: fileName,
      fileSize: fileSize,
      transferId: transferId,
      transferStatus: 'pending',
      localPath: localPath,
    );
    setState(() => _messages.add(bubble));
    _scheduleScrollToBottom();
    await _sendMessage(WireMessage(
      id: messageId,
      senderId: _deviceId,
      senderName: _deviceName,
      targetId: _selectedTargetId,
      type: 'file_request',
      createdAt: bubble.createdAt,
      fileName: fileName,
      fileSize: fileSize,
      transferId: transferId,
    ), addLocal: false);
  }

  Future<void> _sendDroppedFile(String targetId, String path) async {
    if (targetId == groupId) {
      _setStatus('文件发送仅支持私聊');
      return;
    }
    final file = File(path);
    if (!await file.exists()) return;
    final name = path.split(RegExp(r'[\\/]')).last;
    final size = await file.length();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发送文件'),
        content: Text('是否发送文件给 ${_peers[targetId]?.name ?? '当前用户'}？\n$name\n${_formatBytes(size)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('发送')),
        ],
      ),
    );
    if (ok != true) return;
    final transferId = _makeId();
    final messageId = _makeId();
    _pendingFiles[transferId] = PendingFile(peerId: targetId, name: name, fileSize: size, localPath: path);
    final bubble = WireMessage(
      id: messageId,
      senderId: _deviceId,
      senderName: _deviceName,
      targetId: targetId,
      type: 'file_request',
      createdAt: DateTime.now(),
      fileName: name,
      fileSize: size,
      transferId: transferId,
      transferStatus: 'pending',
      localPath: path,
    );
    setState(() => _messages.add(bubble));
    if (_selectedTargetId == targetId) _scheduleScrollToBottom();
    await _sendMessage(WireMessage(
      id: messageId,
      senderId: _deviceId,
      senderName: _deviceName,
      targetId: targetId,
      type: 'file_request',
      createdAt: bubble.createdAt,
      fileName: name,
      fileSize: size,
      transferId: transferId,
    ), addLocal: false);
  }

  Future<void> _sendFileData(PendingFile pending, String transferId) async {
    final peer = _peers[pending.peerId];
    if (peer == null) {
      _setStatus('对方已离线，无法发送文件');
      _updateTransferStatus(transferId, 'canceled');
      return;
    }
    final bubbleIndex = _messages.indexWhere((m) => m.transferId == transferId);
    final bubbleId = bubbleIndex >= 0 ? _messages[bubbleIndex].id : _makeId();
    final message = WireMessage(
      id: bubbleId,
      senderId: _deviceId,
      senderName: _deviceName,
      targetId: pending.peerId,
      type: 'file_stream',
      createdAt: DateTime.now(),
      fileName: pending.name,
      fileSize: pending.fileSize,
      transferId: transferId,
    );
    try {
      final socket = await Socket.connect(peer.address, filePort, timeout: const Duration(seconds: 5));
      socket.add(utf8.encode('${jsonEncode(message.toJson())}\n'));
      if (pending.localPath != null) {
        await socket.addStream(File(pending.localPath!).openRead());
      } else if (pending.bytes != null) {
        socket.add(pending.bytes!);
      }
      await socket.flush();
      await socket.close();
    } catch (error) {
      _setStatus('文件发送失败：$error');
      _updateTransferStatus(transferId, 'canceled');
      return;
    }
    _updateTransferStatus(transferId, 'completed', localPath: pending.localPath);
  }

  Future<void> _sendMessage(WireMessage message, {bool addLocal = true}) async {
    if (addLocal) {
      setState(() {
        _seenMessageIds.add(message.id);
        _messages.add(message);
      });
      _scheduleScrollToBottom(stabilize: message.type == 'image');
    }
    final targets = message.targetId == groupId ? _peers.values.toList() : [_peers[message.targetId]].whereType<Peer>().toList();
    if (targets.isEmpty) {
      _setStatus('没有可发送的在线设备');
      return;
    }
    final payload = utf8.encode(jsonEncode(message.toJson()));
    var success = 0;
    for (final peer in targets) {
      try {
        final socket = await Socket.connect(peer.address, messagePort, timeout: const Duration(seconds: 3));
        socket.add(payload);
        await socket.flush();
        await socket.close();
        success++;
      } catch (_) {}
    }
    _setStatus('已发送到 $success/${targets.length} 个设备');
  }

  List<WireMessage> get _visibleMessages {
    return _messages.where((message) {
      if (_selectedTargetId == groupId) return message.targetId == groupId;
      return message.targetId == _selectedTargetId || (message.senderId == _selectedTargetId && message.targetId == _deviceId);
    }).toList();
  }

  Future<void> _openSettings() async {
    final nameController = TextEditingController(text: _settings.nickname);
    var enterToSend = _settings.enterToSend;
    var askOnClose = _settings.askOnClose;
    var notificationsEnabled = _settings.notificationsEnabled;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('设置'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: '我的名字')),
                  const SizedBox(height: 12),
                  if (Platform.isWindows) ...[
                    SwitchListTile(
                      title: const Text('回车发送，Shift+回车换行'),
                      value: enterToSend,
                      onChanged: (value) => setDialogState(() => enterToSend = value),
                    ),
                    SwitchListTile(
                      title: const Text('关闭软件时询问'),
                      value: askOnClose,
                      onChanged: (value) => setDialogState(() => askOnClose = value),
                    ),
                    SwitchListTile(
                      title: const Text('消息提醒'),
                      value: notificationsEnabled,
                      onChanged: (value) => setDialogState(() => notificationsEnabled = value),
                    ),
                    const SizedBox(height: 8),
                    Text('文件保存位置：${_settings.saveDir}'),
                    TextButton(onPressed: () => _changeDirectory(isCache: false), child: const Text('更换保存位置并迁移')),
                    Text('缓存位置：${_settings.cacheDir}'),
                    TextButton(onPressed: () => _changeDirectory(isCache: true), child: const Text('更换缓存位置并迁移')),
                  ],
                  if (Platform.isAndroid) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.folder_open_rounded),
                      title: const Text('查看接收的文件'),
                      subtitle: const Text('打开或删除已接收文件'),
                      onTap: _openReceivedFiles,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cleaning_services_rounded),
                      title: const Text('清除缓存'),
                      subtitle: Text(_settings.cacheDir),
                      onTap: () async {
                        await _clearCache();
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                _settings.nickname = nameController.text.trim().isEmpty ? _settings.nickname : nameController.text.trim();
                _settings.enterToSend = enterToSend;
                _settings.askOnClose = askOnClose;
                _settings.notificationsEnabled = notificationsEnabled;
                await _saveSettings();
                _announceBurst();
                if (mounted) setState(() {});
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeDirectory({required bool isCache}) async {
    final selected = await getDirectoryPath();
    if (selected == null || selected.isEmpty) return;
    final oldPath = isCache ? _settings.cacheDir : _settings.saveDir;
    final progress = ValueNotifier<double>(0);
    if (!mounted) return;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('正在迁移'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, value, child) => LinearProgressIndicator(value: value <= 0 ? null : value),
        ),
      ),
    ));
    await _copyDirectory(Directory(oldPath), Directory(selected), progress);
    if (isCache) {
      _settings.cacheDir = selected;
    } else {
      _settings.saveDir = selected;
    }
    await _saveSettings();
    progress.value = 1;
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {});
    }
  }

  Future<void> _clearCache() async {
    final dir = Directory(_settings.cacheDir);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    _setStatus('缓存已清除');
  }

  Future<void> _openReceivedFiles() async {
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ReceivedFilesPage(host: this)));
  }

  Future<List<File>> _listReceivedFiles() async {
    final dir = Directory(_settings.saveDir);
    if (!await dir.exists()) return const <File>[];
    final files = await dir.list(recursive: false).where((entity) => entity is File).cast<File>().toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  Future<void> _copyDirectory(Directory source, Directory target, ValueNotifier<double> progress) async {
    if (!await source.exists()) {
      await target.create(recursive: true);
      progress.value = 1;
      return;
    }
    final files = await source.list(recursive: true).where((entity) => entity is File).cast<File>().toList();
    await target.create(recursive: true);
    for (var i = 0; i < files.length; i++) {
      final relative = files[i].path.substring(source.path.length).replaceFirst(RegExp(r'^[\\/]'), '');
      final out = File('${target.path}${Platform.pathSeparator}$relative');
      await out.parent.create(recursive: true);
      await files[i].copy(out.path);
      progress.value = files.isEmpty ? 1 : (i + 1) / files.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final isWide = MediaQuery.sizeOf(context).width >= 760;
    if (isWide) {
      return Scaffold(
        body: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFEFF4FF), Color(0xFFF8FAFC)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Row(
              children: [
                SizedBox(width: 320, child: _buildSidebar()),
                Expanded(child: _buildChatPanel(true)),
              ],
            ),
          ),
        ),
      );
    }
    return _buildMobileShell();
  }

  Widget _buildMobileShell() {
    return Scaffold(
      body: SafeArea(child: _mobileTabIndex == 0 ? _buildMobileSessionList() : _buildMobileSettings()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _mobileTabIndex,
        onDestinationSelected: (index) => setState(() => _mobileTabIndex = index),
        destinations: [
          NavigationDestination(
            icon: _navIcon(Icons.chat_bubble_outline_rounded, _totalUnread),
            selectedIcon: _navIcon(Icons.chat_bubble_rounded, _totalUnread, selected: true),
            label: '消息',
          ),
          const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '设置'),
        ],
      ),
    );
  }

  Widget _navIcon(IconData icon, int count, {bool selected = false}) {
    final base = Icon(icon, color: selected ? null : Colors.black54);
    if (count <= 0) return base;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        Positioned(
          right: -8,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 18),
            decoration: BoxDecoration(color: const Color(0xFFFF4D4F), borderRadius: BorderRadius.circular(10)),
            child: Text(count > 99 ? '99+' : '$count', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  int get _totalUnread => _unread.values.fold(0, (a, b) => a + b);

  Widget _buildMobileSessionList() {
    final peers = _peers.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    final entries = <_SessionEntry>[
      _SessionEntry(id: groupId, title: '局域网群聊', subtitle: '所有局域网设备群聊', deviceType: 'group'),
      for (final peer in peers) _SessionEntry(id: peer.id, title: peer.name, subtitle: peer.address.address, deviceType: peer.deviceType),
    ];
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Expanded(child: Text(appTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              IconButton(icon: const Icon(Icons.radar_rounded), onPressed: _restartDiscovery),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final unread = _unread[entry.id] ?? 0;
              final lastMessage = _messagesForSession(entry.id).lastOrNull;
              final preview = _previewOf(lastMessage);
              return ListTile(
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF6C8CFF),
                      child: Icon(_iconOf(entry.deviceType), color: Colors.white),
                    ),
                    if (unread > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: const Color(0xFFFF4D4F), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 1.5)),
                          constraints: const BoxConstraints(minWidth: 18),
                          child: Text(unread > 99 ? '99+' : '$unread', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                      ),
                  ],
                ),
                title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54)),
                onTap: () => _openMobileChat(entry.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Iterable<WireMessage> _messagesForSession(String sessionId) {
    return _messages.where((m) {
      if (sessionId == groupId) return m.targetId == groupId;
      return (m.senderId == sessionId && m.targetId == _deviceId) || (m.senderId == _deviceId && m.targetId == sessionId);
    });
  }

  String _previewOf(WireMessage? message) {
    if (message == null) return '点击进入聊天';
    if (message.type == 'image') return '[图片]';
    if (message.type == 'file' || message.type == 'file_request') return '[文件] ${message.fileName ?? ''}';
    return message.text ?? '';
  }

  IconData _iconOf(String type) => type == 'pc' ? Icons.desktop_windows_rounded : type == 'group' ? Icons.groups_rounded : Icons.smartphone_rounded;

  Future<void> _openMobileChat(String id) async {
    _resetChatScrollPosition();
    setState(() {
      _selectedTargetId = id;
      _unread.remove(id);
    });
    _scheduleScrollToBottom(stabilize: true);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _MobileChatPage(host: this)));
  }

  Widget _buildMobileSettings() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        ListTile(leading: const Icon(Icons.account_circle_rounded), title: const Text('我的名字'), subtitle: Text(_deviceName), onTap: _openSettings),
        ListTile(leading: const Icon(Icons.notifications_active_outlined), title: const Text('消息提醒'), subtitle: Text(_settings.notificationsEnabled ? '已开启' : '已关闭'), onTap: _openSettings),
        ListTile(leading: const Icon(Icons.folder_open_rounded), title: const Text('管理接收的文件'), subtitle: const Text('查看/删除文件'), onTap: _openReceivedFiles),
        ListTile(leading: const Icon(Icons.cleaning_services_rounded), title: const Text('清除缓存'), subtitle: Text(_settings.cacheDir), onTap: () => unawaited(_clearCache())),
      ],
    );
  }

  Widget _buildSidebar() {
    final peers = _peers.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF172033), borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18)]),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                _avatar(_deviceType, selected: true),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_deviceName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)), Text('${peers.length} 台在线设备', style: const TextStyle(color: Colors.white60))])),
              ],
            ),
          ),
          _sessionTile(id: groupId, title: '局域网群聊', subtitle: '默认群聊，P2P 群发', icon: Icons.groups_rounded, type: 'group'),
          const Padding(padding: EdgeInsets.fromLTRB(18, 20, 18, 8), child: Align(alignment: Alignment.centerLeft, child: Text('在线设备', style: TextStyle(color: Colors.white54, fontSize: 12)))),
          Expanded(
            child: peers.isEmpty
                ? const Center(child: Text('等待设备发现', style: TextStyle(color: Colors.white54)))
                : ListView(children: [for (final peer in peers) _sessionTile(id: peer.id, title: peer.name, subtitle: peer.address.address, icon: Icons.person, type: peer.deviceType)]),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String type, {bool selected = false}) {
    final icon = type == 'pc' ? Icons.desktop_windows_rounded : type == 'group' ? Icons.groups_rounded : Icons.smartphone_rounded;
    return CircleAvatar(backgroundColor: selected ? const Color(0xFF6C8CFF) : Colors.white12, child: Icon(icon, color: Colors.white));
  }

  Widget _sessionTile({required String id, required String title, required String subtitle, required IconData icon, required String type}) {
    final selected = _selectedTargetId == id;
    final unread = _unread[id] ?? 0;
    final tile = Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent, borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            _avatar(type, selected: selected),
            if (unread > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFFF4D4F), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF172033), width: 1.5)),
                  constraints: const BoxConstraints(minWidth: 18),
                  child: Text(unread > 99 ? '99+' : '$unread', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12), overflow: TextOverflow.ellipsis),
        onTap: () {
          _resetChatScrollPosition();
          setState(() {
            _selectedTargetId = id;
            _unread.remove(id);
          });
          _scheduleScrollToBottom(stabilize: true);
          if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.pop(context);
        },
      ),
    );
    if (!Platform.isWindows || id == groupId) return tile;
    return DropTarget(
      onDragDone: (details) {
        if (details.files.isNotEmpty) unawaited(_sendDroppedFile(id, details.files.first.path));
      },
      child: tile,
    );
  }

  Widget _buildChatPanel(bool isWide) {
    final title = _selectedTargetId == groupId ? '局域网群聊' : (_peers[_selectedTargetId]?.name ?? '私聊');
    final messages = _visibleMessages;
    final panel = Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 0 : 12, 12, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ColoredBox(
          color: Colors.white,
          child: Column(
            children: [
              Container(
                height: 72,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE8EDF5)))),
                child: Row(children: [
                  Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), Text(_status, style: const TextStyle(fontSize: 12, color: Colors.black54), overflow: TextOverflow.ellipsis)])),
                  IconButton(onPressed: _restartDiscovery, icon: const Icon(Icons.radar_rounded)),
                  IconButton(onPressed: _openSettings, icon: const Icon(Icons.settings_rounded)),
                ]),
              ),
              Expanded(
                child: messages.isEmpty
                    ? const Center(child: Text('发送第一条消息，局域网内设备会自动互通'))
                    : ListView.builder(
                        controller: _chatScrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(18),
                        itemCount: messages.length,
                        itemBuilder: (context, index) => _messageBubble(messages[messages.length - 1 - index]),
                      ),
              ),
              _buildComposer(),
            ],
          ),
        ),
      ),
    );
    if (!Platform.isWindows) return panel;
    return DropTarget(
      onDragDone: (details) {
        if (details.files.isNotEmpty) unawaited(_sendDroppedFile(_selectedTargetId, details.files.first.path));
      },
      child: panel,
    );
  }

  Widget _messageBubble(WireMessage message) {
    final mine = message.senderId == _deviceId;
    final bubbleColor = mine ? const Color(0xFFDCF8C6) : const Color(0xFFF3F6FB);
    final bubble = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(mine ? '我' : message.senderName, style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          DecoratedBox(
            decoration: BoxDecoration(color: bubbleColor, borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(mine ? 18 : 4), bottomRight: Radius.circular(mine ? 4 : 18))),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: message.type == 'image' && message.bytes != null
                  ? GestureDetector(
                      onTap: () => unawaited(_openImageMessage(message)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          message.bytes!,
                          key: ValueKey(message.id),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    )
                  : message.type == 'file' || message.type == 'file_request'
                      ? _fileCard(message)
                  : _buildTextSpan(message.text ?? '', mine),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Padding(
        padding: EdgeInsets.only(left: mine ? 54 : 0, right: mine ? 0 : 54),
        child: Row(
          mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: mine
              ? [Flexible(child: bubble), const SizedBox(width: 10), _messageAvatar(message)]
              : [_messageAvatar(message), const SizedBox(width: 10), Flexible(child: bubble)],
        ),
      ),
    );
  }

  Widget _messageAvatar(WireMessage message) {
    final mine = message.senderId == _deviceId;
    final name = mine ? _deviceName : message.senderName;
    final type = mine ? _deviceType : (_peers[message.senderId]?.deviceType ?? 'phone');
    return SizedBox(
      width: 40,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _avatarColorFor(message.senderId),
            child: Text(_avatarLetter(name), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
          ),
          Positioned(
            right: -2,
            bottom: 0,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE3E8F2))),
              child: Icon(_iconOf(type), size: 12, color: const Color(0xFF4D5D78)),
            ),
          ),
        ],
      ),
    );
  }

  Color _avatarColorFor(String id) {
    const colors = [
      Color(0xFF4F7BFF),
      Color(0xFF00A6A6),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFF8B5CF6),
      Color(0xFF10B981),
      Color(0xFFEC4899),
      Color(0xFF64748B),
    ];
    var hash = 0;
    for (final codeUnit in id.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return colors[hash % colors.length];
  }

  String _avatarLetter(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }

  Widget _fileCard(WireMessage message) {
    final mine = message.senderId == _deviceId;
    final path = message.localPath ?? _receivedFiles[message.id];
    final status = message.transferStatus ?? (message.type == 'file' ? 'completed' : 'pending');
    final rejected = status == 'rejected' || status == 'canceled';
    final pending = message.type == 'file_request' && status == 'pending';
    final accepted = status == 'accepted';
    final completed = status == 'completed';
    String statusText;
    if (pending) {
      statusText = mine ? '等待对方接收' : '等待你确认';
    } else if (accepted) {
      statusText = mine ? '对方已同意，正在发送…' : '已接收，正在下载…';
    } else if (status == 'canceled') {
      statusText = mine ? '已取消或对方离线' : '发送方已取消';
    } else if (status == 'rejected') {
      statusText = mine ? '对方已拒绝' : '已拒绝接收';
    } else {
      statusText = _formatBytes(message.fileSize ?? 0);
    }
    return SizedBox(
      width: 300,
      child: InkWell(
        onTap: completed && path != null ? () => _openPath(path) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: rejected ? const Color(0xFFFFE1E1) : null,
                    child: Icon(rejected ? Icons.block_rounded : Icons.insert_drive_file_rounded, color: rejected ? const Color(0xFFD93025) : null),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message.fileName ?? '文件', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${_formatBytes(message.fileSize ?? 0)} · $statusText', style: TextStyle(fontSize: 12, color: rejected ? const Color(0xFFD93025) : Colors.black54)),
                      ],
                    ),
                  ),
                ],
              ),
              if (pending && !mine) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, children: [
                  OutlinedButton(onPressed: () => _rejectIncomingFile(message), child: const Text('拒绝')),
                  FilledButton(onPressed: () => _acceptIncomingFile(message), child: const Text('接收')),
                ]),
              ),
              if (pending && mine) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(onPressed: () => _cancelOutgoingFile(message), child: const Text('取消发送')),
              ),
              if (completed && path != null && Platform.isWindows) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, children: [
                  TextButton(onPressed: () => _openPath(path), child: const Text('打开')),
                  TextButton(onPressed: () => _openContainingFolder(path), child: const Text('打开文件夹')),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPath(String path) async {
    try {
      if (Platform.isAndroid) {
        await _androidFileChannel.invokeMethod<bool>('open', {'path': path});
        return;
      }
      final result = await OpenFilex.open(path);
      if (result.type.name != 'done') _setStatus('打开文件失败：${result.message}');
    } on PlatformException catch (error) {
      _setStatus('打开文件失败：${error.message ?? error.code}');
    } catch (error) {
      _setStatus('打开文件失败：$error');
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _setStatus('无法打开链接：$url');
      }
    } catch (error) {
      _setStatus('打开链接失败：$error');
    }
  }

  Widget _buildTextSpan(String text, bool mine) {
    final pattern = RegExp(r'(https?://\S+|www\.\S+)', caseSensitive: false);
    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      final raw = match.group(0)!;
      final url = raw.startsWith('http') ? raw : 'https://$raw';
      spans.add(TextSpan(
        text: raw,
        style: TextStyle(color: mine ? const Color(0xFF1B7BD0) : const Color(0xFF1B7BD0), decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () => unawaited(_openUrl(url)),
      ));
      index = match.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return Text.rich(
      TextSpan(style: const TextStyle(fontSize: 15, height: 1.35, color: Colors.black87), children: spans),
    );
  }

  Future<void> _openImageMessage(WireMessage message) async {
    final bytes = message.bytes;
    if (bytes == null) return;
    try {
      final dir = Directory(_settings.cacheDir);
      await dir.create(recursive: true);
      final ext = (message.fileName != null && message.fileName!.contains('.')) ? message.fileName!.split('.').last.toLowerCase() : 'jpg';
      final path = '${dir.path}${Platform.pathSeparator}lanchat_image_${message.id}.$ext';
      final file = File(path);
      if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
      await _openPath(path);
    } catch (error) {
      _setStatus('打开图片失败：$error');
    }
  }

  Future<void> _openContainingFolder(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', ['/select,', path]);
      } else if (Platform.isAndroid) {
        _setStatus('安卓端暂不支持打开文件夹');
      }
    } catch (error) {
      _setStatus('打开文件夹失败：$error');
    }
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE8EDF5)))),
      child: Row(
        children: [
          IconButton(onPressed: _sendImage, icon: const Icon(Icons.image_outlined)),
          if (_selectedTargetId != groupId) IconButton(onPressed: _sendFileRequest, icon: const Icon(Icons.attach_file_rounded)),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (!Platform.isWindows || !_settings.enterToSend || event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
                  _sendText();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(hintText: _selectedTargetId == groupId ? '发到默认群聊' : '发起私聊', filled: true, fillColor: const Color(0xFFF5F7FB), border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none)),
                onSubmitted: (_) {
                  if (!Platform.isWindows || !_settings.enterToSend) _sendText();
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _sendText, icon: const Icon(Icons.send_rounded), label: const Text('发送')),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _MobileChatPage extends StatefulWidget {
  const _MobileChatPage({required this.host});
  final _ChatHomePageState host;

  @override
  State<_MobileChatPage> createState() => _MobileChatPageState();
}

class _MobileChatPageState extends State<_MobileChatPage> {
  late final VoidCallback _hostListener;

  @override
  void initState() {
    super.initState();
    _hostListener = () {
      if (mounted) setState(() {});
    };
    widget.host._mobileChatListeners.add(_hostListener);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.host._scheduleScrollToBottom());
  }

  @override
  void dispose() {
    widget.host._mobileChatListeners.remove(_hostListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.host;
    final title = state._selectedTargetId == groupId ? '局域网群聊' : (state._peers[state._selectedTargetId]?.name ?? '私聊');
    final messages = state._visibleMessages;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(18),
          child: Padding(
            padding: const EdgeInsets.only(left: 56, bottom: 8),
            child: Align(alignment: Alignment.centerLeft, child: Text(state._status, style: const TextStyle(fontSize: 12, color: Colors.black54), overflow: TextOverflow.ellipsis)),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? const Center(child: Text('发送第一条消息'))
                  : ListView.builder(
                      controller: state._chatScrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(18),
                      itemCount: messages.length,
                      itemBuilder: (context, index) => state._messageBubble(messages[messages.length - 1 - index]),
                    ),
            ),
            state._buildComposer(),
          ],
        ),
      ),
    );
  }
}

class _ReceivedFilesPage extends StatefulWidget {
  const _ReceivedFilesPage({required this.host});
  final _ChatHomePageState host;

  @override
  State<_ReceivedFilesPage> createState() => _ReceivedFilesPageState();
}

class _ReceivedFilesPageState extends State<_ReceivedFilesPage> {
  List<File> _files = [];
  final Set<String> _selected = {};
  bool _selectMode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final files = await widget.host._listReceivedFiles();
    if (!mounted) return;
    setState(() {
      _files = files;
      _selected.removeWhere((path) => !files.any((file) => file.path == path));
      _loading = false;
    });
  }

  Future<void> _confirmDelete() async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除已选文件'),
        content: Text('确认删除选中的 ${_selected.length} 个文件？删除后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton.tonal(style: FilledButton.styleFrom(foregroundColor: const Color(0xFFD93025)), onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    for (final path in _selected.toList()) {
      try {
        await File(path).delete();
      } catch (_) {}
      widget.host._receivedFiles.removeWhere((_, p) => p == path);
    }
    if (widget.host.mounted) widget.host.setState(() {});
    _selected.clear();
    _selectMode = false;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '已选 ${_selected.length} 项' : '接收的文件'),
        leading: _selectMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() {
                  _selectMode = false;
                  _selected.clear();
                }))
            : null,
        actions: [
          if (!_selectMode && _files.isNotEmpty)
            TextButton(onPressed: () => setState(() => _selectMode = true), child: const Text('选择')),
          if (_selectMode)
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == _files.length) {
                  _selected.clear();
                } else {
                  _selected
                    ..clear()
                    ..addAll(_files.map((f) => f.path));
                }
              }),
              child: Text(_selected.length == _files.length ? '取消全选' : '全选'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text('暂无接收的文件'))
              : ListView.separated(
                  itemCount: _files.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    final name = file.path.split(RegExp(r'[\\/]')).last;
                    final selected = _selected.contains(file.path);
                    return ListTile(
                      leading: _selectMode
                          ? Checkbox(
                              value: selected,
                              onChanged: (value) => setState(() {
                                if (value == true) {
                                  _selected.add(file.path);
                                } else {
                                  _selected.remove(file.path);
                                }
                              }),
                            )
                          : const Icon(Icons.insert_drive_file_rounded),
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: FutureBuilder<int>(
                        future: file.length(),
                        builder: (context, snapshot) => Text(widget.host._formatBytes(snapshot.data ?? 0)),
                      ),
                      onTap: () {
                        if (_selectMode) {
                          setState(() {
                            if (selected) {
                              _selected.remove(file.path);
                            } else {
                              _selected.add(file.path);
                            }
                          });
                        } else {
                          widget.host._openPath(file.path);
                        }
                      },
                      onLongPress: () => setState(() {
                        _selectMode = true;
                        _selected.add(file.path);
                      }),
                    );
                  },
                ),
      bottomNavigationBar: _selectMode && _selected.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD93025), minimumSize: const Size.fromHeight(48)),
                  onPressed: _confirmDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text('删除已选 (${_selected.length})'),
                ),
              ),
            )
          : null,
    );
  }
}
