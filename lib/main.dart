import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window_plus/flutter_overlay_window_plus.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hexdeep音视频采集',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const WebRTCDemoPage(),
    );
  }
}

class WebRTCDemoPage extends StatefulWidget {
  const WebRTCDemoPage({super.key});
  @override
  State<WebRTCDemoPage> createState() => _WebRTCDemoPageState();
}

class _WebRTCDemoPageState extends State<WebRTCDemoPage>  with WidgetsBindingObserver {
  // ---------------- 视频相关 ----------------
  final _localCameraRenderer = RTCVideoRenderer();
  RTCPeerConnection? _cameraPc;
  MediaStream? _localCameraStream;
  bool _useFrontCamera = true;
  bool _cameraConnected = false;
  bool _disableHost = false;
  String _cameraStatus = "未连接";
  final _serverIpController = TextEditingController();
  static const _prefsKeyServerIp = "server_ip";

  // 视频角度选择
  int _selectedCameraRotation = 90;
  bool _videoMirror = true;
  MediaStream? _localAudioStream;


  @override
  void initState() {
    super.initState();
    _localCameraRenderer.initialize();
    _loadServerIp();
    WidgetsBinding.instance.addObserver(this);

    FlutterOverlayWindowPlus.isPermissionGranted().then((v){
      if(!v){
        FlutterOverlayWindowPlus.requestPermission();
      }
    });

    Permission.camera.request().then((grant){
      Permission.microphone.request();
    });
  }

