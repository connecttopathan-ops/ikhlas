import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';

/// Dedicated front-camera selfie capture. Returns the captured [XFile] via
/// Navigator.pop, or null if cancelled. Forces the front lens explicitly —
/// image_picker's preferredCameraDevice is only a hint most devices ignore.
class SelfieCaptureScreen extends StatefulWidget {
  const SelfieCaptureScreen({super.key});
  @override
  State<SelfieCaptureScreen> createState() => _SelfieCaptureScreenState();
}

class _SelfieCaptureScreenState extends State<SelfieCaptureScreen> {
  CameraController? _controller;
  Future<void>? _init;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init = _setup();
  }

  Future<void> _setup() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.isNotEmpty ? cameras.first : throw 'no-camera',
      );
      final controller = CameraController(front, ResolutionPreset.medium,
          enableAudio: false);
      await controller.initialize();
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) setState(() => _error = 'Camera unavailable.');
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await c.takePicture();
      if (mounted) Navigator.of(context).pop(file);
    } catch (_) {
      if (mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not capture. Please try again.',
                style: AppType.inter(13))));
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: Row(children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.arrow_back, size: 22, color: DarkTokens.muted(.7)),
            ),
            Expanded(
              child: Text('Your selfie',
                  style: AppType.inter(14,
                      weight: FontWeight.w500, color: DarkTokens.ivory)),
            ),
          ]),
        ),
        Expanded(
          child: FutureBuilder(
            future: _init,
            builder: (context, snap) {
              if (_error != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.screenMargin),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: AppType.inter(14, color: DarkTokens.muted())),
                  ),
                );
              }
              final c = _controller;
              if (c == null || !c.value.isInitialized) {
                return const Center(child: CircularProgressIndicator());
              }
              return Padding(
                padding: const EdgeInsets.all(AppSpace.screenMargin),
                child: Column(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: c.value.previewSize?.height ?? 300,
                          height: c.value.previewSize?.width ?? 400,
                          child: CameraPreview(c),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Centre your face, then capture.',
                      style: AppType.inter(13, color: DarkTokens.muted())),
                  const SizedBox(height: 16),
                ]),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 28, top: 4),
          child: GestureDetector(
            onTap: _capturing ? null : _capture,
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DarkTokens.gold.withOpacity(_capturing ? .4 : 1),
                border: Border.all(color: DarkTokens.bg, width: 4),
                boxShadow: [
                  BoxShadow(color: DarkTokens.gold.withOpacity(.4), blurRadius: 12)
                ],
              ),
              child: _capturing
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: DarkTokens.bg))
                  : Icon(Icons.camera_alt, color: DarkTokens.bg, size: 30),
            ),
          ),
        ),
      ]),
    );
  }
}
