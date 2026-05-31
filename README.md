# LanChat

[中文](#中文) | [English](#english)

## 中文

LanChat 是一个无服务器局域网聊天软件，支持 Windows 与 Android 双端互通。

打开两台设备进同一个 Wi-Fi 即可自动发现彼此，支持群聊、私聊、文本、图片、文件传输，全部点对点 P2P，不经过任何服务器。

下载二进制包请见 [Releases](https://github.com/zyqg/LanChat/releases)。

### 功能

- 默认局域网群聊，自动发现同一网段所有 LanChat 设备
- 私聊、未读小红点、消息预览
- 文本消息中的链接自动识别，点击调起浏览器
- 图片消息，点击直接调系统相册或可用看图应用打开
- 文件传输（仅私聊）
- 流式传输，文件大小没有 16 MB 之类的限制
- 接收方需要在聊天气泡里点 接收 / 拒绝
- 拒绝、超时、对方离线都会显示在双方聊天里
- Windows 可以直接把文件拖到聊天框或对方头像发送
- Android 接收完成后点击文件直接调系统打开（APK 走安装、图片走相册等）
- 聊天气泡显示发送者头像，群聊中更容易区分不同设备
- Windows 体验
- 回车发送 / Shift+Enter 换行
- 消息提醒
- 保存与缓存目录可更换
- 关闭时询问完全关闭还是隐藏
- 右下角托盘恢复 / 退出
- 单实例运行，第二次打开会激活已有窗口
- Android 体验
- 类 QQ/微信的会话列表 + 底部 Tab
- 未读红点
- 接收文件管理，多选、统一删除、二次确认
- 一键清除缓存

### 系统要求

- Windows 10 / 11（x64）
- Android 8.0 及以上
- 双方处于同一局域网，未被路由器“AP 隔离”拦截

如果发现不到对方，请确认两台设备连的是同一个 Wi-Fi，并放行 LanChat 的网络访问权限。Windows 防火墙弹窗时点“允许”。

### 使用

Windows：

1. 下载 `LanChat-Windows.zip`
2. 解压到任意目录
3. 双击 `LanChat.exe` 运行
4. 第一次运行 Windows 防火墙会询问网络权限，勾选并允许

Android：

1. 下载 `LanChat-Android.apk`
2. 在手机里打开安装，授权安装来自未知来源
3. 打开应用后授予网络权限即可

### 技术栈

- Flutter 一套代码同时构建 Windows 与 Android
- UDP 广播做设备发现
- TCP 做消息与文件流传输
- 端口
- `45678` UDP 设备发现
- `45679` TCP 消息
- `45681` TCP 文件流
- `45680` Windows 单实例

### 开发与构建

需要 Flutter SDK，并已配置 Android SDK 与 Visual Studio Build Tools（Windows 端）。

```bash
flutter pub get
flutter analyze
flutter test

flutter build windows
flutter build apk --release
```

### License

MIT

## English

LanChat is a serverless LAN chat app for Windows and Android.

Put two devices on the same Wi-Fi network and they can discover each other automatically. LanChat supports group chat, private chat, text, images, and file transfer. All communication is peer-to-peer on the local network, with no server required.

Download prebuilt packages from [Releases](https://github.com/zyqg/LanChat/releases).

### Features

- Default LAN group chat with automatic device discovery
- Private chats, unread badges, and message previews
- Automatic link detection in text messages, opened with the system browser
- Image messages, opened with the system image viewer or gallery
- File transfer in private chats only
- Stream-based file transfer without a small 16 MB-style payload limit
- Receiver can accept or reject files directly inside the chat bubble
- Rejected, timed out, or offline transfers are shown in both chats
- Windows drag-and-drop sending to the chat area or a peer avatar
- Android opens received files with the system app picker
- Sender avatars in chat bubbles, making group chats easier to read
- Windows features
- Enter to send, Shift+Enter for a new line
- Message notifications
- Configurable save/cache folders
- Close confirmation with tray background mode
- System tray restore and exit menu
- Single-instance behavior
- Android features
- Mobile session list with bottom navigation
- Unread badges
- Received file manager with multi-select delete
- One-tap cache cleanup

### Requirements

- Windows 10 / 11 (x64)
- Android 8.0 or later
- Devices must be on the same LAN, and the router must not block peer-to-peer traffic with AP isolation

If devices cannot find each other, make sure they are connected to the same Wi-Fi network and allow LanChat through the firewall. On Windows, choose Allow when the firewall prompt appears.

### Usage

Windows:

1. Download `LanChat-Windows.zip`
2. Extract it anywhere
3. Run `LanChat.exe`
4. Allow network access if Windows Firewall asks

Android:

1. Download `LanChat-Android.apk`
2. Open it on your phone and allow installation from unknown sources if prompted
3. Launch LanChat and allow network access

### Tech Stack

- Flutter, one codebase for Windows and Android
- UDP broadcast for device discovery
- TCP for messages and file streams
- Ports
- `45678` UDP device discovery
- `45679` TCP messages
- `45681` TCP file streams
- `45680` Windows single-instance activation

### Development

Flutter SDK is required. Android SDK and Visual Studio Build Tools are required for Android and Windows builds.

```bash
flutter pub get
flutter analyze
flutter test

flutter build windows
flutter build apk --release
```

### License

MIT
