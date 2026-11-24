import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'providers/app_provider.dart';
import 'screens/main_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
      ],
      child: const InternNoterApp(),
    ),
  );
}

class InternNoterApp extends StatelessWidget {
  const InternNoterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppProvider, ThemeMode>(
      (provider) => provider.themeMode,
    );

    return MaterialApp(
      title: 'Intern Noter',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const MainScreen(),
    );
  }
}
