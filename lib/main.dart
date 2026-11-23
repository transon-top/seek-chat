import 'package:flutter/widgets.dart';

import 'app/startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ZH
  // 启动链由 `startupRoot` 组装：成功返回真实应用，失败返回启动失败页；
  // 失败页重试成功后二次 `runApp` 真实应用。
  //
  // EN
  // `startupRoot` assembles the startup chain: the real app on success, the failure page
  // on failure; a successful retry runs the real app with a second `runApp`.
  runApp(await startupRoot(StartupDeps.real()));
}
