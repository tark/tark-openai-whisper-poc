import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:translator/translator.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:record/record.dart';
import 'package:tark_openai_whisper_poc/util/context_extensions.dart';

import '../util/log.dart';
import 'common_widgets/texts.dart';
import 'ui_constants.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _messages = [];
  final _player = AudioPlayer();
  final translator = GoogleTranslator();
  final noiseMeter = NoiseMeter();
  final english = RegExp(r'^[a-zA-Z]+');

  late AudioRecorder _recorder;
  late AnimationController _animationController;

  var _isRecording = false;
  var _isPlaying = false;
  var _currentlyPlayingFilePath;
  var lastDecibelValue;
  var _filePath;
  var _currentDecibel = 0.0;

  StreamSubscription<NoiseReading>? _noiseSubscription;
  StreamSubscription? _recorderSubscription;

  Timer? _decibelTimer;

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
    _initializeRecorder();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
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
              controller: _scrollController,
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_isRecording) {
      _stopRecording();
    }
    _noiseSubscription?.cancel();
    _recorderSubscription?.cancel();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeRecorder() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
       l('Microphone permission not granted');
    }
  }

  String _generateRandomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(
      10,
      (i) => chars[random.nextInt(chars.length)],
      growable: false,
    ).join();
  }

  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
    });

    try {
      var filePath = await getApplicationDocumentsDirectory()
          .then((value) => '${value.path}/${_generateRandomId()}.wav');

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
        ),
        path: filePath,
      );

      _noiseSubscription = noiseMeter.noise.listen(
        (NoiseReading noiseReading) {
          double newDecibelValue = noiseReading.meanDecibel;

          if ((lastDecibelValue == null ||
              (newDecibelValue - lastDecibelValue).abs() >= 5)) {
            setState(() {
              lastDecibelValue = newDecibelValue;
              _currentDecibel = newDecibelValue;

              double normalizedValue =
                  ((_currentDecibel - 30) / 50).clamp(0.0, 1.0);
              double targetScale =
                  lerpDouble(0.2, 1.5, normalizedValue) ?? 40.0;

              _animationController.animateTo(
                targetScale,
                curve: Curves.easeInOut,
                duration: const Duration(milliseconds: 300),
              );
            });
          }
        },
        onError: (Object error) {
          l('$error');
        },
        cancelOnError: true,
      );

      _decibelTimer = Timer.periodic(const Duration(seconds: 5), (Timer t) {
        if (lastDecibelValue != null) {
          l('Mean decibel value (every 5 seconds): $lastDecibelValue dB');
        }
        if (lastDecibelValue! < 60) {
          _stopRecording();
        }
      });
    } catch (e) {
      l('_startRecording', 'error: $e');
    }
  }

  Future<void> _stopRecording() async {
    setState(() {
      _noiseSubscription?.cancel();
      _isRecording = false;
    });
    _scrollToBottom();
    _decibelTimer?.cancel();
    _animationController.animateTo(0.0, curve: Curves.easeOut);

    var path = await _recorder.stop();
    if (path == null) {
      return;
    }

    setState(() {
      _filePath = path;
    });

    debugPrint('=========>>>>>> PATH: $_filePath <<<<<<===========');

    _messages.add(Message(
      audioFilePath: _filePath,
      decibels: _currentDecibel,
    ));

    _scrollToBottom();

    await _processTranscription();
  }

  Future<void> _processTranscription() async {
    try {
      OpenAI.apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
      var transcription = await OpenAI.instance.audio.createTranscription(
        file: File(_filePath ?? ""),
        model: "whisper-1",
        responseFormat: OpenAIAudioResponseFormat.json,
      );

      if (transcription.text.isEmpty) {
        l('Transcription error', 'Transcription is empty.');
        return;
      }

      l('Transcription:', transcription.text);

      var translatedText =
          await translator.translate(transcription.text, to: 'en');

      _scrollToBottom();

      setState(() {
        _messages.add(Message(
          whisper: Whisper(
            transcription: transcription.text,
            translation: translatedText.text,
          ),
        ));
      });
    } catch (e) {
      l('_stopRecording', 'error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _messageItem(Message message) {
    final filePath = message.audioFilePath;
    final whisper = message.whisper;
    final decibels = message.decibels;

    if (filePath != null && whisper == null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              padding: AppPadding.allNormal,
              decoration: BoxDecoration(
                color: context.cardBackground,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: context.cardBackground,
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _playButton(filePath),
                  if (decibels != null)
                    Flexible(
                      child: EqualizerVisualizer(decibels: decibels),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    } else if (whisper != null) {
      return Row(
        mainAxisAlignment:
            filePath == null ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (filePath != null) _audioFilePath(filePath),
          Expanded(
            child: _whisperItem(whisper, decibels),
          ),
        ],
      );
    } else {
      return Container();
    }
  }

  Widget _whisperItem(Whisper whisper, double? decibels) {
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
          if (!english.hasMatch(whisper.transcription)) ...[
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
            ),
          ],
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

  Widget _button({required IconData icon, required VoidCallback onPressed}) {
    return InkWell(
      borderRadius: BorderRadius.circular(50),
      onTap: onPressed,
      child: Container(
        height: 100,
        width: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.cardBackground,
        ),
        child: Icon(
          icon,
          color: context.secondary,
          size: 50,
        ),
      ),
    );
  }

  Widget _micButton() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        double outerScale = (_animationController.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: outerScale,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.cardBackground.withOpacity(0.3),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.2),
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
            ),
          ],
        );
      },
    );
  }

  Widget _playButton(String audioFilePath) {
    return Padding(
      padding: AppPadding.leftNormal,
      child: IconButton(
        icon: Icon(
          _isPlaying && _currentlyPlayingFilePath == audioFilePath
              ? Icons.pause_outlined
              : Icons.play_arrow_outlined,
          weight: 10,
        ),
        iconSize: 30.0,
        onPressed: () async {
          if (_isPlaying && _currentlyPlayingFilePath == audioFilePath) {
            await _player.pause();
          } else {
            if (_currentlyPlayingFilePath != null &&
                _currentlyPlayingFilePath != audioFilePath) {
              await _player.stop();
            }
            await _player.play(DeviceFileSource(audioFilePath));
            _currentlyPlayingFilePath = audioFilePath;
          }

          setState(() {
            _isPlaying =
                !_isPlaying || _currentlyPlayingFilePath == audioFilePath;
          });
        },
      ),
    );
  }
}

