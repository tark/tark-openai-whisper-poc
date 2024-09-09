import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocation_poc/ui/common_widgets/spinner.dart';
import 'package:geolocation_poc/ui/ui_constants.dart';
import 'package:geolocation_poc/util/context_extensions.dart';
import 'package:geolocation_poc/util/notifications_util.dart';
import 'package:geolocation_poc/util/locations_util.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:flutter_compass/flutter_compass.dart';
import 'package:location/location.dart';
import 'package:audio_service/audio_service.dart';
import 'package:slider_button/slider_button.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:geolocation_poc/util/log.dart';
import 'common_widgets/buttons.dart';
import 'common_widgets/texts.dart';

import '../util/audio_util.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  GoogleMapController? _mapController;

  BitmapDescriptor? _userMarkerIcon;
  BitmapDescriptor? _placeMarkerIcon;

  final location = Location();
  final audioHandler = MyAudioHandler();
  final List<Place> _locations = [
    Place(
      location: const LatLng(-33.90509336406157, 151.18219312610736),
      name: "31 Devine St",
      imageUrl: "assets/images/25.jpeg",
      audioUrl: "audio/31_devine_st.mp3",
    ),
    Place(
      location: const LatLng(-33.904746587684, 151.18150796894392),
      name: "1 Devine St",
      imageUrl: "assets/images/17.jpeg",
      audioUrl: "audio/1_devine_st.mp3",
    ),
    Place(
      location: const LatLng(-33.9041761813776, 151.18143913580823),
      name: "193 Rochford St",
      imageUrl: "assets/images/9.jpeg",
      audioUrl: "audio/193_rochford_st.mp3",
    ),
    Place(
      location: const LatLng(-33.90357104858936, 151.18190882587766),
      name: "171 Rochford St",
      imageUrl: "assets/images/1.jpeg",
      audioUrl: "audio/171_rochford_st.mp3",
    ),
    Place(
      location: const LatLng(-33.9026941888735, 151.18230337853444),
      name: "137 Rochford St",
      imageUrl: "assets/images/1.jpeg",
      audioUrl: "audio/137_rochford_st.mp3",
    ),
    Place(
      location: const LatLng(-33.90220666188612, 151.18294886218675),
      name: "12 Victoria St",
      imageUrl: "assets/images/1.jpeg",
      audioUrl: "audio/12_victoria_st.mp3",
    ),
    Place(
      location: const LatLng(45.033460037431404, 41.93096903499481),
      name: "Дом",
      imageUrl: "assets/images/1.jpeg",
      audioUrl: "audio/home.mp3",
    ),
    Place(
      location: const LatLng(45.03634078901804, 41.921879494155824),
      name: "Площадь",
      imageUrl: "assets/images/1.jpeg",
      audioUrl: "audio/square.mp3",
    ),
    Place(
      location: const LatLng(45.028259906704136, 41.9203919940623),
      name: "Парк",
      imageUrl: "assets/images/1.jpeg",
      audioUrl: "audio/park.mp3",
    ),
  ];

  var _currentPosition = const LatLng(0, 0);
  var _permissionGranted = false;
  var _modalShown = false;
  var _isRideMode = false;
  var _isMoving;
  var _enabled;
  var _motionActivity;
  var _odometer;
  var _content;

  var _heading = 0;

  JsonEncoder encoder = const JsonEncoder.withIndent('     ');

  @override
  void initState() {
    super.initState();
    _isMoving = false;
    _enabled = false;
    _content = '';
    _motionActivity = 'UNKNOWN';
    _odometer = '0';

    _loadCustomMarkers();
    requestLocationPermission();
    activateAudioSession();
    startAudioService();

    NotificaitonsUtil().initNotifications();

    FlutterCompass.events?.listen((CompassEvent event) {
      setState(() {
        _heading = event.heading?.toInt() ?? 0;
      });
    });

    bg.BackgroundGeolocation.onLocation(_onLocation);
    bg.BackgroundGeolocation.onMotionChange(_onMotionChange);
    bg.BackgroundGeolocation.onActivityChange(_onActivityChange);
    bg.BackgroundGeolocation.onProviderChange(_onProviderChange);
    bg.BackgroundGeolocation.onConnectivityChange(_onConnectivityChange);

    bg.BackgroundGeolocation.ready(bg.Config(
            desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
            distanceFilter: 10.0,
            stopOnTerminate: false,
            startOnBoot: true,
            debug: true,
            logLevel: bg.Config.LOG_LEVEL_VERBOSE,
            reset: true))
        .then((bg.State state) {
      setState(() {
        _enabled = state.enabled;
        _isMoving = state.isMoving == true;
      });
    });

    bg.BackgroundGeolocation.start().then((bg.State state) {
      l('[start] success $state');
      setState(() {
        _enabled = state.enabled;
        _isMoving = state.isMoving == true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: _permissionGranted
          ? Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition,
                    zoom: 15,
                  ),
                  onMapCreated: (c) {
                    _mapController = c;
                    _startLocationUpdates();
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  markers: _buildMarkers(),
                ),
                _buildBikeButton(),
                _isRideMode ? _buildRideModeOverlay() : const SizedBox.shrink(),
              ],
            )
          : _buildPermissionDeniedWidget(),
    );
  }

  Widget _buildRideModeOverlay() {
    WakelockPlus.enable();

    List<Place> nearbyPlaces = _locations.where((place) {
      final distance = _calculateDistance(_currentPosition, place.location);
      return distance <= 500;
    }).toList();

    if (nearbyPlaces.isEmpty) {
      return Positioned.fill(
        child: Container(
          color: Colors.black.withOpacity(0.8),
          child: const Center(
            child: Texts(
              'No nearby locations within 500 meters.',
              color: Colors.white,
              fontSize: AppSize.fontMedium,
            ),
          ),
        ),
      );
    }

    Place closestPlace = nearbyPlaces.reduce((a, b) {
      final distanceA = _calculateDistance(_currentPosition, a.location);
      final distanceB = _calculateDistance(_currentPosition, b.location);
      return distanceA < distanceB ? a : b;
    });

    final angle = _calculateAngle(_currentPosition, closestPlace.location);
    final rotationAngle = angle - (_heading * pi / 180);
    final distanceToClosestPlace = _calculateDistance(_currentPosition, closestPlace.location);

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Texts(
              'Closest location: ' + closestPlace.name,
              color: context.primary,
              fontSize: AppSize.fontMedium,
              fontWeight: FontWeight.bold,
            ),
            Texts(
              '${distanceToClosestPlace.toStringAsFixed(0)} meters away',
              color: context.primary,
              fontSize: AppSize.fontMedium,
            ),
            Transform.rotate(
              angle: -rotationAngle,
              child: Icon(
                Icons.arrow_back_rounded,
                size: 100,
                color: context.primary,
              ),
            ),
            const Vertical.bigExtra(),
            SliderButton(
              action: () async {
                setState(() {
                  _isRideMode = false;
                });
                return null;
              },
              label: Texts(
                "Back to map mode",
                color: context.cardBackground,
                fontWeight: FontWeight.w500,
                fontSize: AppSize.fontNormal,
              ),
              icon: Icon(
                Icons.arrow_forward,
                color: context.cardBackground,
                size: AppSize.iconSizeBig,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Spinner(
            color: context.secondary,
          ),
          const Vertical.normal(),
          Texts(
            'Waiting for location permission...',
            fontSize: AppSize.fontNormal,
            fontWeight: FontWeight.w500,
            color: context.secondary,
          ),
          const SizedBox(height: 16),
          Buttons(
            text: 'Retry',
            onPressed: requestLocationPermission,
            width: 200,
            buttonColor: context.cardBackground,
          ),
        ],
      ),
    );
  }

  Widget _buildBikeButton() {
    return Positioned(
      top: 50,
      right: 10,
      child: FloatingActionButton(
        onPressed: () {
          setState(() {
            _isRideMode = true;
          });
        },
        backgroundColor: Colors.white,
        child: const Icon(Icons.directions_bike),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  Set<Marker> _buildMarkers() {
    Set<Marker> markers = {};
    if (_userMarkerIcon != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user'),
          position: _currentPosition,
          icon: _userMarkerIcon ?? BitmapDescriptor.defaultMarker,
        ),
      );
    }

    if (_placeMarkerIcon != null) {
      for (final place in _locations) {
        markers.add(
          Marker(
            markerId: MarkerId(place.location.toString()),
            position: place.location,
            icon: _placeMarkerIcon ?? BitmapDescriptor.defaultMarker,
            onTap: () {
              _showPlaceDetails(place);
            },
          ),
        );
      }
    }

    return markers;
  }

  _calculateDistance(LatLng pos1, LatLng pos2) {
    var p = 0.017453292519943295;
    var a = 0.5 -
        cos((pos2.latitude - pos1.latitude) * p) / 2 +
        cos(pos1.latitude * p) *
            cos(pos2.latitude * p) *
            (1 - cos((pos2.longitude - pos1.longitude) * p)) /
            2;
    return 12742 * asin(sqrt(a)) * 1000;
  }

  _calculateAngle(LatLng from, LatLng to) {
    final deltaX = to.longitude - from.longitude;
    final deltaY = to.latitude - from.latitude;
    return atan2(deltaY, deltaX); // Return angle in radians
  }

  Future<void> _loadCustomMarkers() async {
// _userMarkerIcon = await _createCircleMarker(Colors.blue);
    _placeMarkerIcon = await _createCircleMarker(Colors.red);
  }

  Future<BitmapDescriptor> _createCircleMarker(Color color) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    const size = 70;
    const shadowOffset = 2.0;
    const shadowSigma = 3.0;

    const offsetX = size / 2;
    const offsetY = size / 2;
    const radius = size / 3;
    const radiusSmall = radius * 0.65;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, shadowSigma);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      const Offset(offsetX, offsetY + shadowOffset),
      radius,
      shadowPaint,
    );
    canvas.drawCircle(
      const Offset(offsetX, offsetY),
      radius,
      whitePaint,
    );
    canvas.drawCircle(
      const Offset(offsetX, offsetY),
      radiusSmall,
      paint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData != null) {
      return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
    } else {
      throw Exception('Failed to convert image to byte data');
    }
  }

  Future<void> requestLocationPermission() async {
    bool serviceEnabled;
    PermissionStatus permissionStatus;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) return;
    }

    permissionStatus = await location.hasPermission();
    if (permissionStatus == PermissionStatus.denied) {
      permissionStatus = await location.requestPermission();
      if (permissionStatus != PermissionStatus.granted) return;
    }

    if (permissionStatus == PermissionStatus.granted) {
      setState(() {
        _permissionGranted = true;
      });
      _startLocationUpdates();
    } else {
      setState(() {
        _permissionGranted = false;
      });
    }
  }

  Future<void> _showPlaceDetails(Place place) async {
    if (_modalShown) {
      return;
    }

    setState(() {
      _modalShown = true;
    });

    NotificaitonsUtil().showNotification(
        title: place.name,
        body: "Congratulations! You have reached: " + place.name);
    await audioHandler.playUrl(place.audioUrl);

    try {
      await showModalBottomSheet(
        context: context,
        builder: (c) {
          return FractionallySizedBox(
            heightFactor: 0.4,
            child: Container(
              width: double.infinity,
              padding: AppPadding.allNormal,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Texts(
                      place.name,
                      fontSize: AppSize.fontBig,
                      fontWeight: FontWeight.w500,
                      color: c.primary,
                      isCenter: true,
                      maxLines: 5,
                      overflow: TextOverflow.visible,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        barrierColor: context.dialogBarrier.withOpacity(0.3),
      );
    } finally {
      await audioHandler.stop();
      setState(() {
        _modalShown = false;
      });
    }
  }

  Future<void> startAudioService() async {
    AudioHandler audioHandler = await AudioService.init(
      builder: () => MyAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.app.channel.audio',
        androidNotificationChannelName: 'Audio Playback',
        androidNotificationOngoing: true,
      ),
    );

    audioHandler.play();
  }

  void _startLocationUpdates() {
    Timer.periodic(
      const Duration(seconds: 1),
      (Timer timer) {
        location.getLocation().then(
          (LocationData currentLocation) {
            setState(() {
              _currentPosition = LatLng(
                currentLocation.latitude ?? 0,
                currentLocation.longitude ?? 0,
              );
            });
            _moveCameraToPosition(_currentPosition);
            _checkProximityToPlaces();
          },
        );
      },
    );
  }

  void _moveCameraToPosition(LatLng position) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(position),
    );
  }

  void _checkProximityToPlaces() {
    for (final place in _locations) {
      final distance = _calculateDistance(_currentPosition, place.location);

      if (distance < 15 && !_modalShown && !place.hasShownPopup) {
        _showPlaceDetails(place);
        place.hasShownPopup = true;
        break;
      } else if (distance > 15 && place.hasShownPopup) {
        place.hasShownPopup = false;
      }
    }
  }

  void _onLocation(bg.Location location) {
    final currentLatLng =
        LatLng(location.coords.latitude, location.coords.longitude);
    final String odometerKM = (location.odometer / 1000.0).toStringAsFixed(1);

    for (final place in _locations) {
      final distance = _calculateDistance(currentLatLng, place.location);

      if (distance < 10) {
        final modalRoute = ModalRoute.of(context);
        if (modalRoute != null && !modalRoute.isCurrent) {
          audioHandler.playUrl(place.audioUrl);
          NotificaitonsUtil().showNotification(
            title: 'You are near ${place.name}',
            body: 'Check out ${place.name}',
          );
        }
      }
    }

    l('[location] - $location');
    setState(() {
      _content = encoder.convert(location.toMap());
      _odometer = odometerKM;
    });
  }

  void _onMotionChange(bg.Location location) {
    l('[motionchange] - $location');
  }

  void activateAudioSession() {
    const MethodChannel('flutter_audio_service')
        .invokeMethod('startAudioService');
  }

  void _onActivityChange(bg.ActivityChangeEvent event) {
    l('[activitychange] - $event');

    setState(() {
      _motionActivity = event.activity;
    });
  }

  void _onProviderChange(bg.ProviderChangeEvent event) {
    l('$event');

    setState(() {
      _content = encoder.convert(event.toMap());
    });
  }

  void _onConnectivityChange(bg.ConnectivityChangeEvent event) {
    l('$event');
  }
}
