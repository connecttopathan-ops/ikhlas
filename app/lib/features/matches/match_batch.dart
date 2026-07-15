import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../providers/application_provider.dart';
import 'match_detail_screen.dart';
import 'member_photo.dart';

/// Today's curated batch (PRD §4.2) — deen-first profile cards, exactly
/// what the server generated, never a browse surface. Photos arrive with
/// the signed-URL + watermark pipeline; until then every card carries the
/// girih silhouette, which the blur-by-default privacy mode requires
/// anyway for most members.
final todayEntriesProvider =
    StreamProvider<QuerySnapshot<Map<String, dynamic>>>((ref) {
  ref.watch(authStateProvider); // rebind on account change
  return ref.read(applicationRepositoryProvider).todayEntriesStream();
});

class MatchBatch extends ConsumerStatefulWidget {
  const MatchBatch({super.key});
  @override
  ConsumerState<MatchBatch> createState() => _MatchBatchState();
}

class _MatchBatchState extends ConsumerState<MatchBatch> {
  bool _requesting = false;

  Future<void> _requestBatch() async {
    setState(() => _requesting = true);
    await _generate(surfaceError: true);
    if (mounted) setState(() => _requesting = false);
  }

  /// Pull-to-refresh: ask the server to (re)generate today's batch. The
  /// snapshots() stream then updates on its own when entries are written.
  Future<void> _onRefresh() async {
    await HapticFeedback.selectionClick();
    await _generate(surfaceError: false);
  }

  Future<void> _generate({required bool surfaceError}) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('generateMyBatch')
          .call();
    } catch (_) {
      // An empty pool returns cleanly; a real failure surfaces on demand only.
      if (surfaceError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not check for matches. Please try again.',
                style: AppType.inter(13))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(todayEntriesProvider);
    return entries.when(
      loading: () => const Center(
          child: SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, __) => _errorState(),
      data: (snap) {
        if (snap.docs.isEmpty) return _resting();
        // Rank by alignment band, never by raw score (PRD §4.2). Score is
        // only a within-band tiebreak here.
        const bandRank = {'strong': 3, 'good': 2, 'some': 1};
        final docs = [...snap.docs]..sort((a, b) {
            final ba = bandRank[a.data()['band']] ?? 0;
            final bb = bandRank[b.data()['band']] ?? 0;
            if (bb != ba) return bb - ba;
            return (b.data()['score'] as num? ?? 0)
                .compareTo(a.data()['score'] as num? ?? 0);
          });
        return RefreshIndicator(
          onRefresh: _onRefresh,
          color: DarkTokens.gold,
          backgroundColor: DarkTokens.bg,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Text("TODAY'S MATCHES", style: AppType.eyebrow(DarkTokens.gold)),
              const SizedBox(height: 6),
              Text('Quality over quantity — ${docs.length} today.',
                  style: AppType.inter(12.5, color: DarkTokens.muted())),
              const SizedBox(height: 16),
              for (final d in docs) _MatchCard(doc: d),
            ],
          ),
        );
      },
    );
  }

  Widget _errorState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const GirihMark(size: 64, opacity: .6),
          const SizedBox(height: 20),
          Text("Couldn't load your matches",
              style: AppType.fraunces(20, color: DarkTokens.ivory)),
          const SizedBox(height: 8),
          Text('Check your connection and try again.',
              textAlign: TextAlign.center,
              style: AppType.inter(13, color: DarkTokens.muted())),
          const SizedBox(height: 18),
          QuietLink(
              linkText: _requesting ? 'Retrying…' : 'Retry',
              onTap: _requesting ? null : _requestBatch),
        ]),
      );

  Widget _resting() => RefreshIndicator(
        onRefresh: _onRefresh,
        color: DarkTokens.gold,
        backgroundColor: DarkTokens.bg,
        child: LayoutBuilder(
          builder: (context, c) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: c.maxHeight,
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const GirihMark(size: 72, opacity: .7),
                    const SizedBox(height: 24),
                    Text('No matches yet today',
                        style: AppType.fraunces(22, color: DarkTokens.ivory)),
                    const SizedBox(height: 8),
                    Text(
                      'Your batch arrives after Fajr. Quality over quantity — '
                      'we never pad the list.',
                      textAlign: TextAlign.center,
                      style:
                          AppType.inter(13, color: DarkTokens.muted(), height: 1.6),
                    ),
                    const SizedBox(height: 18),
                    QuietLink(
                        linkText: _requesting ? 'Checking…' : 'Check for matches',
                        onTap: _requesting ? null : _requestBatch),
                  ]),
                ),
              ),
            ],
          ),
        ),
      );
}

