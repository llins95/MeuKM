import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/shell/meukm_shell.dart';
import '../services/app_controller.dart';

class MeuKmApp extends StatelessWidget {
  const MeuKmApp({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF0759D6);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MeuKM',
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: blue, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF3F6F7),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: Color(0xFFD6DFE1)),
          ),
        ),
      ),
      home: MeuKmShell(controller: controller),
    );
  }
}
