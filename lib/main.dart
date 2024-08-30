import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tark_openai_whisper_poc/ui/main_screen.dart';
import 'ui/theme/dark_theme.dart';

void main() async {
  await dotenv.load(fileName: ".env");

  runApp(const AudioRecorderApp());
}

class AudioRecorderApp extends StatelessWidget {
  const AudioRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Whisper chat',
      themeMode: ThemeMode.dark,
      theme: darkTheme,
      home: const MainScreen(),
    );
  }
}
