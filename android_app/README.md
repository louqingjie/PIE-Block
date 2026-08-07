# PieBlock 遥控 Android APP

利用手机的陀螺仪/加速度计和 ARCore 视觉惯性里程计，给 pie-block 机械臂仿真
发送目标位姿。手机是「空间手柄」：平移手机控制末端 XYZ，旋转手机控制末端 RPY。

## 功能

- **ARCore VIO** 追踪手机空间位置 → 映射为末端 XYZ
- **GAME_ROTATION_VECTOR** 传感器获取手机姿态 → 映射为末端 RPY
- **WebSocket** 通信，30Hz 发送位姿数据
- **二维码扫码**连接（Godot 侧显示 ws:// 地址）
- **超界震动**提醒
- **回中**重置原点

## 构建

1. 安装 [Android Studio](https://developer.android.com/studio)
   （Hedgehog 2023.1.1 或更高）
2. 打开 `android_app/` 目录，等待 Gradle 同步完成
3. 连接 Android 手机（minSdk 24 = Android 7.0，需支持 ARCore）
4. 点击 Run

> **注意**：ARCore 需要手机支持 Google Play Services for AR，首次运行 APP
> 会提示安装。

## 使用

### PC 端（Godot）

1. 打开 pie-block 仿真，进入机械臂逆解页面
2. 烧录 MCU 求解器
3. 点击顶栏「手机传感器」按钮开启 WebSocket 服务端
4. 侧面板显示连接地址（如 `ws://192.168.1.100:19821`）

### 手机端

1. 确保手机和 PC 连同一 WiFi
2. 打开 APP，输入 PC 的 IP 地址（或点「扫码」扫描 Godot 侧显示的地址）
3. 点「连接」
4. 连接后移动手机：
   - **平移手机** → 末端 XYZ 移动（ARCore 追踪）
   - **旋转手机** → 末端 RPY 变化（陀螺仪）
5. 点「回中」重置原点；超界时手机会震动

## 调试

### Godot 侧配置面板

- **位置映射比例**：手机移动 1mm × 比例 = 末端移动量
- **RPY 灵敏度**：手机旋转角度 × 灵敏度 = 末端目标角度
- **坐标轴翻转**：ARCore (Y-up) 到机器人 (Z-up) 的轴映射调整
- **各轴开关**：可单独禁用某轴的手机控制

### 没有手机时测试

```bash
pip install websocket-client
python tools/phone_pose_test.py 127.0.0.1 19821
```

这会模拟一个圆周运动的位姿发送给 Godot。

## 协议

WebSocket JSON 文本帧：

### 手机 → Godot

```json
{"type":"hello","app":"PieBlockRemote","version":1}
{"type":"pose","position":{"x":0,"y":0,"z":0},"rpy":{"roll":0,"pitch":0,"yaw":0},"ts":12345}
{"type":"reset_origin"}
```

### Godot → 手机

```json
{"type":"welcome","server":"pie-block","version":1}
{"type":"clamp_warning","axes":["x","pitch"]}
{"type":"reset_ack"}
```

## 文件结构

```
android_app/
├── build.gradle.kts           # 根构建脚本
├── settings.gradle.kts        # 项目设置
├── gradle.properties          # Gradle 配置
├── gradle/wrapper/            # Gradle Wrapper
└── app/
    ├── build.gradle.kts       # APP 构建脚本
    ├── proguard-rules.pro     # ProGuard 规则
    └── src/main/
        ├── AndroidManifest.xml
        ├── java/com/pieblock/remote/
        │   ├── MainActivity.kt       # 主界面 + 生命周期
        │   ├── PoseDataSource.kt     # 传感器 + ARCore 数据采集
        │   ├── PoseWebSocketClient.kt # WebSocket 通信
        │   └── QrScanner.kt          # 二维码扫描
        └── res/                      # 布局、颜色、主题、图标
```