class _MatchCard extends ConsumerStatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _MatchCard({required this.doc});
  @override
  ConsumerState<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends ConsumerState<_MatchCard> {
  bool _busy = false;

  Future<void> _act(String action) async {
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      await ref
          .read(applicationRepositoryProvider)
          .setEntryAction(widget.doc.id, action);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _prayerLabel = {
    'five_daily': 'Prays five daily',
    'most': 'Prays most salah',
  };
  static const _timeframeLabel = {
    '6m': 'Nikah within 6 months',
    '6_12m': 'Nikah in 6–12 months',
    '12_24m': 'Nikah in 12–24 months',
  };
  static const _bandLabel = {
    'strong': 'Strong alignment',
    'good': 'Good alignment',
    'some': 'Some alignment',
  };

  @override
  Widget build(BuildContext context) {
    final e = widget.doc.data();
    final action = e['action'] as String?;
    final compat = (e['compatibility'] as List?)?.cast<String>() ?? [];
    final band = _bandLabel[e['band']];
    final divergence = e['divergence'] as String?;
    final prompts = (e['bioPrompts'] as List?) ?? [];
    final firstPrompt = prompts.isEmpty
        ? null
        : (prompts.first as Map)['answer'] as String?;

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MatchDetailScreen(
              entryId: widget.doc.id, entry: e))),
      borderRadius: BorderRadius.circular(14),
      child: Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DarkTokens.hairline(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (band != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: DarkTokens.gold.withOpacity(.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(band.toUpperCase(),
                  style: AppType.inter(10.5,
                      weight: FontWeight.w600, color: DarkTokens.gold)
                      .copyWith(letterSpacing: 1)),
            ),
            const SizedBox(height: 14),
          ],
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Photo through the server pipeline — blurred/watermarked per
            // the member's privacy mode, girih silhouette when hidden.
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DarkTokens.hairline(.4)),
              ),
              child: e['hasPhotos'] == true
                  ? MemberPhoto(
                      ownerUid: widget.doc.id, width: 84, height: 104)
                  : const SizedBox(
                      width: 84,
                      height: 104,
                      child: Center(child: GirihMark(size: 44, opacity: .55))),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${_prayerLabel[e['prayer']] ?? 'Deen-focused'}'
                      '${e['revert'] == true ? ' · Revert' : ''}',
                      style: AppType.eyebrow(DarkTokens.gold)),
                  const SizedBox(height: 6),
                  Text('${e['displayName'] ?? 'Member'}, ${e['age'] ?? '—'}',
                      style: AppType.fraunces(24, color: DarkTokens.ivory)),
                  const SizedBox(height: 3),
                  Text(
                      [
                        e['city'],
                        e['profession'],
                        _timeframeLabel[e['timeframe']],
                      ].whereType<String>().join(' · '),
                      style: AppType.inter(12.5, color: DarkTokens.muted(.62))),
                  if (e['ribaDisclosureBadge'] == true) ...[
                    const SizedBox(height: 5),
                    Text('Honest disclosure: exiting legacy debt',
                        style: AppType.inter(11.5, color: DarkTokens.gold)),
                  ],
                ],
              ),
            ),
          ]),
          if (compat.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final c in compat)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(children: [
                  const DiamondBullet(size: 5),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(c,
                          style:
                              AppType.inter(13, color: DarkTokens.ivory))),
                ]),
              ),
          ],
          // The one honest divergence — always present (PRD §4.2). It is
          // what proves the engine advises rather than sells.
          if (divergence != null && divergence.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Differs on:  ',
                  style: AppType.inter(12.5,
                      weight: FontWeight.w600, color: DarkTokens.muted(.8))),
              Expanded(
                child: Text(divergence,
                    style: AppType.inter(12.5,
                        color: DarkTokens.muted(.8), height: 1.45)),
              ),
            ]),
          ],
          if (firstPrompt != null && firstPrompt.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('“$firstPrompt”',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppType.fraunces(14.5,
                    color: DarkTokens.muted(.75), style: FontStyle.italic)),
          ],
          const SizedBox(height: 16),
          if (action == null)
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: PrimaryCta(
                      label: 'Express interest',
                      loading: _busy,
                      onPressed: _busy ? null : () => _act('interested')),
                ),
              ),
              const SizedBox(width: 14),
              QuietLink(
                  linkText: 'Pass',
                  onTap: _busy ? null : () => _act('passed')),
            ])
          else
            Row(children: [
              const DiamondBullet(),
              const SizedBox(width: 10),
              Text(
                  action == 'interested'
                      ? 'Interest expressed — if it is mutual, a conversation opens.'
                      : 'Passed, respectfully.',
                  style: AppType.inter(12.5, color: DarkTokens.muted())),
            ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Tap to view full profile',
                style: AppType.inter(11.5, color: DarkTokens.muted(.5))),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 14, color: DarkTokens.muted(.5)),
          ]),
        ],
      ),
      ),
    );
  }
}
