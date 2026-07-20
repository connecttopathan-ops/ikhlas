import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../matches/member_photo.dart';

/// Read-only profile of the person you're talking to, built from the
/// denormalised snapshot stored on the conversation doc (`profiles[uid]`).
/// A member can't read another member's users doc directly (rules), so the
/// conversation carries everything this view needs. No actions here — the
/// relationship already exists; this is just "who am I speaking with".
class ChatProfileScreen extends StatelessWidget {
  final String ownerUid;
  final Map<String, dynamic> profile;

  /// Whether this person has revealed their (on_mutual_hidden) photos to me.
  /// Feeds the photo cache key so a granted reveal refetches instantly instead
  /// of serving the batch's stale blurred bytes.
  final bool photoRevealed;
  const ChatProfileScreen(
      {super.key,
      required this.ownerUid,
      required this.profile,
      this.photoRevealed = false});

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

  @override
  Widget build(BuildContext context) {
    final e = profile;
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
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: DarkTokens.hairline(.4)),
                    ),
                    child: hasPhotos
                        ? MemberPhoto(
                            ownerUid: ownerUid,
                            width: 240, height: 300, radius: 14,
                            // Only diverge from the batch's cache when the served
                            // image actually differs: blur→clear on match, or a
                            // hidden reveal. Public photos are clear in both, so
                            // we reuse the batch's cache (no extra fetch/latency).
                            cacheBust: _photoCacheBust(e['photoVisibility']))
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
                        e['photoVisibility'] == 'on_mutual_blur'
                            ? 'Photos reveal now that you have matched.'
                            : e['photoVisibility'] == 'on_mutual_hidden'
                                ? (photoRevealed
                                    ? 'Photos shared with you.'
                                    : 'Private photos — revealed by request.')
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
                    Expanded(
                      child: Text(
                          'Honest disclosure: actively exiting legacy debt',
                          style: AppType.inter(12.5, color: DarkTokens.gold)),
                    ),
                  ]),
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
        ],
      ),
    );
  }

  /// The cache-key suffix for a chat photo. `null` reuses the batch's cache
  /// (public — identical bytes). `on_mutual_blur` was cached blurred in the
  /// batch, so we must refetch the clear version. `on_mutual_hidden` flips key
  /// on reveal so the newly-shared photo loads immediately.
  String? _photoCacheBust(dynamic visibility) {
    switch (visibility) {
      case 'on_mutual_hidden':
        return photoRevealed ? 'chatR' : 'chat';
      case 'on_mutual_blur':
        return 'chat';
      default:
        return null;
    }
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
