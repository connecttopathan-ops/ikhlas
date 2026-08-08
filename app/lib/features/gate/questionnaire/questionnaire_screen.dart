import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import '../../../providers/application_provider.dart';
import '../id_capture_screen.dart';
import '../location_data.dart';
import '../selfie_capture_screen.dart';
import 'questionnaire_models.dart';
import 'questionnaire_widgets.dart';

/// Screening questionnaire — sections A–F as a stepped flow (PRD v1.2 §4.1:
/// one question-group per screen, Fraunces headers, gold accents). Answers
/// stage locally; a single submission writes the user profile + the immutable
/// application doc. Section F is non-gating and lands in the profile only.
class QuestionnaireScreen extends ConsumerStatefulWidget {
  const QuestionnaireScreen({super.key});
  @override
  ConsumerState<QuestionnaireScreen> createState() =>
      _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends ConsumerState<QuestionnaireScreen> {
  static const _totalSteps = 11;
  int _step = 1;
  final _a = QuestionnaireAnswers();
  bool _submitting = false;
  XFile? _selfie;
  // Government-ID captured DURING the application (single admin decision covers
  // eligibility + ID together). Reviewed inline by a moderator; never public.
  String? _idType; // 'passport' | 'aadhaar'
  XFile? _idImage;
  bool _appSubmitted = false; // guard: applications/{uid} is create-once

  // Text controllers for free-text fields (kept alive across steps).
  late final _languages = TextEditingController();
  late final _ethnicity = TextEditingController();
  late final _health = TextEditingController();
  late final _sect = TextEditingController();
  late final _madhhab = TextEditingController();
  late final _town = TextEditingController();
  late final _cityText = TextEditingController(); // fallback where no city list
  late final _deen = TextEditingController();


  @override
  void initState() {
    super.initState();
    // Geo-locale guess for location — a default the user can override.
    final cc = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    final guess = _countryFromCode(cc);
    if (guess != null) {
      _a.residenceCountry = guess;
      _a.nationality = guess;
    }
  }

  static String? _countryFromCode(String? code) {
    const m = {
      'IN': 'India', 'PK': 'Pakistan', 'BD': 'Bangladesh', 'AE': 'United Arab Emirates',
      'SA': 'Saudi Arabia', 'QA': 'Qatar', 'KW': 'Kuwait', 'BH': 'Bahrain',
      'OM': 'Oman', 'US': 'United States', 'GB': 'United Kingdom', 'CA': 'Canada',
      'AU': 'Australia', 'MY': 'Malaysia', 'ID': 'Indonesia', 'TR': 'Turkey',
      'LK': 'Sri Lanka', 'SG': 'Singapore', 'ZA': 'South Africa', 'NG': 'Nigeria',
    };
    final name = m[code];
    return (name != null && kCountries.contains(name)) ? name : null;
  }

  @override
  void dispose() {
    for (final c in [
      _languages, _ethnicity, _health, _sect, _madhhab, _town, _cityText,
      _deen
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _next() => setState(() => _step++);

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final repo = ref.read(applicationRepositoryProvider);
      // ID-first, so a failure retries cleanly before the immutable
      // application doc is created: selfie → ID → application.
      final path = await repo.uploadSelfie(File(_selfie!.path));
      final idBytes = await File(_idImage!.path).readAsBytes();
      await repo.submitIdDoc(
        type: _idType!,
        imageBase64: base64Encode(idBytes),
      );
      if (!_appSubmitted) {
        await repo.submitApplication(_a, selfieStoragePath: path);
        _appSubmitted = true;
      }
      if (mounted) context.go('/review-wait');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not submit your application. Please try again.',
                style: AppType.inter(13))));
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _captureSelfie() async {
    final shot = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(builder: (_) => const SelfieCaptureScreen()),
    );
    if (shot != null) setState(() => _selfie = shot);
  }

