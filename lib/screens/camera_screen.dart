import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:intl/intl.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  ScreenshotController _screenshotController = ScreenshotController();
  
  bool _isCameraInitialized = false;
  bool _isRearCameraSelected = true;
  bool _isVideoMode = false;
  bool _isRecording = false;
  FlashMode _flashMode = FlashMode.off;

  Position? _currentPosition;
  ReverseGeocodePlace? _currentAddress;
  String _formattedDate = "";

  @override
  void initState() {
    super.initState();
    _initCamera(widget.cameras.first);
    _getCurrentLocation();
    _updateDate();
  }

  void _updateDate() {
    setState(() {
      _formattedDate = DateFormat("EEEE, dd MMMM yyyy HH:mm:ss").format(DateTime.now());
    });
    Future.delayed(const Duration(seconds: 1), _updateDate);
  }

  Future<void> _initCamera(CameraDescription camera) async {
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await _controller!.initialize();
      setState(() {
        _isCameraInitialized = true;
      });
      await _controller!.setFlashMode(_flashMode);
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied, we cannot request permissions.');
    }

    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
    setState(() {
      _currentPosition = position;
    });

    try {
      ReverseGeocodeResponse? result = await MapplsReverseGeocode(
        location: LatLng(position.latitude, position.longitude)
      ).callReverseGeocode();
      if (result != null && result.results != null && result.results!.isNotEmpty) {
        setState(() {
          _currentAddress = result.results!.first;
        });
      }
    } catch (e) {
      debugPrint("Geocoding Error: $e");
    }
  }

  void _toggleCamera() {
    if (widget.cameras.length < 2) return;
    setState(() {
      _isCameraInitialized = false;
      _isRearCameraSelected = !_isRearCameraSelected;
    });
    CameraDescription selectedCamera = widget.cameras.firstWhere(
      (c) => c.lensDirection == (_isRearCameraSelected ? CameraLensDirection.back : CameraLensDirection.front),
      orElse: () => widget.cameras.first,
    );
    _initCamera(selectedCamera);
  }

  void _toggleFlash() async {
    if (_controller == null) return;
    setState(() {
      _flashMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    });
    await _controller!.setFlashMode(_flashMode);
  }

  String _formatLocation(double? lat, double? lng) {
    if (lat == null || lng == null) return "Lat ... Long ...";
    String latDir = lat > 0 ? "N" : "S";
    String lngDir = lng > 0 ? "E" : "W";

    String formatCoord(double coord) {
      double abs = coord.abs();
      int deg = abs.floor();
      int min = ((abs - deg) * 60).floor();
      double sec = (((abs - deg) * 60) - min) * 60;
      return "$deg° $min' ${sec.toStringAsFixed(3)}''";
    }

    return "Lat ${formatCoord(lat)} $latDir Long ${formatCoord(lng)} $lngDir";
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      // Small feedback UI update could go here
      final image = await _screenshotController.capture(delay: const Duration(milliseconds: 10));
      if (image != null) {
        final directory = await getTemporaryDirectory();
        final imagePath = '${directory.path}/gps_cam_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(imagePath);
        await file.writeAsBytes(image);
        
        await GallerySaver.saveImage(imagePath);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo saved to gallery!')));
      }
    } catch (e) {
      debugPrint("Screenshot Capture Error: $e");
    }
  }

  Future<void> _recordVideo() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isRecording) {
      try {
        final video = await _controller!.stopVideoRecording();
        setState(() {
          _isRecording = false;
        });
        await GallerySaver.saveVideo(video.path);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video saved to gallery!')));
      } catch (e) {
        debugPrint("Stop Video Error: $e");
      }
    } else {
      try {
        await _controller!.startVideoRecording();
        setState(() {
          _isRecording = true;
        });
      } catch (e) {
        debugPrint("Start Video Error: $e");
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _buildTopControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 40.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(LucideIcons.menu, color: Colors.white), onPressed: () {}),
          IconButton(
            icon: Icon(LucideIcons.zap, color: _flashMode == FlashMode.off ? Colors.white : Colors.yellow),
            onPressed: _toggleFlash,
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _isVideoMode = !_isVideoMode;
              });
            },
            child: Text(
              _isVideoMode ? "VIDEO" : "PHOTO",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(icon: const Icon(LucideIcons.refreshCcw, color: Colors.white), onPressed: _toggleCamera),
          IconButton(icon: const Icon(LucideIcons.maximize, color: Colors.white), onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildFocusSquare() {
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.greenAccent, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildWatermarkOverlay() {
    String locationTitle = "Fetching Location...";
    String addressText = "Loading exact address...";
    
    if (_currentAddress != null) {
      locationTitle = _currentAddress!.poi ?? _currentAddress!.street ?? _currentAddress!.locality ?? "Location Details";
      addressText = _currentAddress!.formattedAddress ?? "";
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.only(bottom: 120, left: 12, right: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // Map Thumbnail
            Container(
              width: 80,
              height: 80,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.antiAlias,
              child: _currentPosition != null
                  ? AbsorbPointer(
                      child: MapplsMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                          zoom: 14.0,
                        ),
                        myLocationEnabled: true,
                        myLocationTrackingMode: MyLocationTrackingMode.none,
                        compassEnabled: false,
                      ),
                    )
                  : Container(color: Colors.grey[800]),
            ),

            // Location Info
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(locationTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(addressText, style: const TextStyle(color: Colors.white70, fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(_formatLocation(_currentPosition?.latitude, _currentPosition?.longitude), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(_formattedDate, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  const SizedBox(height: 2),
                  const Text("Note: This is amazing place to spend your vacation", style: TextStyle(color: Colors.white, fontSize: 9, fontStyle: FontStyle.italic)),
                  
                  const SizedBox(height: 4),
                  // Mock Weather Row
                  Row(
                    children: [
                      const Icon(LucideIcons.thermometer, color: Colors.amber, size: 10),
                      const Text(" 32°C  ", style: TextStyle(color: Colors.white, fontSize: 9)),
                      const Icon(LucideIcons.wind, color: Colors.blueAccent, size: 10),
                      const Text(" 30 km/h  ", style: TextStyle(color: Colors.white, fontSize: 9)),
                      const Icon(LucideIcons.droplets, color: Colors.blueAccent, size: 10),
                      const Text(" 53%  ", style: TextStyle(color: Colors.white, fontSize: 9)),
                      const Icon(LucideIcons.mountain, color: Colors.redAccent, size: 10),
                      Text(" ${_currentPosition?.altitude.round() ?? '605'} m", style: const TextStyle(color: Colors.white, fontSize: 9)),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
      );
    }

    final scale = 1 / (_controller!.value.aspectRatio * MediaQuery.of(context).size.aspectRatio);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Screenshot(
            controller: _screenshotController,
            child: Stack(
              children: [
                // Full Screen Camera view
                Positioned.fill(
                  child: Transform.scale(
                    scale: scale < 1.0 ? 1.0 : scale, // basic full screen stretching technique
                    child: Center(
                      child: CameraPreview(_controller!),
                    ),
                  ),
                ),
                
                // Top Controls
                Align(alignment: Alignment.topCenter, child: _buildTopControls()),

                // Center Focus Box
                _buildFocusSquare(),

                // Bottom Overlay
                _buildWatermarkOverlay(),
              ],
            ),
          ),
          
          // Shutter Button (outside screenshot!)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30.0),
              child: GestureDetector(
                onTap: _isVideoMode ? _recordVideo : _capturePhoto,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  child: Center(
                    child: Container(
                      width: 55,
                      height: 55,
                      decoration: BoxDecoration(
                        shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                        borderRadius: _isRecording ? BorderRadius.circular(10) : null,
                        color: _isRecording ? Colors.red : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
