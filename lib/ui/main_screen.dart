import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_audio_waveforms/flutter_audio_waveforms.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:tark_openai_whisper_poc/util/color_extension.dart';
import 'package:tark_openai_whisper_poc/util/context_extensions.dart';

import '../util/log.dart';
import 'common_widgets/texts.dart';
import 'ui_constants.dart';

final mockMessages = [
  Message(
    audioFilePath: 'test',
  ),
  Message(
    whisper: Whisper(
      transcription: 'Может ли иос симулятор использовать микрофон компьютера?',
      translation: 'Can the iOS simulator use the computer\'s microphone?',
    ),
  ),
  Message(
    audioFilePath: 'test',
  ),
  Message(
    whisper: Whisper(
      language: 'english',
      transcription: 'Can the iOS simulator use the computer\'s microphone?',
      translation: 'Can the iOS simulator use the computer\'s microphone?',
    ),
  ),
  Message(
    audioFilePath: 'test',
  ),
  Message(
    whisper: Whisper(
      transcription: 'Может ли иос симулятор использовать микрофон компьютера?',
      translation: 'Can the iOS simulator use the computer\'s microphone?',
    ),
  ),
  Message(
    audioFilePath: 'test',
  ),
  Message(
    whisper: Whisper(
      transcription: 'Может ли иос симулятор использовать микрофон компьютера?',
      translation: 'Can the iOS simulator use the computer\'s microphone?',
    ),
  ),
];

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  // String? _filePath;
  StreamSubscription? _recorderSubscription;
  double _decibels = 0.0;
  final _player = AudioPlayer();
  var _messages = mockMessages;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder(
      logLevel: Level.nothing,
    );
    _initializeRecorder();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Texts(
          'Whisper chat',
          fontSize: 24,
          fontWeight: FontWeight.w500,
          isCenter: true,
          color: context.secondary,
        ),
      ),
      body: Padding(
        padding: AppPadding.horizontalBig,
        child: Stack(
          children: [
            ListView.separated(
              itemCount: _messages.length,
              padding: AppPadding.bottom(160),
              itemBuilder: (c, i) => _messageItem(_messages[i]),
              separatorBuilder: (c, i) => const SizedBox(
                height: 20,
              ),
            ),
            Positioned(
              bottom: -80,
              left: 0,
              right: 0,
              child: SizedBox(
              height: 300,
              width: 300,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _micButton(),

                ],
              ),
            ),),

          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recorder?.closeRecorder();
    _recorderSubscription?.cancel();
    super.dispose();
  }

  //
  Future<void> _initializeRecorder() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }

    await _recorder?.openRecorder();
  }

  Future<void> _startRecording() async {
    l('_startRecording');

    final directory = await getTemporaryDirectory();
    // _filePath =
    //     '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder?.setSubscriptionDuration(
      const Duration(milliseconds: 100),
    );

    _recorderSubscription = _recorder?.onProgress?.listen((e) {
      l('_startRecording', 'decibels: ${e.decibels}');
      setState(() {
        _decibels = e.decibels ?? 0.0;
      });
    });

    try {
      await _recorder?.startRecorder(
        // toFile: _filePath,
      );
    } catch (e) {
      l('_startRecording', 'error: $e');
    }

    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _stopRecording() async {
    await _recorder?.stopRecorder();
    _recorderSubscription?.cancel();

    setState(() {
      _isRecording = false;
    });
    //
    // OpenAI.apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
    // OpenAIAudioModel transcription =
    //     await OpenAI.instance.audio.createTranscription(
    //   file: File(_filePath ?? ''),
    //   model: "whisper-1",
    //   responseFormat: OpenAIAudioResponseFormat.json,
    // );
    //
    // l('build', 'duration:   ${transcription.duration}');
    // l('build', 'language:   ${transcription.language}');
    // l('build', 'text:       ${transcription.text}');

    // _whispers.add(
    //   WhisperObject(
    //     transcription: transcription.text,
    //     translation: 'translation',
    //   language: transcription.language,
    //   ),);

    // setState(() {
    //   _whispers = [
    //     ..._whispers,
    //     Whisper(
    //       transcription: transcription.text,
    //       translation: 'translation',
    //       language: transcription.language,
    //     ),
    //   ];
    // });
  }

  Widget _messageItem(Message message) {
    final filePath = message.audioFilePath;
    final whisper = message.whisper;
    return Row(
      mainAxisAlignment:
          filePath == null ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: [
        if (filePath != null) _audioFilePath(filePath),
        if (whisper != null) Expanded(
          child: _whisperItem(whisper),
        ),
      ],
    );
  }

  Widget _whisperItem(Whisper whisper) {
    return Container(
      padding: AppPadding.verticalNormal + const AppPadding.horizontal(20),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: context.cardBackground,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Texts(
            whisper.transcription,
            fontSize: AppSize.fontNormal,
            maxLines: 100,
          ),
          if (whisper.language != 'english') ...[
          Divider(
            color: context.primary.withOpacity(0.25),
            height: 30,
            thickness: 0.5,
          ),
          Texts(
            whisper.translation,
            fontSize: AppSize.fontNormal,
            maxLines: 100,
            color: context.primary.withOpacity(0.4),
          ),],
        ],
      ),
    );
  }

  Widget _audioFilePath(String filePath) {
    return Container(
      padding: AppPadding.verticalNormal + const AppPadding.horizontal(20),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: context.cardBackground,
          width: 1,
        ),
      ),
      child: const Texts(
        '...',
        fontSize: AppSize.fontNormal,
        maxLines: 100,
      ),
    );
  }

  Widget _box(String text) {
    return Container(
      padding: AppPadding.verticalNormal + const AppPadding.horizontal(20),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.cardBackground,
          width: 1,
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Texts(
                    text + text,
                    fontSize: AppSize.fontNormal,
                    maxLines: 100,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _button({required IconData icon, required VoidCallback onPressed}) {
    return Material(
      elevation: 50,
      color: context.cardBackground,
      borderRadius: BorderRadius.circular(50),
      child: InkWell(
        borderRadius: BorderRadius.circular(50),
        onTap: onPressed,
        child: SizedBox(
          height: 100,
          width: 100,
          child: Icon(
            icon,
            color: context.secondary,
            size: 50,
          ),
        ),
      ),
    );
  }

  Widget _micButton() {

    return Container(
      width: 300,
      height: 300,
      padding: AppPadding.all(100),
      decoration: BoxDecoration(
        shape: BoxShape.circle, // This makes the container circular
        gradient: RadialGradient(
          colors: [
            context.background,
            context.background.withOpacity(0),
          ],
          focal: Alignment.center,
        ),
      ),
      child: _button(
        icon: _isRecording
            ? Icons.stop_outlined
            : Icons.mic_none_outlined,
        onPressed: () async {
          if (_isRecording) {
            await _stopRecording();
          } else {
            await _startRecording();
          }
        },
      ),
    );
  }

  Widget _playButton(){
    return Padding(
        padding: AppPadding.leftNormal,
        child: _button(
          icon: Icons.play_arrow_outlined,
          onPressed: () async {
            // await _player.play(DeviceFileSource(_filePath ?? ''));
          },
        ),
      );
  }
}

//
class EqualizerVisualizer extends StatelessWidget {
  final double decibels;

  const EqualizerVisualizer({Key? key, required this.decibels})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(200, 100),
      painter: EqualizerPainter(decibels),
    );
  }
}