  @override
  void dispose() {
    _localCameraRenderer.dispose();
    _serverIpController.dispose();
    _cameraPc?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 监听生命周期变化
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.inactive:
        print("App处于非活动状态（比如来电或锁屏）");
        break;
      case AppLifecycleState.paused:
        FlutterOverlayWindowPlus.isPermissionGranted().then((v){
          if(!v){
            FlutterOverlayWindowPlus.requestPermission().then((grant){
              if(grant)_showSmallOverlay();
            });
          }else{
            _showSmallOverlay();
          }
        });
        print("App切到后台");
        break;
      case AppLifecycleState.resumed:
        FlutterOverlayWindowPlus.closeOverlay();
        print("App回到前台");
        break;
      case AppLifecycleState.detached:
        print("App被销毁");
        break;
      case AppLifecycleState.hidden:
    }
  }

  Future<void> _showSmallOverlay() async {
    await FlutterOverlayWindowPlus.showOverlay(
      height: 100,
      width: 150,
      alignment: OverlayAlignment.topRight,
      flag: OverlayFlag.defaultFlag,
      overlayTitle: "Small Overlay",
      overlayContent: "Small overlay in top-right",
      enableDrag: true,
      positionGravity: PositionGravity.none,
    );
  }

  // ---------- 本地缓存读取 ----------
  Future<void> _loadServerIp() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString(_prefsKeyServerIp) ?? "192.168.31.54:2000";
    _serverIpController.text = ip;
  }

  // ---------- 本地缓存保存 ----------
  Future<void> _saveServerIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyServerIp, ip);
  }

  // ---------- 获取视频流 ----------
  Future<void> _getCameraStream() async {
    if (_localCameraStream != null) return;
    final constraints = {
      'audio': false,
      'video': {
        'facingMode': _useFrontCamera ? 'user' : 'environment',
        'width': 1920,
        'height': 1080,
        'frameRate': 60,
      }
    };
    _localCameraStream = await navigator.mediaDevices.getUserMedia(constraints);
    _localCameraRenderer.srcObject = _localCameraStream;
  }

  // ---------- 获取音频流 ----------
  Future<void> _getAudioStream() async {
    if (_localAudioStream != null) return;
    final constraints = {
      'audio': true,
      'video': false,
    };
    _localAudioStream = await navigator.mediaDevices.getUserMedia(constraints);
  }

  String filterSrflx(String sdp) {
    final lines = sdp.split('\r\n');
    final filtered = lines.where((line) {
      if (!line.startsWith('a=candidate:')) return true;
      return !(line.contains('typ srflx') || (_disableHost && line.contains('typ host')));
    }).toList();
    return filtered.join('\r\n');
  }

  Future<void> _sendOfferAndSetRemote(String serverIp, String sdp, Map<String, dynamic> config) async {
    setState(() => _cameraStatus = "ICE 收集完成");

    print("video offer is:\n$sdp");
    final fixSdp = filterSrflx(sdp);

    final requestPayload = {
      "ice_servers": config['iceServers'],
      "offer": {"type": "offer", "sdp": fixSdp},
      "video_rotation": _selectedCameraRotation,
      "video_mirror": _videoMirror,
    };

    try {
      final resp = await http.post(
        Uri.parse("http://$serverIp/and_api/webrtc_start"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(requestPayload),
      );

      if (resp.statusCode != 200) {
        _showError("请求失败: ${resp.body}");
        return;
      }

      final data = jsonDecode(resp.body);
      if (data["code"] != 200) {
        _showError("服务器返回错误: ${data["err"]}");
        return;
      }

      final answer = RTCSessionDescription(
        data["data"]["sdp"],
        "answer",
      );
      print("video answer is:\n${answer.sdp}");
      await _cameraPc!.setRemoteDescription(answer);

      setState(() => _cameraConnected = true);
    } catch (e) {
      _showError("连接失败: $e");
    }
  }

  // ---------- 视频 WebRTC  ----------
  Future<void> _startCameraWebRTC() async {
    final cameraGranted = await Permission.camera.request();
    if (!cameraGranted.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("摄像头权限未授权")));
      return;
    }

    final microphoneGranted = await Permission.microphone.request();
    if (!microphoneGranted.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("摄像头权限未授权")));
      return;
    }

    bool hostIce = _disableHost?true:false;
    bool relayIce = false;
    final serverIp = _serverIpController.text.trim();
    if (serverIp.isEmpty) {
      _showError("请输入服务器 IP");
      return;
    }

    await _saveServerIp(serverIp);
    setState(() => _cameraStatus = "连接中...");

    await _getCameraStream();

    await _getAudioStream();

    final config = {
      'iceServers': [
        {'urls': ["stun:43.138.176.9:3480"], 'username': "root", 'credential': "wbs007007"},
        {'urls': ["turn:43.138.176.9:3480"], 'username': "root", 'credential': "wbs007007"}
      ],
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': _disableHost?'relay':'all',
    };

    _cameraPc = await createPeerConnection(config);
    if (_localCameraStream != null) {
      final videoTrack = _localCameraStream!.getVideoTracks().first;
      _cameraPc?.addTransceiver(
        track: videoTrack,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly),
      );
    }

    if(_localAudioStream != null){
      final audioTrack = _localAudioStream!.getAudioTracks().first;
      _cameraPc?.addTransceiver(
        track: audioTrack,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly),
      );
    }
    

    _cameraPc?.onIceConnectionState = (state) {
      setState(() => _cameraStatus = "视频 ICE 状态: $state");
    };

    _cameraPc?.onIceCandidate = (candidate) async {
      if (hostIce && relayIce) return;

      if (candidate.candidate!.contains("typ host")) {
        final regex = RegExp(r'(\d{1,3}\.){3}\d{1,3}');
        final match = regex.firstMatch(candidate.candidate!);
        if (match != null) {
          final ip = match.group(0);
          if (ip != "127.0.0.1") hostIce = true;
        }
      } else if (candidate.candidate!.contains("typ relay")) {
        relayIce = true;
      }

      if (hostIce && relayIce) {
        final sdp = await _cameraPc?.getLocalDescription();
        if (sdp != null) {
          await _sendOfferAndSetRemote(serverIp, sdp.sdp!, config);
        }
      }
    };

    final offer = await _cameraPc!.createOffer({
      "offerToReceiveAudio": false, // 不接收音频
      "offerToReceiveVideo": false, // 不接收视频
    });
    await _cameraPc!.setLocalDescription(offer);
    setState(() => _cameraStatus = "正在收集视频 ICE...");
  }

  Future<void> _stopCameraWebRTC() async {
    final serverIp = _serverIpController.text.trim();
    try {
      await http.get(Uri.parse("http://$serverIp/and_api/webrtc_stop"));
    } catch (_) {}
    await _localCameraStream?.dispose();
    _localCameraStream = null;
    await _cameraPc?.close();
    _cameraPc = null;
    setState(() {
      _cameraStatus = "视频已断开";
      _cameraConnected = false;
    });
  }

  Future<void> _switchCamera() async {
    await _stopCameraWebRTC();
    _useFrontCamera = !_useFrontCamera;
    await _startCameraWebRTC();
  }

  Future<void> _updateCameraRotation() async {
    if (!_cameraConnected) return;
    final serverIp = _serverIpController.text.trim();
    if (serverIp.isEmpty) {
      _showError("请输入服务器 IP");
      return;
    }

    try {
      final url = Uri.parse(
          "http://$serverIp/and_api/webrtc_update_video_rotation?video_rotation=$_selectedCameraRotation&video_mirror=$_videoMirror");
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data["code"] == 200) {
          setState(() => _cameraStatus = "角度已更新: $_selectedCameraRotation°");
        } else {
          _showError("更新失败: ${data["err"]}");
        }
      } else {
        _showError("更新失败: ${resp.body}");
      }
    } catch (e) {
      _showError("请求错误: $e");
    }
  }

  Widget _buildRotationOption(int value) {
    return Expanded(
      child: RadioListTile<int>(
        dense: true,
        title: Text("$value°"),
        value: value,
        groupValue: _selectedCameraRotation,
        onChanged: (val) async {
          if (val != null) {
            setState(() {
              _selectedCameraRotation = val;
            });
            await _updateCameraRotation();
          }
        },
      ),
    );
  }

  void _showError(String msg) {
    setState(() => _cameraStatus = "错误: $msg");
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("WebRTC H.264 & Audio Demo (Flutter)")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _serverIpController,
              decoration: const InputDecoration(labelText: "远端服务器 IP"),
            ),

            // 视频角度选择
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("视频角度选择"),
                Row(
                  children: [
                    _buildRotationOption(0),
                    _buildRotationOption(90),
                  ],
                ),
                Row(
                  children: [
                    _buildRotationOption(180),
                    _buildRotationOption(270),
                  ],
                ),
              ],
            ),

            // 视频镜像 & 禁用直连
            Row(
              children: [
                const Text("视频镜像"),
                Switch(
                  value: _videoMirror,
                  onChanged: (val) {
                    setState(() => _videoMirror = val);
                    _updateCameraRotation();
                  },
                ),
                Expanded(child: const SizedBox()),
                const Text("禁用直连"),
                Switch(
                  value: _disableHost,
                  onChanged: (val) {
                    setState(() => _disableHost = val);
                  },
                ),
              ],
            ),

            const SizedBox(height: 5),
            // 视频和音频状态显示
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("视频状态: $_cameraStatus"),
              ],
            ),

            const SizedBox(height: 10),
            // 控制按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed:_cameraConnected? null:(){
                      if(!_cameraConnected){
                        _startCameraWebRTC();
                      }
                    },
                    child: const Text("开始连接"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed:_cameraConnected? (){
                      if(_cameraConnected){
                        _stopCameraWebRTC();
                      }
                    }:null,
                    child: const Text("断开连接"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _cameraConnected ? _switchCamera : null,
                    child: Text(_useFrontCamera ? "后置摄像头" : "前置摄像头"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            // 视频显示
            Expanded(
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.black)),
                child: RTCVideoView(
                  _localCameraRenderer,
                  mirror: _useFrontCamera,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
