import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../providers/application_provider.dart';

/// Phone capture — MANDATORY in Phase 1 (stored unverified; OTP verify = Phase 2).
/// Indian mobile validation: 10 digits starting 6–9, stored as +91XXXXXXXXXX.
class PhoneCaptureScreen extends ConsumerStatefulWidget {
  const PhoneCaptureScreen({super.key});
  @override
  ConsumerState<PhoneCaptureScreen> createState() => _PhoneCaptureScreenState();
}

class _PhoneCaptureScreenState extends ConsumerState<PhoneCaptureScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  bool get _valid => RegExp(r'^[6-9]\d{9}$').hasMatch(_ctrl.text.trim());

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(applicationRepositoryProvider)
          .savePhone('+91${_ctrl.text.trim()}');
      if (mounted) context.go('/declaration');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not save. Please try again.',
                style: AppType.inter(13))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      // Scrolls instead of overflowing when the keyboard is up on short devices.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.screenMargin),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),
            Text('YOUR APPLICATION', style: AppType.eyebrow(DarkTokens.gold)),
            const SizedBox(height: 14),
            Text('Your mobile number',
                style: AppType.fraunces(32, color: DarkTokens.ivory, height: 1.1)),
            const SizedBox(height: 10),
            Text(
                'Required to complete your application — used for guardian (Wali) '
                'contact and account security. We will verify it later; '
                'we never share it with other members.',
                style: AppType.inter(14, color: DarkTokens.muted(.62))),
            const SizedBox(height: 40),
            Text('MOBILE NUMBER',
                style: AppType.eyebrow(DarkTokens.gold.withOpacity(.8))),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('+91',
                      style: AppType.inter(16, color: DarkTokens.muted())),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: AppType.inter(16, color: DarkTokens.ivory),
                    cursorColor: DarkTokens.gold,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '98765 43210',
                      hintStyle: AppType.inter(16, color: DarkTokens.muted(.4)),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: DarkTokens.gold.withOpacity(.65))),
                      focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: DarkTokens.gold)),
                    ),
                  ),
                ),
              ],
            ),
            if (_ctrl.text.isNotEmpty && !_valid) ...[
              const SizedBox(height: 8),
              Text('Enter a valid 10-digit Indian mobile number.',
                  style: AppType.inter(12.5, color: DarkTokens.muted())),
            ],
                    const Spacer(),
                    PrimaryCta(
                        label: 'Continue',
                        loading: _busy,
                        onPressed: _valid && !_busy ? _save : null),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