class EqualizerPainter extends CustomPainter {
  final double decibels;

  EqualizerPainter(this.decibels);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.fill;

    final barWidth = size.width / 20;
    final maxHeight = size.height;

    for (int i = 0; i < 20; i++) {
      final barHeight = maxHeight * (decibels / 160 + (i / 20));
      canvas.drawRect(
        Rect.fromLTWH(i * barWidth, maxHeight - barHeight, barWidth, barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

//
class Message {
  final String? audioFilePath;
  final Whisper? whisper;

  Message({
    this.audioFilePath,
    this.whisper,
  });
}

class Whisper {
  final String transcription;
  final String translation;
  final String? language;

  Whisper({
    required this.transcription,
    required this.translation,
    this.language,
  });
}

//
class AudioMessage extends StatefulWidget {
  final String filePath;

  const AudioMessage({Key? key, required this.filePath}) : super(key: key);

  @override
  _AudioMessageState createState() => _AudioMessageState();
}

class _AudioMessageState extends State<AudioMessage> {
  late AudioPlayer _audioPlayer;
  // late PlayerController _controller;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    // _controller = PlayerController();
    _loadAudioWaveform();
  }

  Future<void> _loadAudioWaveform() async {
    // await _controller.load(widget.filePath);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    // _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: () async {
            await _audioPlayer.play(DeviceFileSource(widget.filePath));
          },
        ),
        Expanded(
          child: RectangleWaveform(
            samples: [],
            height: 10,
            width: 1,

            // color: Colors.blue,
            // playerController: _controller,
            // waveformType: WaveformType.bar,
            // size: Size(double.infinity, 60.0),
            // backgroundColor: Colors.grey.shade200,
            // barColor: Colors.blue,
          ),
        ),
      ],
    );
  }
}
