# Hexdeep 音视频采集 Flutter Demo

> 这是一个基于 **Flutter** 和 **WebRTC** 的音视频采集示例应用，支持摄像头视频采集、音频采集、视频角度调整、镜像显示、前后摄像头切换以及后台悬浮窗显示。
**连接webrtc之前，必须调用容器:设置推流音视频类型和地址(/and_api/set_stream)接口，设置stream_type=1，否则连接出错**
---

## ✨ 功能特点

- 🎥 **视频采集**：支持前置和后置摄像头
- 🎤 **音频采集**：支持麦克风采集音频
- 📡 **WebRTC 推流**：通过自定义 ICE 和 SDP 与服务器进行 WebRTC 连接
- 🔄 **视频旋转和镜像**：可选择视频旋转角度（0°/90°/180°/270°）和镜像显示
- 📱 **前后摄像头切换**：支持动态切换前置/后置摄像头
- 🪟 **后台悬浮窗**：App 切到后台时显示小悬浮窗
- 💾 **本地缓存服务器 IP**：通过 `SharedPreferences` 保存和加载服务器 IP
- 🔐 **权限管理**：自动申请摄像头、麦克风和悬浮窗权限

---

## 📦 依赖包

项目使用了以下 Flutter 包：

| 包名 | 功能 |
|------|------|
| `flutter_webrtc` | WebRTC 功能 |
| `permission_handler` | 管理摄像头和麦克风权限 |
| `shared_preferences` | 保存本地服务器 IP |
| `http` | HTTP 请求，用于与服务器通信 |
| `flutter_overlay_window_plus` | 后台悬浮窗显示 |

---

## 🔐 权限说明

应用需要以下权限：

| 权限 | 用途 |
|------|------|
| `CAMERA` | 采集视频 |
| `RECORD_AUDIO` | 采集音频 |
| `SYSTEM_ALERT_WINDOW` | App 切到后台时显示小悬浮窗 |

**AndroidManifest.xml 配置：**
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
