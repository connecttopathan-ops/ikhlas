import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../providers/application_provider.dart';
import '../gate/questionnaire/questionnaire_widgets.dart';
import '../gate/questionnaire/questionnaire_models.dart';
import '../matches/member_photo.dart';

/// Edit an already-built profile — photos, privacy, bio prompts, match
/// preferences and Wali, all on one scrollable form pre-filled from the
/// live user doc. Saves through the same `saveProfileBuilder` write the
/// first-run builder uses (owner-only Firestore update).
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

/// One photo slot: either an already-uploaded photo (by its storage path and
/// its index in the saved array, so the server can serve it) or a freshly
/// picked local file awaiting upload.
class _Photo {
  final String? path; // existing storagePath
  final int? savedIndex; // position in the saved photos array
  final XFile? file; // newly picked, not yet uploaded
  _Photo.existing(this.path, this.savedIndex) : file = null;
  _Photo.local(this.file)
      : path = null,
        savedIndex = null;
  bool get isNew => file != null;
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  bool _loaded = false;
  bool _saving = false;

  final List<_Photo> _photos = [];
  String _privacy = 'on_mutual_blur';

  static const _prompts = [
    ('first_year', 'My ideal first year of marriage looks like…'),
    ('deen_consistent', 'The deen practice I am most consistent in…'),
    ('looking_for', 'What I am looking for in a spouse…'),
  ];
  final _promptCtrls =
      List.generate(3, (_) => TextEditingController(), growable: false);

  RangeValues _ageRange = const RangeValues(21, 35);
  bool _acceptDivorced = true;
  bool _acceptWidowed = true;
  bool _acceptChildren = true;
  bool _relocationRequired = false;
  bool _openToSpouseAbroad = true;
  String? _financialExpectation;
  String? _spouseWork;
  String? _deenPrefPrayer;
  String? _deenPrefHijabBeard;
  String? _deenPrefRiba;
  String? _dietPreference;
  RangeValues? _heightRange;

  final _waliName = TextEditingController();
  String? _waliRelationship;
  final _waliPhone = TextEditingController();

  static const _minPromptChars = 40;

  @override
  void dispose() {
    for (final c in _promptCtrls) {
      c.dispose();
    }
    _waliName.dispose();
    _waliPhone.dispose();
    super.dispose();
  }

  /// Pre-fills every field from the current user doc, once.
  void _hydrate(Map<String, dynamic> d) {
    if (_loaded) return;
    _loaded = true;
    final photos = (d['photos'] as List?) ?? [];
    for (var i = 0; i < photos.length; i++) {
      final p = photos[i] as Map?;
      _photos.add(_Photo.existing(p?['storagePath'] as String?, i));
    }
    // photoVisibility, migrating the legacy photoPrivacy field.
    const visMap = {
      'visible': 'public',
      'blur_until_match': 'on_mutual_blur',
      'request_only': 'on_mutual_hidden',
    };
    _privacy = (d['profile'] as Map?)?['photoVisibility'] as String? ??
        visMap[d['photoPrivacy']] ??
        'on_mutual_blur';

    final bio = ((d['profile'] as Map?)?['bioPrompts'] as List?) ?? [];
    for (var i = 0; i < _prompts.length; i++) {
      final match = bio.firstWhere(
        (b) => (b as Map)['promptId'] == _prompts[i].$1,
        orElse: () => null,
      );
      if (match != null) _promptCtrls[i].text = (match['answer'] ?? '') as String;
    }

    final prefs = (d['preferences'] as Map?) ?? {};
    _ageRange = RangeValues(
      (prefs['ageMin'] as num?)?.toDouble() ?? 21,
      (prefs['ageMax'] as num?)?.toDouble() ?? 35,
    );
    _acceptDivorced = prefs['acceptDivorced'] as bool? ?? true;
    _acceptWidowed = prefs['acceptWidowed'] as bool? ?? true;
    _acceptChildren = prefs['acceptChildren'] as bool? ?? true;
    _relocationRequired = prefs['relocationRequired'] as bool? ?? false;
    _openToSpouseAbroad = prefs['openToSpouseAbroad'] as bool? ?? true;
    _spouseWork = prefs['spouseWorkExpectation'] as String?;
    _dietPreference = prefs['dietPreference'] as String?;
    _financialExpectation =
        (d['profile'] as Map?)?['financialExpectation'] as String?;
    final dp = prefs['deenPreference'] as Map?;
    _deenPrefPrayer = dp?['prayer'] as String?;
    _deenPrefHijabBeard = dp?['hijabBeard'] as String?;
    _deenPrefRiba = dp?['ribaStance'] as String?;
    final hr = prefs['heightRange'] as Map?;
    if (hr != null && hr['min'] != null && hr['max'] != null) {
      _heightRange = RangeValues(
          (hr['min'] as num).toDouble(), (hr['max'] as num).toDouble());
    }

    final wali = d['wali'] as Map?;
    if (wali != null) {
      _waliName.text = (wali['name'] ?? '') as String;
      _waliRelationship = wali['relationship'] as String?;
      final phone = (wali['phone'] ?? '') as String;
      _waliPhone.text =
          phone.startsWith('+91') ? phone.substring(3) : phone;
    }
  }

