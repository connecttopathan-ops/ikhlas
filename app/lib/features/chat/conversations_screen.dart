import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../data/repositories/chat_repository.dart';
import 'chat_avatar.dart';

final chatRepositoryProvider = Provider<ChatRepository>((_) => ChatRepository());

final conversationsProvider =
    StreamProvider<QuerySnapshot<Map<String, dynamic>>>((ref) {
  return ref.read(chatRepositoryProvider).conversationsStream();
});

/// Conversation list. Enforces the 3-active-conversation cap visually
/// (the cap itself is enforced server-side at mutual-interest time).
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  static bool isClosed(String? stage) => stage?.startsWith('closed_') ?? false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convs = ref.watch(conversationsProvider);
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    return IkhlasScaffold(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.screenMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            Row(children: [
              IconButton(
                onPressed: () => context.go('/home'),
                icon: Icon(Icons.arrow_back,
                    size: 22, color: DarkTokens.muted(.7)),
              ),
              const SizedBox(width: 4),
              Text('Conversations',
                  style: AppType.fraunces(26, color: DarkTokens.ivory)),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: convs.when(
                loading: () => const Center(
                    child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))),
                error: (e, _) => Center(
                    child: Text('Could not load conversations.',
                        style: AppType.inter(13, color: DarkTokens.muted()))),
                data: (snap) {
                  final docs = [...snap.docs]..sort((a, b) {
                      final ta = (a.data()['lastMessageAt'] ??
                              a.data()['createdAt']) as Timestamp?;
                      final tb = (b.data()['lastMessageAt'] ??
                              b.data()['createdAt']) as Timestamp?;
                      return (tb?.millisecondsSinceEpoch ?? 0)
                          .compareTo(ta?.millisecondsSinceEpoch ?? 0);
                    });
                  final active = docs
                      .where((d) => !isClosed(d.data()['stage'] as String?))
                      .length;
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const GirihMark(size: 64, opacity: .7),
                            const SizedBox(height: 20),
                            Text('No conversations yet',
                                style: AppType.fraunces(20,
                                    color: DarkTokens.ivory)),
                            const SizedBox(height: 8),
                            Text(
                                'When interest is mutual, a guarded '
                                'conversation opens here.',
                                textAlign: TextAlign.center,
                                style: AppType.inter(13,
                                    color: DarkTokens.muted(), height: 1.6)),
                          ]),
                    );
                  }
                  return ListView(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('$active of 3 active — serious seekers, '
                          'not collectors.',
                          style: AppType.inter(12, color: DarkTokens.muted())),
                    ),
                    for (final d in docs) _ConvTile(doc: d, me: me),
                  ]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConvTile extends ConsumerWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String me;
  const _ConvTile({required this.doc, required this.me});

  static const _stageLabel = {
    'intro': 'Introduction',
    'deepening': 'Deepening',
    'family': 'Family stage',
    'closed_dua': 'Ended with dua',
    'closed_timeout': 'Rested (14-day)',
    'success': 'Proceeding to nikah',
  };

  // One delivery mark per (conv, message) — build() runs often; don't spam.
  static final Set<String> _deliveredSeen = {};

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul',
    'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String _time(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
      return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
    }
    return '${d.day} ${_months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = doc.data();
    final stage = d['stage'] as String? ?? 'intro';
    final closed = ConversationsScreen.isClosed(stage);
    final adab = (d['adabAcknowledged'] as Map?) ?? {};
    final needsAdab = adab[me] != true;

    final participants = (d['participants'] as List?)?.cast<String>() ?? [];
    final other = participants.firstWhere((p) => p != me, orElse: () => '');
    final profiles = (d['profiles'] as Map?) ?? const {};
    final otherProfile = (profiles[other] as Map?)?.cast<String, dynamic>();
    final name = otherProfile?['displayName'] as String? ?? 'Your match';
    final photoReveal = (d['photoReveal'] as Map?) ?? const {};

    final lastAt = d['lastMessageAt'] as Timestamp?;
    final lastText = d['lastMessageText'] as String?;
    final lastFrom = d['lastMessageFrom'] as String?;
    final readUpTo = (d['readUpTo'] as Map?) ?? const {};
    final myRead = readUpTo[me] as Timestamp?;
    final unread = !closed &&
        lastFrom != null &&
        lastFrom != me &&
        lastAt != null &&
        (myRead == null || myRead.compareTo(lastAt) < 0);

    // Mark delivered when this device sees an inbound message I haven't got yet.
    if (unread) {
      final delivered = (d['deliveredUpTo'] as Map?) ?? const {};
      final myDeliv = delivered[me] as Timestamp?;
      if (myDeliv == null || myDeliv.compareTo(lastAt) < 0) {
        final key = '${doc.id}|${lastAt.millisecondsSinceEpoch}';
        if (_deliveredSeen.add(key)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(chatRepositoryProvider).markDelivered(doc.id);
          });
        }
      }
    }

    // Subtitle: the last message preview, else the stage/adab hint.
    String subtitle;
    if (closed) {
      subtitle = _stageLabel[stage] ?? 'This conversation has ended';
    } else if (lastText != null && lastText.isNotEmpty) {
      subtitle = (lastFrom == me ? 'You: ' : '') + lastText;
    } else if (needsAdab) {
      subtitle = 'Tap to begin — adab guidelines first';
    } else {
      subtitle = 'Say salaam to begin';
    }

    return InkWell(
      onTap: () => context.go('/chat/${doc.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DarkTokens.hairline(closed ? .2 : .4)),
        ),
        child: Row(children: [
          Opacity(
            opacity: closed ? .45 : 1,
            child: ChatAvatar(
                ownerUid: other,
                profile: otherProfile,
                photoRevealed: photoReveal[other] == true,
                size: 46),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.inter(15,
                              weight: FontWeight.w600,
                              color: closed
                                  ? DarkTokens.muted()
                                  : DarkTokens.ivory)),
                    ),
                    if (lastAt != null) ...[
                      const SizedBox(width: 8),
                      Text(_time(lastAt),
                          style: AppType.inter(11,
                              color: unread
                                  ? DarkTokens.gold
                                  : DarkTokens.muted(.6))),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Row(children: [
                    Expanded(
                      child: Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.inter(12.5,
                              weight:
                                  unread ? FontWeight.w600 : FontWeight.w400,
                              color: unread
                                  ? DarkTokens.ivory
                                  : DarkTokens.muted())),
                    ),
                    if (unread) ...[
                      const SizedBox(width: 8),
                      Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: DarkTokens.gold)),
                    ],
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }
}
