import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../providers/application_provider.dart';

/// 2c — Intent Declaration (interactive). THE signature screen.
/// Bismillah · نِيَّة / Your Intention · 3 consent rows w/ diamond checks ·
/// italic-Fraunces signature · CTA dimmed until all 3 checked + name entered.
class DeclarationScreen extends ConsumerStatefulWidget {
  const DeclarationScreen({super.key});
  @override
  ConsumerState<DeclarationScreen> createState() => _DeclarationScreenState();
}

class _DeclarationScreenState extends ConsumerState<DeclarationScreen> {
  final _checks = [false, false, false];
  final _nameCtrl = TextEditingController();
  bool _submitting = false;

  static const _affirmations = [
    'I am seeking nikah, and I intend to marry within a reasonable timeframe.',
    'I am not currently married.',
    'I understand Ikhlas is not for casual chatting or friendship.',
  ];

  bool get _complete =>
      _checks.every((c) => c) && _nameCtrl.text.trim().length >= 3;

  Future<void> _declare() async {
    setState(() => _submitting = true);
    try {
      await ref.read(applicationRepositoryProvider).saveIntentDeclaration(
            affirmations: _affirmations,
            typedName: _nameCtrl.text.trim(),
          );
      if (mounted) context.go('/questionnaire'); // Week 2 destination
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not save your declaration. Please try again.',
                style: AppType.inter(13))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.screenMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Bismillah — Amiri 21 gold, centered
            Center(
              child: Text('بِسْمِ اللَّهِ الرَّحْمَـٰنِ الرَّحِيمِ',
                  style: AppType.amiri(21, color: DarkTokens.gold)),
            ),
            const SizedBox(height: 36),
            Center(
                child:
                    Text('نِيَّة', style: AppType.amiri(15, color: DarkTokens.gold))),
            const SizedBox(height: 6),
            Center(
                child: Text('Your Intention',
                    style: AppType.fraunces(30, color: DarkTokens.ivory))),
            const SizedBox(height: 32),
            // Consent rows divided by hairlines
            for (int i = 0; i < _affirmations.length; i++) ...[
              _ConsentRow(
                text: _affirmations[i],
                checked: _checks[i],
                onChanged: (v) => setState(() => _checks[i] = v),
              ),
              if (i < _affirmations.length - 1) const Hairline(),
            ],
            const SizedBox(height: 24),
            Text(
              'Ikhlas means sincerity. This declaration is between you and Allah — '
              'and it is the standard we hold every member to.',
              style: AppType.inter(12.5, color: DarkTokens.muted(), height: 1.6),
            ),
            const SizedBox(height: 32),
            Text('SIGN WITH YOUR FULL NAME',
                style: AppType.inter(10.5,
                    weight: FontWeight.w600,
                    color: DarkTokens.gold.withOpacity(.8),
                    letterSpacing: 10.5 * .14)),
            const SizedBox(height: 4),
            TextField(
              controller: _nameCtrl,
              onChanged: (_) => setState(() {}),
              style: AppType.fraunces(23,
                  color: DarkTokens.ivory, style: FontStyle.italic),
              cursorColor: DarkTokens.gold,
              decoration: InputDecoration(
                enabledBorder: UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: DarkTokens.gold.withOpacity(.65))),
                focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: DarkTokens.gold)),
              ),
            ),
            const SizedBox(height: 40),
            PrimaryCta(
              label: 'I declare with sincerity',
              loading: _submitting,
              onPressed: _complete ? _declare : null,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Consent row: 22px rounded-square (6px radius) checkbox,
/// border rgba(gold,.55); check = 10px gold diamond fading in .3s.
class _ConsentRow extends StatelessWidget {
  final String text;
  final bool checked;
  final ValueChanged<bool> onChanged;
  const _ConsentRow(
      {required this.text, required this.checked, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.checkbox),
                border:
                    Border.all(color: DarkTokens.gold.withOpacity(.55), width: 1),
              ),
              alignment: Alignment.center,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: checked ? 1 : 0,
                child: const DiamondBullet(size: 10, color: DarkTokens.gold),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(text,
                  style: AppType.inter(14.5,
                      color: DarkTokens.ivory, height: 1.55)),
            ),
          ],
        ),
      ),
    );
  }
}