  // Camera path — the framed capture screen with the document guide.
  Future<void> _captureId() async {
    if (_idType == null) return;
    final shot = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(builder: (_) => IdCaptureScreen(docType: _idType!)),
    );
    if (shot != null) setState(() => _idImage = shot);
  }

  // Device path — pick an existing photo from the gallery. Same OCR + face
  // pipeline as the camera path; uploads just miss the alignment guide, so
  // they may OCR slightly worse (acceptable — more manual correction).
  Future<void> _uploadId() async {
    if (_idType == null) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      imageQuality: 88,
    );
    if (file != null) setState(() => _idImage = file);
  }

  // DOB as three plain dropdowns (day / month / year) — far clearer than a
  // calendar you must page ~24 years back for a birthdate.
  int? _dobD, _dobM, _dobY;
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  void _syncDob() {
    if (_dobD != null && _dobM != null && _dobY != null) {
      final maxDay = DateUtils.getDaysInMonth(_dobY!, _dobM!);
      _a.dob = DateTime(_dobY!, _dobM!, _dobD!.clamp(1, maxDay));
    } else {
      _a.dob = null;
    }
  }

  /// True when a full date is chosen but the person is under 18.
  bool get _dobUnder18 {
    final dob = _a.dob;
    if (dob == null) return false;
    final now = DateTime.now();
    return dob.isAfter(DateTime(now.year - 18, now.month, now.day));
  }

  /// A single tappable field that opens a wheel picker — reads as one
  /// intentional control rather than three bare dropdowns.
  Widget _dobPicker() {
    final dob = _a.dob;
    final chosen = dob != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: _openDobSheet,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
                color: DarkTokens.gold.withOpacity(chosen ? .75 : .4)),
          ),
          child: Row(children: [
            Icon(Icons.cake_outlined, size: 18, color: DarkTokens.muted(.75)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                chosen
                    ? '${dob.day} ${_monthNames[dob.month - 1]} ${dob.year}'
                    : 'Select your date of birth',
                style: AppType.inter(15.5,
                    color: chosen ? DarkTokens.ivory : DarkTokens.muted(.55)),
              ),
            ),
            Icon(Icons.expand_more, size: 22, color: DarkTokens.muted(.7)),
          ]),
        ),
      ),
      if (_dobUnder18)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('You must be 18 or older to apply.',
              style: AppType.inter(12.5, color: DarkTokens.gold)),
        ),
    ]);
  }

  /// Themed bottom sheet with three spinning wheels (day / month / year).
  /// Haptic tick per detent; a single gold "Set date" confirms.
  Future<void> _openDobSheet() async {
    final now = DateTime.now();
    final maxYear = now.year - 18; // 18+ gate — no younger year offered
    final minYear = now.year - 80;
    final years = [for (var y = maxYear; y >= minYear; y--) y];

    // Working selection, seeded from the current value or sensible defaults.
    var tmpDay = _dobD ?? _a.dob?.day ?? 1;
    var tmpMonth = _dobM ?? _a.dob?.month ?? 1;
    var tmpYear = _dobY ?? _a.dob?.year ?? (maxYear - 7); // ~25 by default

    final dayCtrl = FixedExtentScrollController(initialItem: tmpDay - 1);
    final monthCtrl = FixedExtentScrollController(initialItem: tmpMonth - 1);
    final yearCtrl =
        FixedExtentScrollController(initialItem: years.indexOf(tmpYear).clamp(0, years.length - 1));

    Widget wheel({
      required FixedExtentScrollController controller,
      required int count,
      required String Function(int) labelOf,
      required ValueChanged<int> onChanged,
      int flex = 1,
    }) =>
        Expanded(
          flex: flex,
          child: CupertinoPicker.builder(
            scrollController: controller,
            itemExtent: 40,
            squeeze: 1.1,
            diameterRatio: 1.25,
            magnification: 1.05,
            useMagnifier: true,
            selectionOverlay: Container(
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal:
                      BorderSide(color: DarkTokens.gold.withOpacity(.35)),
                ),
              ),
            ),
            childCount: count,
            itemBuilder: (_, i) => Center(
              child: Text(labelOf(i),
                  style: AppType.inter(17, color: DarkTokens.ivory)),
            ),
            onSelectedItemChanged: (i) {
              HapticFeedback.selectionClick();
              onChanged(i);
            },
          ),
        );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: DarkTokens.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: DarkTokens.hairline(.4)),
        ),
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).padding.bottom + 12, top: 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: DarkTokens.hairline(),
                borderRadius: BorderRadius.circular(2)),
          ),
          Text('Date of birth',
              style: AppType.fraunces(20, color: DarkTokens.ivory)),
          const SizedBox(height: 4),
          Text('You must be 18 or older',
              style: AppType.inter(12.5, color: DarkTokens.muted(.7))),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpace.screenMargin),
              child: Row(children: [
                wheel(
                    controller: dayCtrl,
                    count: 31,
                    flex: 3,
                    labelOf: (i) => '${i + 1}',
                    onChanged: (i) => tmpDay = i + 1),
                wheel(
                    controller: monthCtrl,
                    count: 12,
                    flex: 5,
                    labelOf: (i) => _monthNames[i],
                    onChanged: (i) => tmpMonth = i + 1),
                wheel(
                    controller: yearCtrl,
                    count: years.length,
                    flex: 4,
                    labelOf: (i) => '${years[i]}',
                    onChanged: (i) => tmpYear = years[i]),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpace.screenMargin),
            child: PrimaryCta(
                label: 'Set date',
                onPressed: () {
                  // Clamp the day to the chosen month/year (e.g. 31 → Feb).
                  final maxDay = DateUtils.getDaysInMonth(tmpYear, tmpMonth);
                  setState(() {
                    _dobD = tmpDay.clamp(1, maxDay);
                    _dobM = tmpMonth;
                    _dobY = tmpYear;
                    _syncDob();
                  });
                  Navigator.pop(ctx);
                }),
          ),
        ]),
      ),
    );

    dayCtrl.dispose();
    monthCtrl.dispose();
    yearCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: switch (_step) {
        1 => _sectionA(),
        2 => _sectionB(),
        3 => _sectionC1(),
        4 => _sectionC2(),
        5 => _sectionC3(),
        6 => _sectionC4(),
        7 => _sectionD2(),
        8 => _sectionE(),
        9 => _sectionF(),
        10 => _selfieStep(),
        _ => _idStep(),
      },
    );
  }

  // ---- A. Readiness ----
  Widget _sectionA() => StepScaffold(
        step: 1,
        totalSteps: _totalSteps,
        eyebrow: 'Section A · Readiness',
        title: 'Where are you on the path to nikah?',
        children: [
          const QuestionLabel('When do you intend to marry, insha\'Allah?'),
          OptionList(
              options: Choices.timeframe,
              selected: _a.timeframe,
              onSelect: (v) => setState(() => _a.timeframe = v)),
          const QuestionLabel(
              'Are you financially and personally prepared to marry?'),
          OptionList(
              options: Choices.financiallyReady,
              selected: _a.financiallyReady,
              onSelect: (v) => setState(() => _a.financiallyReady = v)),
          const QuestionLabel('Have you spoken to your family about marriage?'),
          OptionList(
              options: Choices.familyAware,
              selected: _a.familyAware,
              onSelect: (v) => setState(() => _a.familyAware = v)),
        ],
        onNext: _a.sectionAComplete ? _next : null,
      );

  // ---- B. Deen profile ----
  Widget _sectionB() => StepScaffold(
        step: 2,
        totalSteps: _totalSteps,
        eyebrow: 'Section B · Deen',
        title: 'Your relationship with the deen',
        intro: 'Answer honestly — sincerity is the standard here, '
            'not perfection.',
        children: [
          const QuestionLabel('How consistent is your salah?'),
          OptionList(
              options: Choices.prayer,
              selected: _a.prayer,
              onSelect: (v) => setState(() => _a.prayer = v)),
          const SizedBox(height: 10),
          UnderlineField(
              label: 'Sect (optional)',
              controller: _sect,
              hint: 'e.g. Sunni',
              onChanged: (v) => _a.sect = v),
          const SizedBox(height: 20),
          UnderlineField(
              label: 'Madhhab (optional)',
              controller: _madhhab,
              hint: 'e.g. Hanafi',
              onChanged: (v) => _a.madhhab = v),
        ],
        onNext: _a.sectionBComplete ? _next : null,
      );

  // ---- C1. About you ----
  Widget _sectionC1() => StepScaffold(
        step: 3,
        totalSteps: _totalSteps,
        eyebrow: 'Section C · About you',
        title: 'The essentials',
        children: [
          const QuestionLabel('I am a'),
          OptionList(
              options: Choices.gender,
              selected: _a.gender,
              onSelect: (v) => setState(() => _a.gender = v)),
          const QuestionLabel('Date of birth (18+)'),
          _dobPicker(),
          const QuestionLabel('Marital status'),
          OptionList(
              options: Choices.maritalStatus,
              selected: _a.maritalStatus,
              onSelect: (v) => setState(() {
                    _a.maritalStatus = v;
                    // Never-married applicants can't have children in this
                    // pool, so the question is skipped and set to false.
                    if (v == 'never_married') _a.hasChildren = false;
                  })),
          // Children question only applies to divorced/widowed applicants.
          if (_a.maritalStatus == 'divorced' ||
              _a.maritalStatus == 'widowed') ...[
            const QuestionLabel('Do you have children?'),
            OptionList(
                options: Choices.yesNo,
                selected: _a.hasChildren == null
                    ? null
                    : (_a.hasChildren! ? 'yes' : 'no'),
                onSelect: (v) => setState(() => _a.hasChildren = v == 'yes')),
          ],
          const SizedBox(height: 18),
          InkWell(
            onTap: () => setState(() => _a.revert = !_a.revert),
            child: Row(children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _a.revert ? 1 : .35,
                child: const DiamondBullet(size: 8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('I am a revert to Islam, alhamdulillah (optional)',
                    style: AppType.inter(13.5, color: DarkTokens.muted(.7))),
              ),
            ]),
          ),
        ],
        onNext: _a.sectionC1Complete && !_dobUnder18 ? _next : null,
      );

  // ---- C2. Life & roots ----
  Widget _sectionC2() => StepScaffold(
        step: 4,
        totalSteps: _totalSteps,
        eyebrow: 'Section C · Life & roots',
        title: 'Where life has placed you',
        children: [
          // Nationality first (where you're from), then the residence block
          // (where you live) — grouped so the screen reads top-to-bottom
          // instead of interleaving the two.
          _dropdown(
              label: 'Nationality — where you are from',
              value: _a.nationality.isEmpty ? null : _a.nationality,
              items: kCountries,
              onChanged: (v) => setState(() => _a.nationality = v ?? '')),
          const SizedBox(height: 12),
          _dropdown(
              label: 'Where you currently live — country',
              value: _a.residenceCountry.isEmpty ? null : _a.residenceCountry,
              items: kCountries,
              onChanged: (v) => setState(() {
                    _a.residenceCountry = v ?? '';
                    _a.residenceState = '';
                    _a.residenceCity = '';
                    _cityText.clear();
                  })),
          if (statesFor(_a.residenceCountry).isNotEmpty)
            _dropdown(
                label: 'State / region',
                value: _a.residenceState.isEmpty ? null : _a.residenceState,
                items: statesFor(_a.residenceCountry),
                onChanged: (v) => setState(() {
                      _a.residenceState = v ?? '';
                      _a.residenceCity = '';
                      _cityText.clear();
                    })),
          // India: city/town is FREE TEXT — Indian cities are too numerous and
          // inconsistently spelled for a usable dropdown. Everywhere else the
          // dropdown stays so the data remains matchable. Country and state
          // are dropdowns for everyone.
          if (_a.residenceCountry != 'India' &&
              citiesFor(_a.residenceCountry, _a.residenceState).isNotEmpty)
            _dropdown(
                label: 'City',
                value: _a.residenceCity.isEmpty ? null : _a.residenceCity,
                items: citiesFor(_a.residenceCountry, _a.residenceState),
                onChanged: (v) => setState(() => _a.residenceCity = v ?? ''))
          else
            UnderlineField(
                label: _a.residenceCountry == 'India' ? 'City / town' : 'City',
                controller: _cityText,
                hint: 'e.g. Hyderabad',
                onChanged: (v) => setState(() => _a.residenceCity = v)),
          const SizedBox(height: 12),
          UnderlineField(
              label: 'Town / area (optional)',
              controller: _town,
              onChanged: (v) => setState(() => _a.residenceTown = v)),
          const QuestionLabel('Your residency status where you live'),
          OptionList(
              options: Choices.residencyStatus,
              selected: _a.residencyStatus,
              onSelect: (v) => setState(() => _a.residencyStatus = v)),
          const QuestionLabel('Willing to relocate for the right match?'),
          OptionList(
              options: Choices.yesNo,
              selected: _a.willingToRelocate == null
                  ? null
                  : (_a.willingToRelocate! ? 'yes' : 'no'),
              onSelect: (v) =>
                  setState(() => _a.willingToRelocate = v == 'yes')),
          const SizedBox(height: 10),
          UnderlineField(
              label: 'Languages you speak',
              controller: _languages,
              hint: 'e.g. Urdu, Hindi, English',
              onChanged: (v) => setState(() => _a.languages = v)),
          const SizedBox(height: 20),
          UnderlineField(
              label: 'Ethnicity (optional)',
              controller: _ethnicity,
              onChanged: (v) => _a.ethnicity = v),
        ],
        onNext: _a.sectionC2Complete ? _next : null,
      );

  // ---- C3. Education & work ----
  Widget _sectionC3() => StepScaffold(
        step: 5,
        totalSteps: _totalSteps,
        eyebrow: 'Section C · Education & work',
        title: 'What you do',
        children: [
          const QuestionLabel('Highest education'),
          OptionList(
              options: Choices.education,
              selected: _a.education,
              onSelect: (v) => setState(() => _a.education = v)),
          const QuestionLabel('Profession'),
          OptionList(
              options: Choices.profession,
              selected: _a.profession,
              onSelect: (v) => setState(() => _a.profession = v)),
          const QuestionLabel('Annual income band'),
          Text(
              'Private — never shown on your match card and never used to rank. '
              'Shared only at the Family Stage.',
              style: AppType.inter(12.5, color: DarkTokens.muted(), height: 1.5)),
          const SizedBox(height: 6),
          OptionList(
              options: Choices.incomeBand,
              selected: _a.incomeBand,
              onSelect: (v) => setState(() => _a.incomeBand = v)),
        ],
        onNext: _a.sectionC3Complete ? _next : null,
      );

  // ---- C4. Family & background ----
  Widget _sectionC4() => StepScaffold(
        step: 6,
        totalSteps: _totalSteps,
        eyebrow: 'Section C · Family & background',
        title: 'Your family context',
        children: [
          const QuestionLabel('Family type'),
          OptionList(
              options: Choices.familyType,
              selected: _a.familyType,
              onSelect: (v) => setState(() => _a.familyType = v)),
          const QuestionLabel('How practising is your family?'),
          OptionList(
              options: Choices.familyReligiosity,
              selected: _a.familyReligiosity,
              onSelect: (v) => setState(() => _a.familyReligiosity = v)),
          const QuestionLabel('Any health condition to disclose? (optional)'),
          Text(
              'Shared only once a conversation opens, never on your match card. '
              'Honesty before nikah is an amanah.',
              style: AppType.inter(12.5, color: DarkTokens.muted(), height: 1.5)),
          const SizedBox(height: 8),
          UnderlineField(
              label: 'Health disclosure (optional)',
              controller: _health,
              hint: 'Leave blank if none',
              onChanged: (v) => _a.healthDisclosure = v),
        ],
        onNext: _a.sectionC4Complete ? _next : null,
      );

  // ---- D1 / D2. Short answers ----
  Widget _shortAnswer({
    required int step,
    required String title,
    required String prompt,
    required TextEditingController ctrl,
    required void Function(String) onChanged,
    required bool complete,
    required int lengthNow,
  }) =>
      StepScaffold(
        step: step,
        totalSteps: _totalSteps,
        eyebrow: 'Section D · In your words',
        title: title,
        intro: prompt,
        children: [
          TextField(
            controller: ctrl,
            onChanged: (v) => setState(() => onChanged(v)),
            maxLines: 7,
            style: AppType.inter(15, color: DarkTokens.ivory, height: 1.65),
            cursorColor: DarkTokens.gold,
            decoration: InputDecoration(
              hintText: 'Write from the heart.',
              hintStyle: AppType.inter(14, color: DarkTokens.muted(.4)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  borderSide:
                      BorderSide(color: DarkTokens.gold.withOpacity(.35))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  borderSide:
                      BorderSide(color: DarkTokens.gold.withOpacity(.8))),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            complete
                ? 'JazakAllah khair — that is enough, though you may write more.'
                : '${QuestionnaireAnswers.shortAnswerMin - lengthNow} more characters needed',
            style: AppType.inter(12, color: DarkTokens.muted()),
          ),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 15, color: DarkTokens.muted(.7)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This appears on your profile for potential matches to read, '
                'and is used by our team for review.',
                style: AppType.inter(12, color: DarkTokens.muted(), height: 1.5),
              ),
            ),
          ]),
        ],
        onNext: complete ? _next : null,
      );

  Widget _sectionD2() => _shortAnswer(
        step: 7,
        title: 'Describe your relationship with deen',
        prompt: 'What part of your deen are you most consistent in, and what '
            'are you still working on?',
        ctrl: _deen,
        onChanged: (v) => _a.deenRelationship = v,
        complete: _a.sectionD2Complete,
        lengthNow: _a.deenRelationship.trim().length,
      );

  // ---- Shared input: tap-to-open sheet selector (replaces bare dropdowns) ----
  /// A labelled field that opens a themed picker sheet — one intentional
  /// control, consistent with the date-of-birth picker, instead of a raw
  /// Material dropdown. Long lists (e.g. countries) get a search box.
  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final chosen = value != null && value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppType.inter(12.5, color: DarkTokens.muted())),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _openSelectSheet(
              title: label, value: value, items: items, onChanged: onChanged),
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(
                  color: DarkTokens.gold.withOpacity(chosen ? .75 : .4)),
            ),
            child: Row(children: [
              Expanded(
                child: Text(chosen ? value : 'Select…',
                    style: AppType.inter(15.5,
                        color:
                            chosen ? DarkTokens.ivory : DarkTokens.muted(.55))),
              ),
              Icon(Icons.expand_more, size: 22, color: DarkTokens.muted(.7)),
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _openSelectSheet({
    required String title,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) async {
    final searchable = items.length > 12;
    final search = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(builder: (ctx, setSheet) {
          final q = search.text.trim().toLowerCase();
          final filtered = q.isEmpty
              ? items
              : items.where((e) => e.toLowerCase().contains(q)).toList();
          return ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * .78),
            child: Container(
              decoration: BoxDecoration(
                color: DarkTokens.bg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: DarkTokens.hairline(.4)),
              ),
              padding: const EdgeInsets.only(top: 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: DarkTokens.hairline(),
                      borderRadius: BorderRadius.circular(2)),
                ),
                Text(title,
                    style: AppType.fraunces(19, color: DarkTokens.ivory)),
                const SizedBox(height: 10),
                if (searchable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.screenMargin, 0, AppSpace.screenMargin, 6),
                    child: TextField(
                      controller: search,
                      autofocus: true,
                      onChanged: (_) => setSheet(() {}),
                      style: AppType.inter(15, color: DarkTokens.ivory),
                      cursorColor: DarkTokens.gold,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search…',
                        hintStyle:
                            AppType.inter(15, color: DarkTokens.muted(.5)),
                        prefixIcon: Icon(Icons.search,
                            size: 20, color: DarkTokens.muted(.7)),
                        enabledBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: DarkTokens.hairline(.5))),
                        focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: DarkTokens.gold)),
                      ),
                    ),
                  ),
                Flexible(
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text('No matches.',
                              style: AppType.inter(14,
                                  color: DarkTokens.muted())),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final it = filtered[i];
                            final sel = it == value;
                            return InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onChanged(it);
                                Navigator.pop(ctx);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpace.screenMargin,
                                    vertical: 14),
                                child: Row(children: [
                                  Expanded(
                                    child: Text(it,
                                        style: AppType.inter(15.5,
                                            color: sel
                                                ? DarkTokens.gold
                                                : DarkTokens.ivory)),
                                  ),
                                  if (sel)
                                    Icon(Icons.check,
                                        size: 18, color: DarkTokens.gold),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
                SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
              ]),
            ),
          );
        }),
      ),
    );
    search.dispose();
  }

  // ---- E. Creed & finance ----
  Widget _sectionE() => StepScaffold(
        step: 8,
        totalSteps: _totalSteps,
        eyebrow: 'Section E · Creed & finance',
        title: 'Affirmations',
        intro: 'These reflect the standard of the Ikhlaas pool. '
            'Answer truthfully before Allah.',
        children: [
          // E1 Tawhid. The clarifier is fiqh-sensitive (targets istighatha, not
          // grave visitation) and flagged for scholarly sign-off — do NOT edit.
          const AffirmationPrompt(
            'I worship Allah alone, and call upon Him alone.',
            clarifier:
                "I don't pray to, or seek help from, the dead, saints, or graves.",
          ),
          OptionList(
              options: Choices.e1,
              selected: _a.e1Tawhid,
              onSelect: (v) => setState(() => _a.e1Tawhid = v)),
          // E2 Riba belief.
          const AffirmationPrompt(
            'I believe riba (interest) is haram.',
            clarifier:
                'This includes conventional interest-based home, car, and '
                'personal loans, and credit-card interest.',
          ),
          OptionList(
              options: Choices.e1, // same affirm / not_affirm pair
              selected: _a.e2Riba,
              onSelect: (v) => setState(() => _a.e2Riba = v)),
          // E3 Debt situation. E3(b) carries the honest-disclosure badge (note
          // lives on the option in Choices.e3).
          const AffirmationPrompt('My situation with interest-based debt:'),
          OptionList(
              options: Choices.e3,
              selected: _a.e3RibaPractice,
              onSelect: (v) => setState(() => _a.e3RibaPractice = v)),
          // E4 Income. Label "Not sure"; stored config value stays "uncertain".
          const AffirmationPrompt('Is your main income from a halal source?'),
          OptionList(
              options: Choices.e4,
              selected: _a.e4IncomeSource,
              onSelect: (v) => setState(() => _a.e4IncomeSource = v)),
        ],
        onNext: _a.sectionEComplete ? _next : null,
      );

  // ---- F. Deen Detail (NON-GATING — matching signal only) ----
  Widget _sectionF() => StepScaffold(
        step: 9,
        totalSteps: _totalSteps,
        eyebrow: 'Section F · Deen detail',
        title: 'A little more, so we match you well',
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DarkTokens.gold.withOpacity(.08),
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: DarkTokens.gold.withOpacity(.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 16, color: DarkTokens.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    'This helps us match you. None of it affects your '
                    'application.',
                    style: AppType.inter(13,
                        color: DarkTokens.ivory, height: 1.5)),
              ),
            ]),
          ),
          const QuestionLabel('Your Quran recitation'),
          OptionList(
              options: Choices.quranEngagement,
              selected: _a.quranEngagement,
              onSelect: (v) => setState(() => _a.quranEngagement = v)),
          const QuestionLabel('Quran memorization'),
          OptionList(
              options: Choices.quranMemorization,
              selected: _a.quranMemorization,
              onSelect: (v) => setState(() => _a.quranMemorization = v)),
          const QuestionLabel('Islamic study'),
          OptionList(
              options: Choices.islamicStudy,
              selected: _a.islamicStudy,
              onSelect: (v) => setState(() => _a.islamicStudy = v)),
          const QuestionLabel('Fasting'),
          OptionList(
              options: Choices.fasting,
              selected: _a.fasting,
              onSelect: (v) => setState(() => _a.fasting = v)),
        ],
        onNext: _a.sectionFComplete ? _next : null,
      );

  // ---- Verification selfie (manual capture; liveness SDK later) ----
  Widget _selfieStep() => StepScaffold(
        step: 10,
        totalSteps: _totalSteps,
        eyebrow: 'Verification · 1 of 2',
        title: 'One honest photo',
        intro: 'A quick selfie confirms you are you. It is seen only by '
            'our review team — never by other members.',
        ctaLabel: 'Continue',
        children: [
          Center(
            child: InkWell(
              onTap: _captureSelfie,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Container(
                width: 220,
                height: 280,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(
                      color: DarkTokens.gold
                          .withOpacity(_selfie == null ? .45 : .9),
                      width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: _selfie == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const GirihMark(size: 56, opacity: .8),
                          const SizedBox(height: 18),
                          Text('Tap to take your selfie',
                              style: AppType.inter(13.5,
                                  color: DarkTokens.muted(.7))),
                        ],
                      )
                    : Image.file(File(_selfie!.path), fit: BoxFit.cover),
              ),
            ),
          ),
          if (_selfie != null) ...[
            const SizedBox(height: 14),
            Center(
              child: QuietLink(
                  linkText: 'Retake photo', onTap: _captureSelfie),
            ),
          ],
          const SizedBox(height: 22),
          Text(
            'Next you will add one government-ID for a one-time identity '
            'check. Both photos are seen only by our review team.',
            style: AppType.inter(12.5, color: DarkTokens.muted(), height: 1.6),
          ),
        ],
        onNext: _selfie != null ? _next : null,
      );

  // ---- Government-ID (captured with the application; reviewed inline by a
  // moderator alongside eligibility — a single decision). Image goes only to
  // the admin-only quarantine bucket; never public, purged if declined. ----
  Widget _idStep() => StepScaffold(
        step: 11,
        totalSteps: _totalSteps,
        eyebrow: 'Verification · 2 of 2',
        title: 'Verify your identity',
        intro: 'One clear photo of a government-ID. It is used only to confirm '
            'you are a real person, seen only by our review team, and deleted '
            'if your application is not accepted.',
        ctaLabel: 'Submit my application',
        loading: _submitting,
        children: [
          const QuestionLabel('Which document will you use?'),
          OptionList(
              options: const [
                Choice('passport', 'Passport'),
                Choice('aadhaar', 'Aadhaar'),
              ],
              selected: _idType,
              onSelect: (v) => setState(() {
                    // Changing the document invalidates a photo framed for the
                    // previous one (different aspect ratio / guide).
                    if (v != _idType) _idImage = null;
                    _idType = v;
                  })),
          const SizedBox(height: 20),
          // Preview / target zone — full width so it never reads cramped.
          // The cue names the correct side: OCR + face-match need the front
          // (photo + name), not the Aadhaar back (address).
          Container(
            width: double.infinity,
            height: 210,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(
                  color: DarkTokens.gold
                      .withOpacity(_idImage == null ? .45 : .9),
                  width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: _idImage == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.badge_outlined,
                          size: 40,
                          color: DarkTokens.muted(_idType == null ? .3 : .7)),
                      const SizedBox(height: 12),
                      Text(
                          _idType == null
                              ? 'Choose a document first'
                              : 'A clear photo of your ${_idType == 'passport' ? 'passport' : 'Aadhaar'}',
                          textAlign: TextAlign.center,
                          style: AppType.inter(13,
                              color: DarkTokens.muted(.7))),
                      if (_idType != null) ...[
                        const SizedBox(height: 5),
                        Text(
                            _idType == 'passport'
                                ? 'The photo page.'
                                : 'Front side — the one with your photo.',
                            textAlign: TextAlign.center,
                            style: AppType.inter(12.5,
                                weight: FontWeight.w500,
                                color: DarkTokens.gold.withOpacity(.9))),
                      ],
                    ],
                  )
                : Image.file(File(_idImage!.path), fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),
          // Capture is the primary path (the overlay guide gives better OCR);
          // device upload is the quiet fallback beneath it.
          _idActionButton(
            _idImage == null ? 'Take photo' : 'Retake photo',
            Icons.photo_camera_outlined,
            _idType == null || _submitting ? null : _captureId,
          ),
          const SizedBox(height: 12),
          Center(
            child: QuietLink(
                linkText: 'Upload from device',
                onTap: _idType == null || _submitting ? null : _uploadId),
          ),
          const SizedBox(height: 22),
          Text(
            'Your application is reviewed by our team. Decisions are '
            'typically made within 24 hours.\n\n'
            'For the safety of the pool, your device details and '
            'approximate location are recorded with your application.',
            style: AppType.inter(12.5, color: DarkTokens.muted(), height: 1.6),
          ),
        ],
        onNext: _idType != null && _idImage != null && !_submitting
            ? _submit
            : null,
      );

  // Bordered action button for the ID step (curved, on-brand). Disabled when
  // onTap is null (no document chosen yet, or a submit is in flight).
  Widget _idActionButton(String label, IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
              color: DarkTokens.gold.withOpacity(enabled ? .6 : .25), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: DarkTokens.gold.withOpacity(enabled ? .95 : .35)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: AppType.inter(13,
                      weight: FontWeight.w500,
                      color: DarkTokens.ivory.withOpacity(enabled ? 1 : .4))),
            ),
          ],
        ),
      ),
    );
  }
}
