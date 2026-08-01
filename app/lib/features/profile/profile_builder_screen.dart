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

/// Profile builder (PRD §4.1 step 6): photos + privacy mode, appearance,
/// beliefs & family, match preferences, Wali setup.
/// One atomic save at the end → profileComplete → home.
class ProfileBuilderScreen extends ConsumerStatefulWidget {
  const ProfileBuilderScreen({super.key});
  @override
  ConsumerState<ProfileBuilderScreen> createState() =>
      _ProfileBuilderScreenState();
}

class _ProfileBuilderScreenState extends ConsumerState<ProfileBuilderScreen> {
  static const _totalSteps = 6;
  int _step = 1;
  bool _saving = false;

  // Step 1 — photos
  final List<XFile> _photos = [];

  // Step 2 — photo visibility (PRD §4.2: default on_mutual_blur)
  String _privacy = 'on_mutual_blur';

  // Step 3 — appearance
  int? _weightKg;
  bool _weightMetric = true; // kg by default; toggle to lb
  String? _build;
  String? _beard; // brothers
  String? _hijab; // sisters
  final _dressing = TextEditingController();

  // Step 4 — beliefs & family
  String? _aqidah;
  final _islamicPractice = TextEditingController();
  final _scholars = TextEditingController();
  final _aboutFamily = TextEditingController();
  String? _livingArrangement;
  final _lookingForSpouse = TextEditingController();
  final _lookingForFamily = TextEditingController();

  // Step 5 — preferences
  RangeValues _ageRange = const RangeValues(21, 35);
  bool _acceptDivorced = true;
  bool _acceptWidowed = true;
  bool _acceptChildren = true;
  bool _relocationRequired = false;
  bool _openToSpouseAbroad = true; // diaspora open by default (PRD Q11)
  String? _financialExpectation; // own stance → scored as alignment
  String? _spouseWork;
  String? _deenPrefPrayer;
  String? _deenPrefHijabBeard;
  String? _deenPrefRiba;
  RangeValues? _heightRange; // nullable — off unless the user sets it

  // Step 6 — wali
  final _waliName = TextEditingController();
  String? _waliRelationship;
  final _waliPhone = TextEditingController();

  bool get _photosOk => _photos.isNotEmpty;
  bool get _waliValid =>
      _waliName.text.trim().length >= 3 &&
      _waliRelationship != null &&
      RegExp(r'^[6-9]\d{9}$').hasMatch(_waliPhone.text.trim());
  bool get _waliEmpty =>
      _waliName.text.trim().isEmpty &&
      _waliPhone.text.trim().isEmpty &&
      _waliRelationship == null;

  void _next() => setState(() => _step++);

  /// preferences map — new deen/lifestyle preference fields are nullable and
  /// only written when set (an unset preference must not become a filter).
  Map<String, dynamic> _prefsMap() => {
        'ageMin': _ageRange.start.round(),
        'ageMax': _ageRange.end.round(),
        'acceptDivorced': _acceptDivorced,
        'acceptWidowed': _acceptWidowed,
        'acceptChildren': _acceptChildren,
        'relocationRequired': _relocationRequired,
        'openToSpouseAbroad': _openToSpouseAbroad,
        if (_spouseWork != null) 'spouseWorkExpectation': _spouseWork,
        if (_heightRange != null)
          'heightRange': {
            'min': _heightRange!.start.round(),
            'max': _heightRange!.end.round(),
          },
        if (_deenPrefPrayer != null ||
            _deenPrefHijabBeard != null ||
            _deenPrefRiba != null)
          'deenPreference': {
            if (_deenPrefPrayer != null) 'prayer': _deenPrefPrayer,
            if (_deenPrefHijabBeard != null) 'hijabBeard': _deenPrefHijabBeard,
            if (_deenPrefRiba != null) 'ribaStance': _deenPrefRiba,
          },
      };

