import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../data/repositories/application_repository.dart';
import '../../providers/application_provider.dart';

/// Mandatory government-ID verification (PRD Step 4A) — runs after gate
/// approval, before pool entry. The applicant chooses exactly one document
/// (passport preferred), uploads a single image, and a moderator reviews it
/// manually. The image is sent only to the admin-only quarantine bucket; it is
/// never shown to other members and never stored on any client-readable path.
class VerifyIdScreen extends ConsumerStatefulWidget {
  const VerifyIdScreen({super.key});
  @override
  ConsumerState<VerifyIdScreen> createState() => _VerifyIdScreenState();
}

class _VerifyIdScreenState extends ConsumerState<VerifyIdScreen> {
  String _type = 'passport'; // passport is the default/preferred document
  XFile? _image;
  bool _busy = false;

  Future<void> _capture(ImageSource source) async {
    final x = await ImagePicker().pickImage(
        source: source, imageQuality: 70, maxWidth: 1600);
    if (x != null) setState(() => _image = x);
  }

  Future<void> _submit() async {
    if (_image == null || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _image!.readAsBytes();
      await ref.read(applicationRepositoryProvider).submitIdDoc(
            type: _type,
            imageBase64: base64Encode(bytes),
          );
      // The router reacts to idDocStatus → 'submitted' and shows the pending
      // state; nothing to navigate here.
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not submit. Please try again.',
                style: AppType.inter(13))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(userDocProvider).value?.data();
    final idStatus = doc?['idDocStatus'] as String?;
    final status = doc?['status'] as String?;

    if (idStatus == 'submitted') return _pending();
    final rejected = idStatus == 'rejected' || status == 'needs_info';
    return _form(rejected);
  }

  Widget _pending() => IkhlasScaffold(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.screenMargin),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const LozengeMark(size: 72, opacity: .8),
              const SizedBox(height: 24),
              Text('Under review', style: AppType.fraunces(24, color: DarkTokens.ivory)),
              const SizedBox(height: 10),
              Text(
                  'JazakAllah khair. Your ID has been received and is being '
                  'reviewed by our team. You will be notified once you are '
                  'verified, in shaa Allah.',
                  textAlign: TextAlign.center,
                  style: AppType.inter(13.5, color: DarkTokens.muted(), height: 1.6)),
            ]),
          ),
        ),
      );

  Widget _form(bool rejected) => IkhlasScaffold(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.screenMargin, 28, AppSpace.screenMargin, 28),
            children: [
              Text('Verify your identity',
                  style: AppType.fraunces(27, color: DarkTokens.ivory)),
              const SizedBox(height: 10),
              Text(
                  'Ikhlaas is built on trust. Every profile is identity-verified '
                  'before entering the pool — this is how we keep out '
                  'catfishing. Your ID is reviewed privately by our team, is '
                  'never shown to any other member, and is stored securely.',
                  style: AppType.inter(13.5, color: DarkTokens.muted(), height: 1.6)),
              if (rejected) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: DarkTokens.gold.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DarkTokens.hairline(.4)),
                  ),
                  child: Text(
                      'Your previous submission needs another look. Please '
                      're-capture a clear, well-lit photo where the name and '
                      'number are readable.',
                      style: AppType.inter(12.5, color: DarkTokens.ivory, height: 1.5)),
                ),
              ],
              const SizedBox(height: 26),
              Text('DOCUMENT', style: AppType.eyebrow(DarkTokens.gold)),
              const SizedBox(height: 12),
              _docOption('passport', 'Passport', 'Preferred — fastest to verify'),
              const SizedBox(height: 10),
              _docOption('aadhaar', 'Aadhaar', 'Only the last 4 digits are ever kept'),
              const SizedBox(height: 26),
              Text('PHOTO OF YOUR ${_type == 'passport' ? 'PASSPORT' : 'AADHAAR'}',
                  style: AppType.eyebrow(DarkTokens.gold)),
              const SizedBox(height: 12),
              _imageArea(),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: PrimaryCta(
                  label: _busy ? 'Submitting…' : 'Submit for verification',
                  onPressed: (_image != null && !_busy) ? _submit : null,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _docOption(String value, String title, String sub) {
    final selected = _type == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _type = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? DarkTokens.gold : DarkTokens.hairline(.5),
              width: selected ? 1.4 : 1),
          color: selected ? DarkTokens.gold.withValues(alpha: .06) : null,
        ),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20, color: selected ? DarkTokens.gold : DarkTokens.muted(.6)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppType.inter(15, weight: FontWeight.w600, color: DarkTokens.ivory)),
              const SizedBox(height: 2),
              Text(sub, style: AppType.inter(12, color: DarkTokens.muted())),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _imageArea() {
    if (_image != null) {
      return Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(_image!.path, height: 200,
              width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => FutureBuilder(
                    future: _image!.readAsBytes(),
                    builder: (_, s) => s.hasData
                        ? Image.memory(s.data!, height: 200,
                            width: double.infinity, fit: BoxFit.cover)
                        : const SizedBox(height: 200),
                  )),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() => _image = null),
          child: Text('Retake', style: AppType.inter(13.5, color: DarkTokens.gold)),
        ),
      ]);
    }
    return Row(children: [
      Expanded(child: _captureBtn('Camera', Icons.photo_camera_outlined, ImageSource.camera)),
      const SizedBox(width: 12),
      Expanded(child: _captureBtn('Gallery', Icons.photo_library_outlined, ImageSource.gallery)),
    ]);
  }

  Widget _captureBtn(String label, IconData icon, ImageSource source) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _capture(source),
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DarkTokens.hairline(.5)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 26, color: DarkTokens.gold),
            const SizedBox(height: 8),
            Text(label, style: AppType.inter(13, color: DarkTokens.muted(.85))),
          ]),
        ),
      );
}
