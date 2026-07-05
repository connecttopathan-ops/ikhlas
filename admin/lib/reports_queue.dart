import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Report queue (PRD §4.6) — open reports, auto-frozen conversations,
/// with one-click dismiss / warn / suspend / ban. Ban keys the phone in
/// the ban registry to block re-entry.
class ReportsQueue extends StatelessWidget {
  const ReportsQueue({super.key});

  static const _reasonLabel = {
    'not_serious': 'Not serious about marriage',
    'already_married': 'Already married (undisclosed)',
    'inappropriate': 'Inappropriate content',
    'off_app': 'Asking to move off-app',
    'fake_profile': 'Fake profile',
    'harassment': 'Harassment',
  };

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('reports')
        .where('status', isEqualTo: 'open');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = [...snap.data!.docs]..sort((a, b) {
            final ta = (a.data()['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final tb = (b.data()['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return ta.compareTo(tb); // oldest first
          });
        if (docs.isEmpty) {
          return Center(
              child: Text('No open reports.',
                  style: T.inter(15, color: T.muted)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: docs.length,
          itemBuilder: (_, i) => _ReportCard(doc: docs[i]),
        );
      },
    );
  }
}

class _ReportCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _ReportCard({required this.doc});
  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _busy = false;

  Future<void> _act(String action) async {
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('moderateReport')
          .call({
        'reportId': widget.doc.id,
        'reportedUid': widget.doc.data()['reportedUid'],
        'action': action,
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data();
    final reason = ReportsQueue._reasonLabel[d['reason']] ?? d['reason'];
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(22),
      constraints: const BoxConstraints(maxWidth: 760),
      decoration: BoxDecoration(
        color: T.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.reject.withOpacity(.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(reason, style: T.fraunces(18, color: T.ivory)),
        const SizedBox(height: 8),
        Text('Reported: ${d['reportedUid']}',
            style: T.inter(12.5, color: T.muted)),
        Text('By: ${d['reporterUid']}', style: T.inter(12.5, color: T.muted)),
        if ((d['detail'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(d['detail'], style: T.inter(13.5, color: T.ivory)),
        ],
        const SizedBox(height: 18),
        if (_busy)
          const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
        else
          Wrap(spacing: 10, runSpacing: 10, children: [
            _btn('Dismiss', T.muted, () => _act('dismiss')),
            _btn('Warn', T.gold, () => _act('warn')),
            _btn('Suspend 7d', T.reject, () => _act('suspend')),
            _btn('Ban', T.reject, () => _act('ban')),
          ]),
      ]),
    );
  }

  Widget _btn(String label, Color c, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
            side: BorderSide(color: c.withOpacity(.6))),
        child: Text(label, style: T.inter(13, color: c)),
      );
}
