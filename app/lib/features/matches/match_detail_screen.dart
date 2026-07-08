import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../providers/application_provider.dart';
import 'member_photo.dart';

/// Full profile for one daily-batch match. Opened by tapping a card —
/// deen-first, showing every photo the member's privacy allows, all three
/// bio prompts, and the basics. Express interest / Pass live here too.
class MatchDetailScreen extends ConsumerStatefulWidget {
  final String entryId; // the other member's uid
  final Map<String, dynamic> entry;
  const MatchDetailScreen({super.key, required this.entryId, required this.entry});

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen> {
  bool _busy = false;

  static const _prayerLabel = {
    'five_daily': 'Prays five daily',
    'most': 'Prays most salah',
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

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final action = e['action'] as String?;
    final compat = (e['compatibility'] as List?)?.cast<String>() ?? [];
    final prompts = (e['bioPrompts'] as List?) ?? [];
    final langs = (e['languages'] as List?)?.cast<String>() ?? [];
    final hasPhotos = e['hasPhotos'] == true;

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
                // Lead photo (privacy-aware) or girih panel
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: DarkTokens.hairline(.4)),
                    ),
                    child: hasPhotos
                        ? MemberPhoto(
                            ownerUid: widget.entryId,
                            width: 240, height: 300, radius: 14)
                        : const SizedBox(
                            width: 240, height: 300,
                            child: Center(
                                child: GirihMark(size: 96, opacity: .5))),
                  ),
                ),
                if (hasPhotos)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        e['photoPrivacy'] == 'blur_until_match'
                            ? 'Photos reveal when interest is mutual.'
                            : e['photoPrivacy'] == 'request_only'
                                ? 'Private photos — revealed by request.'
                                : '',
                        textAlign: TextAlign.center,
                        style: AppType.inter(11.5, color: DarkTokens.muted())),
                  ),
                const SizedBox(height: 22),
                Text(
                    '${_prayerLabel[e['prayer']] ?? 'Deen-focused'}'
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
                    const DiamondBullet(size: 6),
                    const SizedBox(width: 8),
                    Text('Honest disclosure: actively exiting legacy debt',
                        style: AppType.inter(12.5, color: DarkTokens.gold)),
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
                                child: DiamondBullet(size: 5)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(c,
                                    style: AppType.inter(14,
                                        color: DarkTokens.ivory))),
                          ]),
                    ),
                ],

                const SizedBox(height: 22),
                const Hairline(),
                const SizedBox(height: 18),
                Text('BASICS', style: AppType.eyebrow(DarkTokens.gold)),
                const SizedBox(height: 12),
                _fact('Seeking', _timeframeLabel[e['timeframe']]),
                _fact('Marital status', _maritalLabel[e['maritalStatus']]),
                _fact('Education', e['education']),
                _fact('Profession', e['profession']),
                _fact('Languages', langs.isEmpty ? null : langs.join(', ')),
                _fact('Madhhab', e['madhhab']),

                if (prompts.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Hairline(),
                  const SizedBox(height: 18),
                  Text('IN HER WORDS', style: AppType.eyebrow(DarkTokens.gold)),
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

                // Section D answers — seriousness/deen, shown to matches.
                if ((e['whyNow'] ?? '').toString().isNotEmpty ||
                    (e['deenRelationship'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Hairline(),
                  const SizedBox(height: 18),
                  Text('ON SEEKING NIKAH', style: AppType.eyebrow(DarkTokens.gold)),
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
                const DiamondBullet(),
                const SizedBox(width: 10),
                Text(
                    action == 'interested'
                        ? 'Interest expressed — a conversation opens if mutual.'
                        : 'Passed, respectfully.',
                    style: AppType.inter(12.5, color: DarkTokens.muted())),
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
