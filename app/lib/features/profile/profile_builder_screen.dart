import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../providers/application_provider.dart';
import '../gate/questionnaire/questionnaire_models.dart';
import '../gate/questionnaire/questionnaire_widgets.dart';

/// Profile builder (PRD §4.1 step 6): photos + privacy mode, guided bio
/// prompts (no blank text box), match preferences, Wali setup.
/// One atomic save at the end → profileComplete → home.
class ProfileBuilderScreen extends ConsumerStatefulWidget {
  const ProfileBuilderScreen({super.key});
  @override
  ConsumerState<ProfileBuilderScreen> createState() =>
      _ProfileBuilderScreenState();
}

class _ProfileBuilderScreenState extends ConsumerState<ProfileBuilderScreen> {
  static const _totalSteps = 5;
  int _step = 1;
  bool _saving = false;

  // Step 1 — photos
  final List<XFile> _photos = [];

  // Step 2 — privacy (PRD: default blur_until_match)
  String _privacy = 'blur_until_match';

  // Step 3 — guided bio prompts
  static const _prompts = [
    ('first_year', 'My ideal first year of marriage looks like…'),
    ('deen_consistent', 'The deen practice I am most consistent in…'),
    ('looking_for', 'What I am looking for in a spouse…'),
  ];
  final _promptCtrls =
      List.generate(3, (_) => TextEditingController(), growable: false);

  // Step 4 — preferences
  RangeValues _ageRange = const RangeValues(21, 35);
  bool _acceptDivorced = true;
  bool _acceptWidowed = true;
  bool _acceptChildren = true;
  bool _relocationRequired = false;

  // Step 5 — wali
  final _waliName = TextEditingController();
  String? _waliRelationship;
  final _waliPhone = TextEditingController();

  static const _minPromptChars = 40;

  bool get _photosOk => _photos.isNotEmpty;
  bool get _promptsOk => _promptCtrls
      .every((c) => c.text.trim().length >= _minPromptChars);
  bool get _waliValid =>
      _waliName.text.trim().length >= 3 &&
      _waliRelationship != null &&
      RegExp(r'^[6-9]\d{9}$').hasMatch(_waliPhone.text.trim());
  bool get _waliEmpty =>
      _waliName.text.trim().isEmpty &&
      _waliPhone.text.trim().isEmpty &&
      _waliRelationship == null;

  void _next() => setState(() => _step++);

  Future<void> _addPhotos() async {
    if (_photos.length >= 6) return;
    final picked = await ImagePicker()
        .pickMultiImage(maxWidth: 1600, imageQuality: 88);
    if (picked.isNotEmpty) {
      setState(() {
        for (final img in picked) {
          if (_photos.length < 6) _photos.add(img);
        }
      });
    }
  }

