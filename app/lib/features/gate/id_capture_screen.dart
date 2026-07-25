import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';

/// Dedicated rear-camera capture for government-ID documents (PRD Step 4A).
/// Shows a live preview with a ROUNDED document-frame guide sized per
/// [docType], a dimmed scrim outside the frame, and capture instructions.
/// Returns the captured [XFile] via Navigator.pop, or null if cancelled.
///
/// This is a static alignment guide only — no real-time edge detection.
class IdCaptureScreen extends StatefulWidget {
  /// 'passport' (portrait booklet page) or 'aadhaar' (landscape ID-1 card).
  final String docType;
  const IdCaptureScreen({super.key, required this.docType});

  @override
  State<IdCaptureScreen> createState() => _IdCaptureScreenState();
}

class _IdCaptureScreenState extends State<IdCaptureScreen> {
  CameraController? _controller;
  Future<void>? _init;
  bool _capturing = false;
  String? _error;

  // Frame aspect ratio as width / height.
  //  · aadhaar → ID-1 card, 85.6 × 53.98 mm ≈ 1.586 (landscape).
  //  · passport → open booklet data page is portrait ≈ 0.71 (1 / 1.42).
  bool get _isLandscape => widget.docType == 'aadhaar';
  double get _frameAspect => _isLandscape ? 1.586 : 0.71;
  String get _docLabel => widget.docType == 'passport' ? 'passport' : 'Aadhaar';

  @override
  void initState() {
    super.initState();
    _init = _setup();
  }

  Future<void> _setup() async {
    try {
      final cameras = await availableCameras();
      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.isNotEmpty ? cameras.first : throw 'no-camera',
      );
      final controller =
          CameraController(rear, ResolutionPreset.high, enableAudio: false);
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
    HapticFeedback.mediumImpact();
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
              child: Text('Photo of your $_docLabel',
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
                    child: Text(
                        'Camera unavailable. Please check permissions, or go '
                        'back and choose a photo from your gallery.',
                        textAlign: TextAlign.center,
                        style: AppType.inter(14, color: DarkTokens.muted())),
                  ),
                );
              }
              final c = _controller;
              if (c == null || !c.value.isInitialized) {
                return const Center(child: CircularProgressIndicator());
              }
              return _preview(c);
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

  /// The live preview, cropped to a rounded window, with the document-frame
  /// guide + dimming scrim painted on top and instructions below.
  Widget _preview(CameraController c) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.screenMargin),
      child: Column(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Full-bleed camera preview.
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: c.value.previewSize?.height ?? 300,
                    height: c.value.previewSize?.width ?? 400,
                    child: CameraPreview(c),
                  ),
                ),
                // Scrim + rounded document frame guide.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DocFramePainter(aspect: _frameAspect),
                  ),
                ),
                // TODO: real-time edge alignment feedback (Phase 2) — overlay
                // live corner/edge indicators here that turn gold once the
                // document is aligned within the frame.
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
            'Fit the document inside the frame · Avoid glare · Ensure all '
            'four corners are visible',
            textAlign: TextAlign.center,
            style: AppType.inter(12.5, color: DarkTokens.muted(.85), height: 1.5)),
        const SizedBox(height: 16),
      ]),
    );
  }
}

/// Paints a dimming scrim over the whole preview with a rounded rectangular
/// window cut out for the document, and strokes that window in gold.
/// Curves only — the frame is an RRect (BorderRadius ~16), never a hard rect.
class _DocFramePainter extends CustomPainter {
  final double aspect; // width / height of the document window
  _DocFramePainter({required this.aspect});

  static const double _radius = 16;

  Rect _frameRect(Size size) {
    // Fit the target aspect inside the preview, leaving a margin so the guide
    // sits comfortably within the window.
    final maxW = size.width * 0.86;
    final maxH = size.height * 0.86;
    var w = maxW;
    var h = w / aspect;
    if (h > maxH) {
      h = maxH;
      w = h * aspect;
    }
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        _frameRect(size), const Radius.circular(_radius));

    // Dimmed scrim OUTSIDE the frame (everything minus the rounded window).
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rrect),
    );
    canvas.drawPath(
      scrim,
      Paint()..color = const Color(0xFF17251B).withOpacity(.62),
    );

    // Gold outline of the document window (illumination, never fill).
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = DarkTokens.gold,
    );
  }

  @override
  bool shouldRepaint(covariant _DocFramePainter old) => old.aspect != aspect;
}
