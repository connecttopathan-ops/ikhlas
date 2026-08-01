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
  static const _buildLabel = {
    'slim': 'Slim', 'athletic': 'Athletic', 'average': 'Average',
    'stocky': 'Stocky', 'heavy': 'Heavy-set',
  };
  static const _beardLabel = {
    'full': 'Full beard', 'fist_length': 'Fist-length',
    'trimmed': 'Trimmed / short', 'clean_shaven': 'Clean-shaven',
  };
  static const _hijabLabel = {
    'niqab': 'Niqab', 'hijab': 'Hijab',
    'modest_no_hijab': 'Modest, no hijab yet',
  };
  static const _aqidahLabel = {
    'athari_salafi': 'Athari / Salafi', 'ashari': 'Ashʿari',
    'maturidi': 'Maturidi', 'just_muslim': 'Just Muslim',
    'still_learning': 'Still learning',
  };
  static const _livingLabel = {
    'joint': 'Joint family', 'nuclear': 'Nuclear household',
    'flexible': 'Flexible / open',
  };
  static String? _heightLabel(dynamic cm) {
    if (cm is! int || cm <= 0) return null;
    final t = (cm / 2.54).round();
    return '${t ~/ 12}\'${t % 12}" ($cm cm)';
  }
  static String? _weightLabel(dynamic kg) =>
      (kg is! int || kg <= 0) ? null : '$kg kg (${(kg * 2.20462).round()} lb)';

  @override
  Widget build(BuildContext context) {
    final e = profile;
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
                if (!hasPhotos)
                  // Same shared placeholder + reason as the match card, so the
                  // state is never a bare, unexplained illustration.
                  const Center(
                      child: HiddenPhotoPlaceholder(reason: 'No photo'))
                else if (e['photoVisibility'] == 'on_mutual_hidden' &&
                    !photoRevealed)
                  const Center(
                      child: HiddenPhotoPlaceholder(
                          reason: 'Private photos — revealed by request'))
                else ...[
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: DarkTokens.hairline(.4)),
                      ),
                      child: MemberPhoto(
                          ownerUid: ownerUid,
                          width: 240, height: 300, radius: 14,
                          cacheBust: _photoCacheBust(e['photoVisibility'])),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        e['photoVisibility'] == 'on_mutual_blur'
                            ? 'Photos reveal now that you have matched.'
                            : e['photoVisibility'] == 'on_mutual_hidden'
                                ? 'Photos shared with you.'
                                : '',
                        textAlign: TextAlign.center,
                        style: AppType.inter(11.5, color: DarkTokens.muted())),
                  ),
                ],
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

                // DEEN extras (aqidah + scholars) surfaced above basics.
                if (_aqidahLabel[e['aqidah']] != null ||
                    (e['scholars'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Hairline(),
                  const SizedBox(height: 18),
                  Text('DEEN', style: AppType.eyebrow(DarkTokens.gold)),
                  const SizedBox(height: 12),
                  _fact('Aqidah', _aqidahLabel[e['aqidah']]),
                  _fact('Madhhab', e['madhhab']),
                  _prose('Scholars they listen to', e['scholars']),
                ],

                // APPEARANCE (never skin tone — §0).
                if (_heightLabel(e['height']) != null ||
                    _weightLabel(e['weightKg']) != null ||
                    _buildLabel[e['build']] != null ||
                    _beardLabel[e['beard']] != null ||
                    _hijabLabel[e['hijab']] != null ||
                    (e['dressingStyle'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Hairline(),
                  const SizedBox(height: 18),
                  Text('APPEARANCE', style: AppType.eyebrow(DarkTokens.gold)),
                  const SizedBox(height: 12),
                  _fact('Height', _heightLabel(e['height'])),
                  _fact('Weight', _weightLabel(e['weightKg'])),
                  _fact('Build', _buildLabel[e['build']]),
                  _fact('Beard', _beardLabel[e['beard']]),
                  _fact('Hijab', _hijabLabel[e['hijab']]),
                  _fact('Dressing', e['dressingStyle']),
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

                // FAMILY (descriptive free-text lives under IN THEIR WORDS).
                if (_livingLabel[e['livingArrangement']] != null) ...[
                  const SizedBox(height: 22),
                  const Hairline(),
                  const SizedBox(height: 18),
                  Text('FAMILY', style: AppType.eyebrow(DarkTokens.gold)),
                  const SizedBox(height: 12),
                  _fact('Living after nikah', _livingLabel[e['livingArrangement']]),
                ],

                // IN THEIR WORDS — sourced from the surviving profile free-text
                // (the standalone bio-prompts page was removed as redundant).
                if ((e['islamicPractice'] ?? '').toString().isNotEmpty ||
                    (e['lookingForSpouse'] ?? '').toString().isNotEmpty ||
                    (e['lookingForFamily'] ?? '').toString().isNotEmpty ||
                    (e['aboutFamily'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Hairline(),
                  const SizedBox(height: 18),
                  Text('IN THEIR WORDS',
                      style: AppType.eyebrow(DarkTokens.gold)),
                  const SizedBox(height: 12),
                  _prose('Their Islamic practice', e['islamicPractice']),
                  _prose('Looking for in a spouse', e['lookingForSpouse']),
                  _prose('Looking for in their family', e['lookingForFamily']),
                  _prose('About their family', e['aboutFamily']),
                ],

                if ((e['deenRelationship'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Hairline(),
                  const SizedBox(height: 18),
                  Text('ON SEEKING NIKAH',
                      style: AppType.eyebrow(DarkTokens.gold)),
                  const SizedBox(height: 12),
                  ...[
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

  Widget _prose(String label, dynamic value) {
    if (value == null || '$value'.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: AppType.inter(11.5,
                color: DarkTokens.muted(), weight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('“$value”',
            style: AppType.fraunces(15,
                color: DarkTokens.ivory, style: FontStyle.italic, height: 1.5)),
      ]),
    );
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
