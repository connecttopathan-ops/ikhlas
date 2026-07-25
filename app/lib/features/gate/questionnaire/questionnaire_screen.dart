import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import '../../../providers/application_provider.dart';
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

  // Text controllers for free-text fields (kept alive across steps).
  late final _languages = TextEditingController();
  late final _ethnicity = TextEditingController();
  late final _health = TextEditingController();
  late final _sect = TextEditingController();
  late final _madhhab = TextEditingController();
  late final _town = TextEditingController();
  late final _cityText = TextEditingController(); // fallback where no city list
  late final _timing = TextEditingController();
  late final _deen = TextEditingController();

  bool _heightImperial = true; // ft/in by default (India); toggle to cm

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
      _timing, _deen
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
      final path = await repo.uploadSelfie(File(_selfie!.path));
      await repo.submitApplication(_a, selfieStoragePath: path);
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

  Future<void> _pickDob() async {
    final now = DateTime.now();
    // 18+ is a hard gate — the picker can't select a younger birthdate.
    final eighteen = DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _a.dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 80),
      lastDate: eighteen,
      helpText: 'Date of birth (18+)',
    );
    if (picked != null) setState(() => _a.dob = picked);
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
        7 => _sectionD1(),
        8 => _sectionD2(),
        9 => _sectionE(),
        10 => _sectionF(),
        _ => _selfieStep(),
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
          const QuestionLabel('Date of birth'),
          InkWell(
            onTap: _pickDob,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: DarkTokens.gold.withOpacity(.65))),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _a.dob == null
                        ? 'Select your date of birth'
                        : '${_a.dob!.day.toString().padLeft(2, '0')} / '
                            '${_a.dob!.month.toString().padLeft(2, '0')} / '
                            '${_a.dob!.year}',
                    style: AppType.inter(16,
                        color: _a.dob == null
                            ? DarkTokens.muted(.4)
                            : DarkTokens.ivory),
                  ),
                ),
                const DiamondBullet(size: 6),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          _heightPicker(),
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
        onNext: _a.sectionC1Complete ? _next : null,
      );

  // ---- C2. Life & roots ----
  Widget _sectionC2() => StepScaffold(
        step: 4,
        totalSteps: _totalSteps,
        eyebrow: 'Section C · Life & roots',
        title: 'Where life has placed you',
        children: [
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
          if (citiesFor(_a.residenceCountry, _a.residenceState).isNotEmpty)
            _dropdown(
                label: 'City',
                value: _a.residenceCity.isEmpty ? null : _a.residenceCity,
                items: citiesFor(_a.residenceCountry, _a.residenceState),
                onChanged: (v) => setState(() => _a.residenceCity = v ?? ''))
          else
            UnderlineField(
                label: 'City',
                controller: _cityText,
                hint: 'e.g. Hyderabad',
                onChanged: (v) => setState(() => _a.residenceCity = v)),
          const SizedBox(height: 12),
          UnderlineField(
              label: 'Town / area (optional)',
              controller: _town,
              onChanged: (v) => setState(() => _a.residenceTown = v)),
          const SizedBox(height: 12),
          _dropdown(
              label: 'Nationality — where you are from',
              value: _a.nationality.isEmpty ? null : _a.nationality,
              items: kCountries,
              onChanged: (v) => setState(() => _a.nationality = v ?? '')),
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
          const QuestionLabel('Your halal diet practice'),
          OptionList(
              options: Choices.diet,
              selected: _a.dietPractice,
              onSelect: (v) => setState(() => _a.dietPractice = v)),
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

  Widget _sectionD1() => _shortAnswer(
        step: 7,
        title: 'What makes now the right time?',
        prompt: "Tell us what's happening in your life that's made this the "
            "right time to look for a spouse. A few honest sentences. There's "
            "no right answer — we're trying to understand where you are.",
        ctrl: _timing,
        onChanged: (v) => _a.timingReadiness = v,
        complete: _a.sectionD1Complete,
        lengthNow: _a.timingReadiness.trim().length,
      );

  Widget _sectionD2() => _shortAnswer(
        step: 8,
        title: 'Describe your relationship with deen',
        prompt: 'What part of your deen are you most consistent in, and what '
            'are you still working on?',
        ctrl: _deen,
        onChanged: (v) => _a.deenRelationship = v,
        complete: _a.sectionD2Complete,
        lengthNow: _a.deenRelationship.trim().length,
      );

  // ---- Shared inputs: styled dropdown + dual-unit height picker ----
  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppType.inter(12.5, color: DarkTokens.muted())),
          const SizedBox(height: 2),
          DropdownButtonFormField<String>(
            initialValue: (value != null && items.contains(value)) ? value : null,
            isExpanded: true,
            dropdownColor: DarkTokens.bg,
            icon: Icon(Icons.expand_more, color: DarkTokens.muted(.7)),
            style: AppType.inter(15, color: DarkTokens.ivory),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: DarkTokens.hairline(.5))),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: DarkTokens.gold)),
            ),
            hint: Text('Select…',
                style: AppType.inter(15, color: DarkTokens.muted(.5))),
            items: [
              for (final it in items)
                DropdownMenuItem(
                    value: it,
                    child: Text(it,
                        style: AppType.inter(15, color: DarkTokens.ivory))),
            ],
            onChanged: onChanged,
          ),
        ]),
      );

  Widget _heightPicker() {
    final cm = _a.heightCm;
    int? feet, inch;
    if (cm != null) {
      final t = (cm / 2.54).round();
      feet = t ~/ 12;
      inch = t % 12;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text('Height',
                style: AppType.inter(12.5, color: DarkTokens.muted()))),
        _unitPill('ft/in', true),
        const SizedBox(width: 8),
        _unitPill('cm', false),
      ]),
      const SizedBox(height: 4),
      if (_heightImperial)
        Row(children: [
          Expanded(
              child: _miniDropdown<int>(
                  value: feet,
                  items: [for (var f = 4; f <= 7; f++) f],
                  labelOf: (v) => '$v ft',
                  onChanged: (f) => _setImperial(f, inch ?? 0))),
          const SizedBox(width: 12),
          Expanded(
              child: _miniDropdown<int>(
                  value: inch,
                  items: [for (var i = 0; i <= 11; i++) i],
                  labelOf: (v) => '$v in',
                  onChanged: (i) => _setImperial(feet ?? 5, i))),
        ])
      else
        _miniDropdown<int>(
            value: cm,
            items: [for (var c = 140; c <= 210; c++) c],
            labelOf: (v) => '$v cm',
            onChanged: (c) => setState(() => _a.heightCm = c)),
      if (cm != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${feet}\'$inch" ($cm cm)',
              style: AppType.inter(13, color: DarkTokens.gold)),
        ),
    ]);
  }

  void _setImperial(int feet, int inch) =>
      setState(() => _a.heightCm = ((feet * 12 + inch) * 2.54).round());

  Widget _unitPill(String label, bool imperial) {
    final on = _heightImperial == imperial;
    return GestureDetector(
      onTap: () => setState(() => _heightImperial = imperial),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: on ? DarkTokens.gold.withValues(alpha: .12) : null,
          border: Border.all(
              color: on ? DarkTokens.gold : DarkTokens.hairline(.5)),
        ),
        child: Text(label,
            style: AppType.inter(12,
                color: on ? DarkTokens.gold : DarkTokens.muted())),
      ),
    );
  }

  Widget _miniDropdown<T>({
    required T? value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T> onChanged,
  }) =>
      DropdownButtonFormField<T>(
        initialValue: (value != null && items.contains(value)) ? value : null,
        isExpanded: true,
        dropdownColor: DarkTokens.bg,
        icon: Icon(Icons.expand_more, color: DarkTokens.muted(.7)),
        style: AppType.inter(15, color: DarkTokens.ivory),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: DarkTokens.hairline(.5))),
          focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: DarkTokens.gold)),
        ),
        hint: Text('—', style: AppType.inter(15, color: DarkTokens.muted(.5))),
        items: [
          for (final it in items)
            DropdownMenuItem(
                value: it,
                child: Text(labelOf(it),
                    style: AppType.inter(15, color: DarkTokens.ivory))),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );

  // ---- E. Creed & finance ----
  Widget _sectionE() => StepScaffold(
        step: 9,
        totalSteps: _totalSteps,
        eyebrow: 'Section E · Creed & finance',
        title: 'Affirmations',
        intro: 'These reflect the standard of the Ikhlaas pool. '
            'Answer truthfully before Allah.',
        children: [
          const QuestionLabel(
              'I affirm that all worship and supplication is for Allah alone. '
              'I do not invoke, supplicate to, or seek help from the deceased, '
              'saints, or graves.'),
          OptionList(
              options: Choices.e1,
              selected: _a.e1Tawhid,
              onSelect: (v) => setState(() => _a.e1Tawhid = v)),
          const QuestionLabel(
              'I affirm that riba (interest) is impermissible, including '
              'conventional interest-based home, car, and personal loans and '
              'credit-card interest.'),
          OptionList(
              options: Choices.e1, // same affirm / not_affirm pair
              selected: _a.e2Riba,
              onSelect: (v) => setState(() => _a.e2Riba = v)),
          const QuestionLabel('My current situation with interest-based debt:'),
          OptionList(
              options: Choices.e3,
              selected: _a.e3RibaPractice,
              onSelect: (v) => setState(() => _a.e3RibaPractice = v)),
          const QuestionLabel(
              'Is your primary income from a source you consider halal?'),
          OptionList(
              options: Choices.e4,
              selected: _a.e4IncomeSource,
              onSelect: (v) => setState(() => _a.e4IncomeSource = v)),
        ],
        onNext: _a.sectionEComplete ? _next : null,
      );

  // ---- F. Deen Detail (NON-GATING — matching signal only) ----
  Widget _sectionF() => StepScaffold(
        step: 10,
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
        step: 11,
        totalSteps: _totalSteps,
        eyebrow: 'Verification',
        title: 'One honest photo',
        intro: 'A quick selfie confirms you are you. It is seen only by '
            'our review team — never by other members.',
        ctaLabel: 'Submit my application',
        loading: _submitting,
        children: [
          Center(
            child: InkWell(
              onTap: _submitting ? null : _captureSelfie,
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
                  linkText: 'Retake photo',
                  onTap: _submitting ? null : _captureSelfie),
            ),
          ],
          const SizedBox(height: 22),
          Text(
            'Your application is reviewed by our team. Decisions are '
            'typically made within 24 hours.\n\n'
            'For the safety of the pool, your device details and '
            'approximate location are recorded with your application.',
            style: AppType.inter(12.5, color: DarkTokens.muted(), height: 1.6),
          ),
        ],
        onNext: _selfie != null && !_submitting ? _submit : null,
      );
}
