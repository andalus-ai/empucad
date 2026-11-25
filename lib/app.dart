import 'package:flutter/material.dart';

import 'presentation/screens/editor_screen.dart';

class EmpuCadApp extends StatelessWidget {
  const EmpuCadApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EmpuCAD',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF3B82F6), brightness: Brightness.dark, useMaterial3: true),
        home: const EditorScreen(),
      );
}