class EqualizerVisualizer extends StatelessWidget {
  final double decibels;

  const EqualizerVisualizer({Key? key, required this.decibels})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width,
        minHeight: 30,
      ),
      child: CustomPaint(
        size: Size(MediaQuery.of(context).size.width, 30),
        painter: EqualizerPainter(decibels),
      ),
    );
  }
}

class EqualizerPainter extends CustomPainter {
  final double decibels;

  EqualizerPainter(this.decibels);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white30
      ..style = PaintingStyle.fill;

    const barCount = 50;
    const padding = 2.0;
    const totalPadding = (barCount - 1) * padding;
    final barWidth = (size.width - totalPadding) / barCount;
    final maxHeight = size.height;
    final baseHeight =
        (maxHeight * ((decibels - 30) / 50).clamp(0.0, 1.0)).isNaN
            ? 0
            : maxHeight * ((decibels - 30) / 50).clamp(0.0, 1.0);

    for (int i = 0; i < barCount; i++) {
      final minHeight = maxHeight * 0.1;
      final barHeight = (baseHeight *
              (0.6 +
                  0.4 * sin((i / barCount) * 4 * pi + Random().nextDouble())))
          .clamp(minHeight, maxHeight);
      final left = i * (barWidth + padding);
      canvas.drawRect(
        Rect.fromLTWH(left, maxHeight - barHeight, barWidth, barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class Message {
  final String? audioFilePath;
  final Whisper? whisper;
  final Widget? audioVisualizer;
  final double? decibels;

  Message({
    this.audioFilePath,
    this.whisper,
    this.audioVisualizer,
    this.decibels,
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
