import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前宿主是不是 iOS。
///
/// 默认按 [defaultTargetPlatform]；widget 测试在桌面宿主上跑，那里平台是
/// macos/linux/windows 而不是 iOS，所以测试用 [isIosProvider] 的 override
/// 注入想要的平台，再断言"入口在 iOS 上隐 / 在 Android 上现"。
final isIosProvider = Provider<bool>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS,
);

/// 是否支持本地 DSH 引擎（PRoot）。iOS 不支持——本地引擎的安装、启动、连接
/// 与相关页面在 iOS 上全部隐藏/拦截。与 [phoneControlSupportedProvider] 是两个
/// 独立能力（手机操控是无障碍平台能力，与引擎无关），只是当前取值恰好相同。
final localEngineSupportedProvider = Provider<bool>(
  (ref) => !ref.watch(isIosProvider),
);

/// 是否支持手机操控（无障碍）。iOS 不支持。
final phoneControlSupportedProvider = Provider<bool>(
  (ref) => !ref.watch(isIosProvider),
);