  bool get _photosOk => _photos.isNotEmpty;
  bool get _promptsOk =>
      _promptCtrls.every((c) => c.text.trim().length >= _minPromptChars);
  bool get _waliEmpty =>
      _waliName.text.trim().isEmpty &&
      _waliPhone.text.trim().isEmpty &&
      _waliRelationship == null;
  bool get _waliValid =>
      _waliName.text.trim().length >= 3 &&
      _waliRelationship != null &&
      RegExp(r'^[6-9]\d{9}$').hasMatch(_waliPhone.text.trim());
  bool get _waliOk => _waliEmpty || _waliValid;
  bool get _canSave => _photosOk && _promptsOk && _waliOk && !_saving;

  Future<void> _addPhotos() async {
    if (_photos.length >= 6) return;
    final picked =
        await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 88);
    if (picked.isNotEmpty) {
      setState(() {
        for (final img in picked) {
          if (_photos.length < 6) _photos.add(_Photo.local(img));
        }
      });
    }
  }

  /// Highest slot number already used by kept photos, so new uploads never
  /// overwrite an existing file (paths look like `.../photo_3.jpg`).
  int _maxSlot() {
    var max = -1;
    for (final p in _photos) {
      final path = p.path;
      if (path == null) continue;
      final m = RegExp(r'photo_(\d+)').firstMatch(path);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? -1;
        if (n > max) max = n;
      }
    }
    return max;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(applicationRepositoryProvider);
      var slot = _maxSlot() + 1;
      final paths = <String>[];
      for (final p in _photos) {
        if (p.isNew) {
          paths.add(await repo.uploadProfilePhoto(File(p.file!.path), slot++));
        } else if (p.path != null) {
          paths.add(p.path!);
        }
      }
      await repo.saveProfileBuilder(
        photoPaths: paths,
        photoVisibility: _privacy,
        bioPrompts: [
          for (var i = 0; i < _prompts.length; i++)
            {'promptId': _prompts[i].$1, 'answer': _promptCtrls[i].text.trim()},
        ],
        preferences: {
          'ageMin': _ageRange.start.round(),
          'ageMax': _ageRange.end.round(),
          'acceptDivorced': _acceptDivorced,
          'acceptWidowed': _acceptWidowed,
          'acceptChildren': _acceptChildren,
          'relocationRequired': _relocationRequired,
          'openToSpouseAbroad': _openToSpouseAbroad,
          if (_dietPreference != null) 'dietPreference': _dietPreference,
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
        },
        financialExpectation: _financialExpectation,
        wali: _waliValid
            ? {
                'name': _waliName.text.trim(),
                'relationship': _waliRelationship,
                'phone': '+91${_waliPhone.text.trim()}',
                'permissionLevel': 'notify',
                'verified': false,
              }
            : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Profile updated.', style: AppType.inter(13))));
        context.go('/settings');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not save changes. Please try again.',
                style: AppType.inter(13))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(userDocProvider).value?.data();
    if (doc == null) {
      return const IkhlasScaffold(
          child: Center(child: CircularProgressIndicator()));
    }
    _hydrate(doc);
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isSister = doc['gender'] == 'female';

    return IkhlasScaffold(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, AppSpace.screenMargin, 4),
          child: Row(children: [
            IconButton(
              onPressed: () => context.go('/settings'),
              icon: Icon(Icons.arrow_back, size: 22, color: DarkTokens.muted(.7)),
            ),
            const SizedBox(width: 4),
            Text('Edit profile',
                style: AppType.fraunces(24, color: DarkTokens.ivory)),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.screenMargin, 12, AppSpace.screenMargin, 20),
            children: [
              _section('Photos'),
              Text('At least one, up to six. Revealed to a match only when '
                  'your privacy setting allows.',
                  style: AppType.inter(12.5, color: DarkTokens.muted(.7))),
              const SizedBox(height: 14),
              _photoGrid(me),

              const SizedBox(height: 28),
              _section('Photo visibility'),
              OptionList(
                options: Choices.photoVisibility,
                selected: _privacy,
                onSelect: (v) => setState(() => _privacy = v),
              ),

              const SizedBox(height: 28),
              _section('In your words'),
              for (var i = 0; i < _prompts.length; i++) ...[
                QuestionLabel(_prompts[i].$2),
                TextField(
                  controller: _promptCtrls[i],
                  onChanged: (_) => setState(() {}),
                  maxLines: 3,
                  style:
                      AppType.inter(14.5, color: DarkTokens.ivory, height: 1.6),
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
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 16),
              _section('Preferences'),
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
                Row(children: [
                  Expanded(
                    child: RangeSlider(
                      values: _heightRange!,
                      min: 140,
                      max: 210,
                      divisions: 70,
                      activeColor: DarkTokens.gold,
                      inactiveColor: DarkTokens.hairline(),
                      onChanged: (v) => setState(() => _heightRange = v),
                    ),
                  ),
                  QuietLink(
                      linkText: 'Clear',
                      onTap: () => setState(() => _heightRange = null)),
                ]),

              const QuestionLabel('Your own view on provision'),
              Text('Matched as alignment — never an income filter.',
                  style: AppType.inter(12, color: DarkTokens.muted())),
              const SizedBox(height: 6),
              OptionList(
                  options: Choices.financialExpectation,
                  selected: _financialExpectation,
                  onSelect: (v) => setState(() => _financialExpectation = v)),

              const QuestionLabel('Preferred halal diet (optional)'),
              OptionList(
                  options: Choices.dietPreference,
                  selected: _dietPreference,
                  onSelect: (v) => setState(() => _dietPreference = v)),

              const QuestionLabel(
                  'Would you like your spouse to work? (optional)'),
              OptionList(
                  options: Choices.spouseWork,
                  selected: _spouseWork,
                  onSelect: (v) => setState(() => _spouseWork = v)),

              const QuestionLabel('Deen preferences (optional)'),
              Text('What you\'re looking for — never a hard gate.',
                  style: AppType.inter(12, color: DarkTokens.muted())),
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

              const SizedBox(height: 28),
              _section('Wali'),
              Text(
                  isSister
                      ? 'Your Wali is notified as things progress. Add or '
                          'update his details, or clear all three to remove.'
                      : 'Optional — a guardian kept informed as things '
                          'progress. Clear all three to remove.',
                  style: AppType.inter(12.5, color: DarkTokens.muted(.7))),
              const SizedBox(height: 16),
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
              const SizedBox(height: 12),
              if (!_waliEmpty && !_waliValid)
                Text('Complete all three Wali fields (valid Indian mobile) — '
                    'or clear them to remove.',
                    style: AppType.inter(12.5, color: DarkTokens.muted())),
              const SizedBox(height: 8),
              if (!_photosOk)
                Text('Add at least one photo.',
                    style: AppType.inter(12.5, color: DarkTokens.muted())),
              if (!_promptsOk)
                Text('Each of the three prompts needs at least '
                    '$_minPromptChars characters.',
                    style: AppType.inter(12.5, color: DarkTokens.muted())),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.screenMargin, 4, AppSpace.screenMargin, 20),
          child: PrimaryCta(
              label: 'Save changes',
              loading: _saving,
              onPressed: _canSave ? _save : null),
        ),
      ]),
    );
  }

  Widget _prefLabel(String s) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 2),
        child: Text(s,
            style: AppType.inter(13,
                weight: FontWeight.w500, color: DarkTokens.muted(.85))),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title.toUpperCase(),
            style: AppType.eyebrow(DarkTokens.gold)),
      );

  Widget _photoGrid(String me) => GridView.count(
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
                child: _photos[i].isNew
                    ? Image.file(File(_photos[i].file!.path), fit: BoxFit.cover)
                    : MemberPhoto(
                        ownerUid: me,
                        index: _photos[i].savedIndex ?? 0,
                        width: 200,
                        height: 250,
                        radius: AppRadius.control),
              ),
              if (i == 0)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    color: DarkTokens.bg.withOpacity(.75),
                    child: Text('PRIMARY',
                        style: AppType.inter(9,
                            weight: FontWeight.w600, color: DarkTokens.gold)),
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
                  border: Border.all(color: DarkTokens.hairline(.45)),
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const DiamondBullet(size: 8),
                      const SizedBox(height: 8),
                      Text('Add',
                          style: AppType.inter(12, color: DarkTokens.muted())),
                    ]),
              ),
            ),
        ],
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
}
