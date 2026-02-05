import 'package:flutter/material.dart';

import 'home_page.dart';

class TapoExampleApp extends StatelessWidget {
  const TapoExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    const title = 'Tapo P115 Demo';
    return MaterialApp(
      title: title,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green), useMaterial3: true),
      home: const HomePage(title: title),
    );
  }
}
