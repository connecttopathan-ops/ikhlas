import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../providers/application_provider.dart';
import 'member_photo.dart';

/// Full profile for one daily-batch match. Deen-first (PRD §4.2): the DEEN
/// block sits above BASICS, the photo layer honours photoVisibility, and the
/// card is curves-only — no squares or rotated squares anywhere in this tree.
/// Income, residency and health are never shown here (Family Stage only, §0).
class MatchDetailScreen extends ConsumerStatefulWidget {
  final String entryId; // the other member's uid
  final Map<String, dynamic> entry;
  const MatchDetailScreen({super.key, required this.entryId, required this.entry});

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen> {
  bool _busy = false;

  static const _prayerEyebrow = {
    'five_daily': 'Prays five daily',
    'most': 'Prays most salah',
  };
  static const _prayerLabel = {
    'five_daily': 'Five daily, consistently',
    'most': 'Most prayers',
    'working': 'Working on it',
    'rarely': 'Rarely',
  };
  static const _quranLabel = {
    'hafiz': 'Hafiz',
    'regular': 'Reads regularly',
    'learning': 'Learning to read',
    'seeking': 'Seeking to start',
  };
  static const _islamicStudyLabel = {
    'formal': 'Formal (madrasa / ʿalim)',
    'structured_self': 'Structured self-study',
    'casual': 'Casual',
    'none': 'None yet',
  };
  static const _fastingLabel = {
    'regularly': 'Regularly',
    'sometimes': 'Sometimes',
    'no': 'Not beyond Ramadan',
  };
  static const _dietLabel = {
    'zabiha_only': 'Zabiha only',
    'halal_only': 'Halal only',
    'halal_when_available': 'Halal when available',
    'no_restriction': 'No restriction',
  };
  static const _timeframeLabel = {
    '6m': 'Nikah within 6 months',
    '6_12m': 'Nikah in 6–12 months',
    '12_24m': 'Nikah in 12–24 months',
  };
  static const _maritalLabel = {
    'never_married': 'Never married',
    'divorced': 'Divorced',
    'widowed': 'Widowed',
  };
  static const _bandLabel = {
    'strong': 'Strong alignment',
    'good': 'Good alignment',
    'some': 'Some alignment',
  };
  static const _eduLabel = {
    'high_school': 'High school',
    'diploma': 'Diploma',
    'bachelors': "Bachelor's degree",
    'masters': "Master's degree",
    'doctorate': 'Doctorate (PhD)',
    'islamic_studies': 'Islamic studies',
    'other': 'Other',
  };
  static const _profLabel = {
    'student': 'Student',
    'healthcare': 'Healthcare / Medicine',
    'engineering_it': 'Engineering / IT',
    'business': 'Business / Self-employed',
    'education': 'Education / Academia',
    'government': 'Government / Public sector',
    'finance': 'Finance / Accounting',
    'legal': 'Legal',
    'trade': 'Skilled trade',
    'homemaker': 'Homemaker',
    'other': 'Other',
  };

  Future<void> _act(String action) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(applicationRepositoryProvider)
          .setEntryAction(widget.entryId, action);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A1 — photo layer, three states, curves-only. `photoVisibility` +
  /// whether photos exist decide what renders; reveal is mutual + symmetric.
  Widget _photoLayer(Map<String, dynamic> e) {
    final hasPhotos = e['hasPhotos'] == true;
    final vis = e['photoVisibility'] as String? ?? 'on_mutual_blur';
    const w = 240.0, h = 300.0;

    Widget lozenge() => const SizedBox(
        width: w, height: h,
        child: Center(child: LozengeMark(size: 96, opacity: .5)));

    // No photos, or hidden-until-request → the curved lozenge motif.
    final showLozenge = !hasPhotos || vis == 'on_mutual_hidden';
    final caption = !hasPhotos
        ? null
        : (vis == 'on_mutual_blur' || vis == 'on_mutual_hidden')
            ? 'Photo shared on mutual interest'
            : null;

    return Column(children: [
      Center(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DarkTokens.hairline(.4)),
          ),
          child: showLozenge
              ? lozenge()
              // public → clear; on_mutual_blur → server returns a blur pre-match.
              : MemberPhoto(
                  ownerUid: widget.entryId, width: w, height: h, radius: 14),
        ),
      ),
      if (caption != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(caption,
              textAlign: TextAlign.center,
              style: AppType.inter(11.5, color: DarkTokens.muted())),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final action = e['action'] as String?;
    final compat = (e['compatibility'] as List?)?.cast<String>() ?? [];
    final prompts = (e['bioPrompts'] as List?) ?? [];
    final langs = (e['languages'] as List?)?.cast<String>() ?? [];
    final divergence = (e['divergence'] ?? '').toString();

    return IkhlasScaffold(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.arrow_back,
                    size: 22, color: DarkTokens.muted(.7)),
              ),
              Expanded(
                child: Text('Profile',
                    style: AppType.inter(14,
                        weight: FontWeight.w500, color: DarkTokens.ivory)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.screenMargin, 8, AppSpace.screenMargin, 24),
              children: [
                _photoLayer(e),
                const SizedBox(height: 22),
                if (_bandLabel[e['band']] != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: DarkTokens.gold.withOpacity(.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_bandLabel[e['band']]!.toUpperCase(),
                        style: AppType.inter(10.5,
                                weight: FontWeight.w600, color: DarkTokens.gold)
                            .copyWith(letterSpacing: 1)),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                    '${_prayerEyebrow[e['prayer']] ?? 'Deen-focused'}'
                    '${e['revert'] == true ? ' · Revert, celebrated' : ''}',
                    style: AppType.eyebrow(DarkTokens.gold)),
                const SizedBox(height: 8),
                Text('${e['displayName'] ?? 'Member'}, ${e['age'] ?? '—'}',
                    style: AppType.fraunces(30, color: DarkTokens.ivory)),
                const SizedBox(height: 4),
                Text(
                    [e['city'], e['country']]
                        .whereType<String>()
                        .join(', '),
                    style: AppType.inter(13.5, color: DarkTokens.muted(.7))),
                if (e['ribaDisclosureBadge'] == true) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const RoundBullet(size: 6),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'Honest disclosure: actively exiting legacy debt',
                          style: AppType.inter(12.5, color: DarkTokens.gold)),
                    ),
                  ]),
                ],

                if (compat.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Hairline(),
                  const SizedBox(height: 18),
                  Text('WHY YOU MATCH', style: AppType.eyebrow(DarkTokens.gold)),
                  const SizedBox(height: 10),
                  for (final c in compat)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: RoundBullet(size: 5)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(c,
                                    style: AppType.inter(14,
                                        color: DarkTokens.ivory))),
                          ]),
                    ),
                ],

                // A2 — DEEN block, above BASICS. Madhhab lives here now.
                const SizedBox(height: 22),
                const Hairline(),
                const SizedBox(height: 18),
                Text('DEEN', style: AppType.eyebrow(DarkTokens.gold)),
                const SizedBox(height: 12),
                _fact('Prayer', _prayerLabel[e['prayer']]),
                _fact('Quran', _quranLabel[e['quran']]),
                _fact('Islamic study', _islamicStudyLabel[e['islamicStudy']]),
                _fact('Fasting', _fastingLabel[e['fastingBeyondRamadan']]),
                _fact('Madhhab', e['madhhab']),
                _fact('Diet', _dietLabel[e['dietPractice']]),

                // A3 — BASICS, now with Height (madhhab moved to Deen).
                const SizedBox(height: 22),
                const Hairline(),
                const SizedBox(height: 18),
                Text('BASICS', style: AppType.eyebrow(DarkTokens.gold)),
                const SizedBox(height: 12),
                _fact('Seeking', _timeframeLabel[e['timeframe']]),
                _fact('Marital status', _maritalLabel[e['maritalStatus']]),
                _fact('Height',
                    e['height'] == null ? null : '${e['height']} cm'),
                _fact('Education', _eduLabel[e['education']] ?? e['education']),
                _fact('Profession',
                    _profLabel[e['profession']] ?? e['profession']),
                _fact('Languages', langs.isEmpty ? null : langs.join(', ')),

                // A4 — the one honest divergence, below BASICS (PRD §4.2).
                if (divergence.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Differs on:  ',
                        style: AppType.inter(13,
                            weight: FontWeight.w600,
                            color: DarkTokens.muted(.85))),
                    Expanded(
                      child: Text(divergence,
                          style: AppType.inter(13,
                              color: DarkTokens.muted(.85), height: 1.45)),
                    ),
                  ]),
                ],

                // A6 — "In their words" left exactly as is.
                if (prompts.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Hairline(),
                  const SizedBox(height: 18),
                  Text('IN THEIR WORDS',
                      style: AppType.eyebrow(DarkTokens.gold)),
                  const SizedBox(height: 12),
                  for (final p in prompts)
                    if (((p as Map)['answer'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_promptLabel(p['promptId']),
                                  style: AppType.inter(11.5,
                                      color: DarkTokens.muted(),
                                      weight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              Text('“${p['answer']}”',
                                  style: AppType.fraunces(15.5,
                                      color: DarkTokens.ivory,
                                      style: FontStyle.italic,
                                      height: 1.5)),
                            ]),
                      ),
                ],

                if ((e['whyNow'] ?? '').toString().isNotEmpty ||
                    (e['deenRelationship'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Hairline(),
                  const SizedBox(height: 18),
                  Text('ON SEEKING NIKAH',
                      style: AppType.eyebrow(DarkTokens.gold)),
                  const SizedBox(height: 12),
                  if ((e['whyNow'] ?? '').toString().isNotEmpty) ...[
                    Text('Why nikah, and why now',
                        style: AppType.inter(11.5,
                            color: DarkTokens.muted(), weight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('“${e['whyNow']}”',
                        style: AppType.fraunces(15.5,
                            color: DarkTokens.ivory,
                            style: FontStyle.italic,
                            height: 1.5)),
                    const SizedBox(height: 16),
                  ],
                  if ((e['deenRelationship'] ?? '').toString().isNotEmpty) ...[
                    Text('Their relationship with the deen',
                        style: AppType.inter(11.5,
                            color: DarkTokens.muted(), weight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('“${e['deenRelationship']}”',
                        style: AppType.fraunces(15.5,
                            color: DarkTokens.ivory,
                            style: FontStyle.italic,
                            height: 1.5)),
                  ],
                ],
              ],
            ),
          ),
          // Sticky action bar
          if (action == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.screenMargin, 8, AppSpace.screenMargin, 20),
              child: Row(children: [
                Expanded(
                  child: PrimaryCta(
                      label: 'Express interest',
                      loading: _busy,
                      onPressed: _busy ? null : () => _act('interested')),
                ),
                const SizedBox(width: 16),
                QuietLink(
                    linkText: 'Pass',
                    onTap: _busy ? null : () => _act('passed')),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.screenMargin, 8, AppSpace.screenMargin, 24),
              child: Row(children: [
                const RoundBullet(),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      action == 'interested'
                          ? 'Interest expressed — a conversation opens if mutual.'
                          : 'Passed, respectfully.',
                      style: AppType.inter(12.5, color: DarkTokens.muted())),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  static String _promptLabel(dynamic id) {
    switch (id) {
      case 'first_year':
        return 'My ideal first year of marriage looks like…';
      case 'deen_consistent':
        return 'The deen practice I am most consistent in…';
      case 'looking_for':
        return 'What I am looking for in a spouse…';
      default:
        return '';
    }
  }

  Widget _fact(String label, dynamic value) {
    if (value == null || '$value'.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 120,
          child: Text(label,
              style: AppType.inter(12.5, color: DarkTokens.muted())),
        ),
        Expanded(
          child: Text('$value',
              style: AppType.inter(13.5, color: DarkTokens.ivory)),
        ),
      ]),
    );
  }
}
