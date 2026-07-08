import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import '../../../providers/application_provider.dart';
import '../selfie_capture_screen.dart';
import 'questionnaire_models.dart';
import 'questionnaire_widgets.dart';

/// Screening questionnaire — sections A–E as a stepped flow
/// (ikhlas-tech-requirements.md §4: one question-group per screen,
/// Fraunces headers, gold accents). Answers stage locally; a single
/// submission writes the user profile + the immutable application doc.
class QuestionnaireScreen extends ConsumerStatefulWidget {
  const QuestionnaireScreen({super.key});
  @override
  ConsumerState<QuestionnaireScreen> createState() =>
      _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends ConsumerState<QuestionnaireScreen> {
  static const _totalSteps = 9;
  int _step = 1;
  final _a = QuestionnaireAnswers();
  bool _submitting = false;
  XFile? _selfie;

  // Text controllers for free-text fields (kept alive across steps).
  late final _city = TextEditingController(text: _a.city);
  late final _country = TextEditingController(text: _a.country);
  late final _languages = TextEditingController();
  late final _ethnicity = TextEditingController();
  late final _education = TextEditingController();
  late final _profession = TextEditingController();
  late final _sect = TextEditingController();
  late final _madhhab = TextEditingController();
  late final _whyNow = TextEditingController();
  late final _deen = TextEditingController();

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
        6 => _sectionD1(),
        7 => _sectionD2(),
        8 => _sectionE(),
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
          UnderlineField(
              label: 'Country',
              controller: _country,
              onChanged: (v) => setState(() => _a.country = v)),
          const SizedBox(height: 20),
          UnderlineField(
              label: 'City',
              controller: _city,
              hint: 'e.g. Hyderabad',
              onChanged: (v) => setState(() => _a.city = v)),
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
          UnderlineField(
              label: 'Education',
              controller: _education,
              hint: 'e.g. B.Tech, Computer Science',
              onChanged: (v) => setState(() => _a.education = v)),
          const SizedBox(height: 20),
          UnderlineField(
              label: 'Profession',
              controller: _profession,
              hint: 'e.g. Software engineer',
              onChanged: (v) => setState(() => _a.profession = v)),
        ],
        onNext: _a.sectionC3Complete ? _next : null,
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
        step: 6,
        title: 'Why nikah, and why now?',
        prompt: 'A few sincere sentences. Minimum 100 characters.',
        ctrl: _whyNow,
        onChanged: (v) => _a.whyNow = v,
        complete: _a.sectionD1Complete,
        lengthNow: _a.whyNow.trim().length,
      );

  Widget _sectionD2() => _shortAnswer(
        step: 7,
        title: 'Describe your relationship with your deen',
        prompt: 'Where you are, where you are striving to be. '
            'Minimum 100 characters.',
        ctrl: _deen,
        onChanged: (v) => _a.deenRelationship = v,
        complete: _a.sectionD2Complete,
        lengthNow: _a.deenRelationship.trim().length,
      );

  // ---- E. Creed & finance ----
  Widget _sectionE() => StepScaffold(
        step: 8,
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
        ],
        onNext: _a.sectionEComplete ? _next : null,
      );

  // ---- Verification selfie (manual capture; liveness SDK later) ----
  Widget _selfieStep() => StepScaffold(
        step: 9,
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
