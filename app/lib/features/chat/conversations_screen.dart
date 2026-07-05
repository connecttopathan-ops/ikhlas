import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../data/repositories/chat_repository.dart';

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
                    for (final d in docs) _ConvTile(doc: d),
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

class _ConvTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _ConvTile({required this.doc});

  static const _stageLabel = {
    'intro': 'Introduction',
    'deepening': 'Deepening',
    'family': 'Family stage',
    'closed_dua': 'Ended with dua',
    'closed_timeout': 'Rested (14-day)',
    'success': 'Proceeding to nikah',
  };

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final stage = d['stage'] as String? ?? 'intro';
    final closed = ConversationsScreen.isClosed(stage);
    final me = FirebaseAuth.instance.currentUser!.uid;
    final other = (d['participants'] as List).firstWhere((p) => p != me,
        orElse: () => '');
    final adab = (d['adabAcknowledged'] as Map?) ?? {};
    final needsAdab = adab[me] != true;

    return InkWell(
      onTap: () => context.go('/chat/${doc.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DarkTokens.hairline(closed ? .2 : .4)),
        ),
        child: Row(children: [
          Opacity(
            opacity: closed ? .4 : 1,
            child: const GirihMark(size: 34, opacity: .7),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_stageLabel[stage] ?? stage,
                      style: AppType.inter(14.5,
                          weight: FontWeight.w500,
                          color: closed
                              ? DarkTokens.muted()
                              : DarkTokens.ivory)),
                  const SizedBox(height: 2),
                  Text(
                      needsAdab && !closed
                          ? 'Tap to begin — adab guidelines first'
                          : 'Member ${other.toString().substring(0, other.toString().length.clamp(0, 6))}',
                      style:
                          AppType.inter(12, color: DarkTokens.muted())),
                ]),
          ),
          if (!closed)
            Icon(Icons.chevron_right, size: 20, color: DarkTokens.muted(.6)),
        ]),
      ),
    );
  }
}
