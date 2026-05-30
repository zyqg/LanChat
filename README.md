# LanChat

无服务器局域网聊天，Windows 与 Android 双端互通。

打开两台设备进同一个 Wi-Fi 即可自动发现彼此，支持群聊、私聊、文本、图片、文件传输，全部点对点 P2P，不经过任何服务器。

下载二进制包请见 [Releases](https://github.com/zyqg/LanChat/releases)。

## 功能

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
- Windows 体验
  - 设置：回车发送 / Shift+Enter 换行、消息提醒、关闭时询问完全关闭还是隐藏、保存与缓存目录可更换
  - 关闭主窗口可隐藏到右下角托盘，单击 / 双击恢复，右键退出
  - 单实例运行，第二次打开会激活已有窗口
  - 新消息系统通知 + 托盘提示
- Android 体验
  - 类 QQ/微信的会话列表 + 底部 Tab，未读红点
  - 设置中可管理接收的文件，多选、统一删除、二次确认
  - 一键清除缓存

## 系统要求

- Windows 10 / 11（x64）
- Android 8.0 及以上
- 双方处于同一局域网，未被路由器“AP 隔离”拦截

如果发现不到对方，请确认两台设备连的是同一个 Wi-Fi，并放行 LanChat 的网络访问权限（Windows 防火墙弹窗时点“允许”）。

## 使用

Windows：

1. 下载 `LanChat-Windows.zip`，解压到任意目录
2. 双击 `LanChat.exe` 运行
3. 第一次运行 Windows 防火墙会询问网络权限，勾选并允许

Android：

1. 下载 `LanChat-Android.apk`
2. 在手机里打开安装，授权安装来自未知来源
3. 打开应用后授予网络权限即可

## 技术栈

- Flutter 一套代码同时构建 Windows 与 Android
- UDP 广播做设备发现，TCP 做消息与文件流传输
- 端口
  - `45678` UDP 设备发现
  - `45679` TCP 消息
  - `45681` TCP 文件流
  - `45680` Windows 单实例

## 开发与构建

需要 Flutter SDK，并已配置 Android SDK 与 Visual Studio Build Tools（Windows 端）。

```bash
flutter pub get
flutter analyze
flutter test

flutter build windows
flutter build apk --release
```

## License

MIT
