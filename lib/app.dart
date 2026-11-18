// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_theme.dart';
import 'state/ragaa_controller.dart';
import 'ui/shell_page.dart';

/// Root Flutter widget for the RAGAA central collection accounting application.
class RagaaApp extends StatelessWidget {
  final RagaaController controller;

  const RagaaApp({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RAGAA — إدارة تحصيل المنافذ',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        // ignore: deprecated_member_use
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        // ignore: deprecated_member_use
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: RagaaShellPage(controller: controller),
    );
  }
}