  Future<void> _addPhotos() async {
    if (_photos.length >= 6) return;
    final picked = await ImagePicker()
        .pickMultiImage(maxWidth: 1200, imageQuality: 78);
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
        photoVisibility: _privacy,
        preferences: _prefsMap(),
        financialExpectation: _financialExpectation,
        weightKg: _weightKg,
        buildType: _build,
        beard: _beard,
        hijab: _hijab,
        dressingStyle: _dressing.text,
        aqidah: _aqidah,
        islamicPractice: _islamicPractice.text,
        scholars: _scholars.text,
        aboutFamily: _aboutFamily.text,
        livingArrangement: _livingArrangement,
        lookingForSpouse: _lookingForSpouse.text,
        lookingForFamily: _lookingForFamily.text,
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
        3 => _appearanceStep(),
        4 => _beliefsFamilyStep(),
        5 => _preferencesStep(),
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
            options: Choices.photoVisibility,
            selected: _privacy,
            onSelect: (v) => setState(() => _privacy = v),
          ),
        ],
        onNext: _next,
      );

  // ---- Step 3 · Appearance (physical descriptors — never skin tone, §0) ----
  Widget _appearanceStep() {
    final isSister = ref.watch(userDocProvider).value?.data()?['gender'] ==
        'female';
    return StepScaffold(
      step: 3,
      totalSteps: _totalSteps,
      eyebrow: 'Your profile · Appearance',
      title: 'A little about you',
      intro: 'Optional, but it helps a match picture you. All curves — never '
          'a measure of worth.',
      children: [
        _weightPicker(),
        const QuestionLabel('Build'),
        OptionList(
            options: Choices.build,
            selected: _build,
            onSelect: (v) => setState(() => _build = v)),
        if (isSister) ...[
          const QuestionLabel('Hijab'),
          OptionList(
              options: Choices.hijab,
              selected: _hijab,
              onSelect: (v) => setState(() => _hijab = v)),
        ] else ...[
          const QuestionLabel('Beard'),
          OptionList(
              options: Choices.beard,
              selected: _beard,
              onSelect: (v) => setState(() => _beard = v)),
        ],
        const QuestionLabel('Describe your dressing (optional)'),
        _freeText(_dressing,
            'e.g. modest and simple — thobe or kurta most days.',
            minLines: 2),
      ],
      onNext: _next,
    );
  }

  // ---- Step 4 · Beliefs, practice & family ----
  Widget _beliefsFamilyStep() => StepScaffold(
        step: 4,
        totalSteps: _totalSteps,
        eyebrow: 'Your profile · Beliefs & family',
        title: 'Your deen and your people',
        children: [
          const QuestionLabel('Aqidah (optional)'),
          OptionList(
              options: Choices.aqidah,
              selected: _aqidah,
              onSelect: (v) => setState(() => _aqidah = v)),
          const QuestionLabel('Describe your Islamic practice'),
          _freeText(_islamicPractice,
              'e.g. I pray in congregation when I can, seek knowledge weekly, '
              'and try to keep good character above all.'),
          const QuestionLabel('Scholars and speakers you listen to'),
          _freeText(_scholars,
              'e.g. names of scholars, teachers or reciters whose approach '
              'you follow.',
              minLines: 2),
          const QuestionLabel('About your family'),
          _freeText(_aboutFamily,
              'e.g. practising household, based in Hyderabad, close-knit.'),
          const QuestionLabel('Living arrangement after marriage'),
          OptionList(
              options: Choices.livingArrangement,
              selected: _livingArrangement,
              onSelect: (v) => setState(() => _livingArrangement = v)),
          const QuestionLabel("What I'm looking for in my spouse"),
          _freeText(_lookingForSpouse,
              'e.g. someone God-conscious, kind, and serious about building '
              'a home on the sunnah.'),
          const QuestionLabel("What I'm looking for in their family"),
          _freeText(_lookingForFamily,
              'e.g. supportive, practising, and welcoming of a new member.',
              minLines: 2),
        ],
        onNext: _next,
      );

  /// Outlined free-text field mirroring the gate's short-answer look.
  Widget _freeText(TextEditingController ctrl, String hint,
          {int minLines = 3}) =>
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: TextField(
          controller: ctrl,
          onChanged: (_) => setState(() {}),
          minLines: minLines,
          maxLines: minLines + 2,
          style: AppType.inter(14.5, color: DarkTokens.ivory, height: 1.6),
          cursorColor: DarkTokens.gold,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                AppType.inter(13.5, color: DarkTokens.muted(.45), height: 1.5),
            contentPadding: const EdgeInsets.all(14),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: BorderSide(color: DarkTokens.gold.withOpacity(.35))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: BorderSide(color: DarkTokens.gold.withOpacity(.8))),
          ),
        ),
      );

  /// Weight with a kg/lb toggle — mirrors the height ft/cm pattern. Stored as
  /// kg (int, single source of truth); lb is display-only.
  Widget _weightPicker() {
    final kg = _weightKg;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text('Weight (optional)',
                style: AppType.inter(12.5, color: DarkTokens.muted()))),
        _weightUnitPill('kg', true),
        const SizedBox(width: 8),
        _weightUnitPill('lb', false),
      ]),
      const SizedBox(height: 4),
      if (_weightMetric)
        _pbDropdown<int>(
            value: kg,
            items: [for (var w = 40; w <= 150; w++) w],
            labelOf: (v) => '$v kg',
            onChanged: (v) => setState(() => _weightKg = v))
      else
        _pbDropdown<int>(
            value: kg == null ? null : (kg * 2.20462).round(),
            items: [for (var w = 90; w <= 330; w++) w],
            labelOf: (v) => '$v lb',
            onChanged: (lb) => setState(
                () => _weightKg = lb == null ? null : (lb / 2.20462).round())),
      if (kg != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('$kg kg (${(kg * 2.20462).round()} lb)',
              style: AppType.inter(13, color: DarkTokens.gold)),
        ),
    ]);
  }

  Widget _weightUnitPill(String label, bool metric) {
    final on = _weightMetric == metric;
    return GestureDetector(
      onTap: () => setState(() => _weightMetric = metric),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: on ? DarkTokens.gold.withOpacity(.12) : null,
          border: Border.all(
              color: on ? DarkTokens.gold : DarkTokens.hairline(.5)),
        ),
        child: Text(label,
            style: AppType.inter(12,
                color: on ? DarkTokens.gold : DarkTokens.muted())),
      ),
    );
  }

  Widget _pbDropdown<T>({
    required T? value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: DarkTokens.gold.withOpacity(.4)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: DarkTokens.bg,
            icon: Icon(Icons.expand_more, color: DarkTokens.muted(.7)),
            hint: Text('Select',
                style: AppType.inter(14, color: DarkTokens.muted(.5))),
            style: AppType.inter(14.5, color: DarkTokens.ivory),
            items: [
              for (final it in items)
                DropdownMenuItem<T>(value: it, child: Text(labelOf(it))),
            ],
            onChanged: onChanged,
          ),
        ),
      );

  Widget _preferencesStep() => StepScaffold(
        step: 5,
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
          _toggle('Open to a spouse living in another country',
              _openToSpouseAbroad,
              (v) => setState(() => _openToSpouseAbroad = v)),

          QuestionLabel(_heightRange == null
              ? 'Preferred height range (optional)'
              : 'Height range: ${_heightRange!.start.round()}–${_heightRange!.end.round()} cm'),
          if (_heightRange == null)
            Align(
              alignment: Alignment.centerLeft,
              child: QuietLink(
                  linkText: 'Set a height range',
                  onTap: () => setState(
                      () => _heightRange = const RangeValues(155, 185))),
            )
          else
            RangeSlider(
              values: _heightRange!,
              min: 140,
              max: 210,
              divisions: 70,
              activeColor: DarkTokens.gold,
              inactiveColor: DarkTokens.hairline(),
              onChanged: (v) => setState(() => _heightRange = v),
            ),

          const SizedBox(height: 10),
          const QuestionLabel('Your own view on provision'),
          Text('Matched as alignment — never an income filter.',
              style: AppType.inter(12, color: DarkTokens.muted())),
          const SizedBox(height: 6),
          OptionList(
              options: Choices.financialExpectation,
              selected: _financialExpectation,
              onSelect: (v) => setState(() => _financialExpectation = v)),

          const QuestionLabel('Would you like your spouse to work? (optional)'),
          OptionList(
              options: Choices.spouseWork,
              selected: _spouseWork,
              onSelect: (v) => setState(() => _spouseWork = v)),

          const QuestionLabel('Deen preferences (optional)'),
          Text('What you\'re looking for — helps us match, never a hard gate.',
              style: AppType.inter(12, color: DarkTokens.muted())),
          const SizedBox(height: 10),
          _prefLabel('Prayer'),
          OptionList(
              options: Choices.deenPrefPrayer,
              selected: _deenPrefPrayer,
              onSelect: (v) => setState(() => _deenPrefPrayer = v)),
          _prefLabel('Hijab / beard'),
          OptionList(
              options: Choices.deenPrefHijabBeard,
              selected: _deenPrefHijabBeard,
              onSelect: (v) => setState(() => _deenPrefHijabBeard = v)),
          _prefLabel('Interest-based debt'),
          OptionList(
              options: Choices.deenPrefRiba,
              selected: _deenPrefRiba,
              onSelect: (v) => setState(() => _deenPrefRiba = v)),
        ],
        onNext: _next,
      );

  Widget _prefLabel(String s) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 2),
        child: Text(s,
            style: AppType.inter(13,
                weight: FontWeight.w500, color: DarkTokens.muted(.85))),
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
      step: 6,
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