  Future<void> _finish({required bool withWali}) async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(applicationRepositoryProvider);
      final paths = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        paths.add(await repo.uploadProfilePhoto(File(_photos[i].path), i));
      }
      await repo.saveProfileBuilder(
        photoPaths: paths,
        photoPrivacy: _privacy,
        bioPrompts: [
          for (var i = 0; i < _prompts.length; i++)
            {
              'promptId': _prompts[i].$1,
              'answer': _promptCtrls[i].text.trim(),
            },
        ],
        preferences: {
          'ageMin': _ageRange.start.round(),
          'ageMax': _ageRange.end.round(),
          'acceptDivorced': _acceptDivorced,
          'acceptWidowed': _acceptWidowed,
          'acceptChildren': _acceptChildren,
          'relocationRequired': _relocationRequired,
        },
        wali: withWali && _waliValid
            ? {
                'name': _waliName.text.trim(),
                'relationship': _waliRelationship,
                'phone': '+91${_waliPhone.text.trim()}',
                'permissionLevel': 'notify',
                'verified': false,
              }
            : null,
      );
      if (mounted) context.go('/home');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not save your profile. Please try again.',
                style: AppType.inter(13))));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: switch (_step) {
        1 => _photosStep(),
        2 => _privacyStep(),
        3 => _promptsStep(),
        4 => _preferencesStep(),
        _ => _waliStep(),
      },
    );
  }

  Widget _photosStep() => StepScaffold(
        step: 1,
        totalSteps: _totalSteps,
        eyebrow: 'Your profile · Photos',
        title: 'Add your photos',
        intro: 'At least one, up to six — you can select several at once. '
            'Your photos stay private: they are only revealed to a match '
            'when you choose to. You set that on the next step.',
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: .8,
            children: [
              for (var i = 0; i < _photos.length; i++)
                Stack(fit: StackFit.expand, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child:
                        Image.file(File(_photos[i].path), fit: BoxFit.cover),
                  ),
                  if (i == 0)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        color: DarkTokens.bg.withOpacity(.75),
                        child: Text('PRIMARY',
                            style: AppType.inter(9,
                                weight: FontWeight.w600,
                                color: DarkTokens.gold)),
                      ),
                    ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: InkWell(
                      onTap: () => setState(() => _photos.removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: DarkTokens.bg.withOpacity(.75),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.close,
                            size: 14, color: DarkTokens.ivory),
                      ),
                    ),
                  ),
                ]),
              if (_photos.length < 6)
                InkWell(
                  onTap: _addPhotos,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border:
                          Border.all(color: DarkTokens.hairline(.45)),
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const DiamondBullet(size: 8),
                          const SizedBox(height: 8),
                          Text('Add',
                              style: AppType.inter(12,
                                  color: DarkTokens.muted())),
                        ]),
                  ),
                ),
            ],
          ),
        ],
        onNext: _photosOk ? _next : null,
      );

  Widget _privacyStep() => StepScaffold(
        step: 2,
        totalSteps: _totalSteps,
        eyebrow: 'Your profile · Privacy',
        title: 'Who sees your photos?',
        intro: 'Changeable anytime. Haya is the default here, not an option '
            'buried in settings.',
        children: [
          OptionList(
            options: const [
              Choice('blur_until_match', 'Blurred until we match',
                  note: 'Matches see a soft silhouette; photos reveal on '
                      'mutual interest. The Ikhlaas default.'),
              Choice('visible', 'Visible to my daily matches',
                  note: 'Only people in your curated batch — never a public '
                      'gallery.'),
              Choice('request_only', 'Private — I approve every reveal',
                  note: 'Hidden even after matching until you grant it, '
                      'revocable anytime.'),
            ],
            selected: _privacy,
            onSelect: (v) => setState(() => _privacy = v),
          ),
        ],
        onNext: _next,
      );

  Widget _promptsStep() => StepScaffold(
        step: 3,
        totalSteps: _totalSteps,
        eyebrow: 'Your profile · In your words',
        title: 'Let them meet you',
        intro: 'Three guided prompts — at least $_minPromptChars characters '
            'each.',
        children: [
          for (var i = 0; i < _prompts.length; i++) ...[
            QuestionLabel(_prompts[i].$2),
            TextField(
              controller: _promptCtrls[i],
              onChanged: (_) => setState(() {}),
              maxLines: 3,
              style: AppType.inter(14.5, color: DarkTokens.ivory, height: 1.6),
              cursorColor: DarkTokens.gold,
              decoration: InputDecoration(
                enabledBorder: UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: DarkTokens.gold.withOpacity(.5))),
                focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: DarkTokens.gold)),
              ),
            ),
            const SizedBox(height: 6),
            Builder(builder: (_) {
              final len = _promptCtrls[i].text.trim().length;
              return Text(
                  len >= _minPromptChars
                      ? 'Looks good'
                      : '${_minPromptChars - len} more characters needed',
                  style: AppType.inter(11.5, color: DarkTokens.muted()));
            }),
            const SizedBox(height: 14),
          ],
        ],
        onNext: _promptsOk ? _next : null,
      );

  Widget _preferencesStep() => StepScaffold(
        step: 4,
        totalSteps: _totalSteps,
        eyebrow: 'Your profile · Preferences',
        title: 'Who are you open to?',
        intro: 'These shape your daily matches. Openness widens your pool.',
        children: [
          QuestionLabel(
              'Age range: ${_ageRange.start.round()}–${_ageRange.end.round()}'),
          RangeSlider(
            values: _ageRange,
            min: 18,
            max: 60,
            divisions: 42,
            activeColor: DarkTokens.gold,
            inactiveColor: DarkTokens.hairline(),
            onChanged: (v) => setState(() => _ageRange = v),
          ),
          _toggle('Open to divorced', _acceptDivorced,
              (v) => setState(() => _acceptDivorced = v)),
          _toggle('Open to widowed', _acceptWidowed,
              (v) => setState(() => _acceptWidowed = v)),
          _toggle('Open to someone with children', _acceptChildren,
              (v) => setState(() => _acceptChildren = v)),
          _toggle('They must be willing to relocate', _relocationRequired,
              (v) => setState(() => _relocationRequired = v)),
        ],
        onNext: _next,
      );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: AppType.inter(14.5, color: DarkTokens.ivory))),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: value ? 1 : .3,
              child: const DiamondBullet(size: 10),
            ),
          ]),
        ),
      );

  Widget _waliStep() {
    final userDoc = ref.watch(userDocProvider).value;
    final isSister = userDoc?.data()?['gender'] == 'female';
    return StepScaffold(
      step: 5,
      totalSteps: _totalSteps,
      eyebrow: 'Your profile · Wali',
      title: isSister ? 'Your Wali walks with you' : 'Involve a guardian?',
      intro: isSister
          ? 'We strongly encourage every sister to add her Wali — he is '
              'notified as things progress, with the visibility level you '
              'choose. He will receive an introduction when invitations open.'
          : 'Optional for brothers — a father or elder who should be kept '
              'informed as things progress.',
      ctaLabel: 'Save & finish',
      loading: _saving,
      children: [
        UnderlineField(
            label: 'Wali name',
            controller: _waliName,
            onChanged: (_) => setState(() {})),
        const QuestionLabel('Relationship'),
        OptionList(
          options: const [
            Choice('father', 'Father'),
            Choice('brother', 'Brother'),
            Choice('uncle', 'Uncle'),
            Choice('other', 'Other appointed guardian'),
          ],
          selected: _waliRelationship,
          onSelect: (v) => setState(() => _waliRelationship = v),
        ),
        const SizedBox(height: 10),
        UnderlineField(
            label: 'Wali mobile',
            controller: _waliPhone,
            keyboardType: TextInputType.phone,
            prefix: '+91  ',
            hint: '98765 43210',
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 20),
        if (!_waliEmpty && !_waliValid)
          Text('Complete all three Wali fields (valid Indian mobile) — '
              'or clear them to skip.',
              style: AppType.inter(12.5, color: DarkTokens.muted())),
        Center(
          child: QuietLink(
            linkText: isSister ? 'Skip for now' : 'Skip',
            onTap: _saving ? null : () => _finish(withWali: false),
          ),
        ),
      ],
      onNext: _waliValid && !_saving ? () => _finish(withWali: true) : null,
    );
  }
}
