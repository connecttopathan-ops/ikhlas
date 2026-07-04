import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Review queue — escalated (human-needed) applications, oldest first.
/// Shows structured answers, short answers, gate reasons and the
/// verification selfie; one-click approve / soft-reject with notes.
/// Firestore writes are permitted by the moderator claim in the rules.
class ReviewQueueScreen extends StatelessWidget {
  const ReviewQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('applications')
        .where('queue', isEqualTo: 'human');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: T.bg,
        title: Row(children: [
          Text('Ikhlas', style: T.fraunces(22, color: T.gold)),
          const SizedBox(width: 12),
          Text('Review queue', style: T.inter(14, color: T.muted)),
        ]),
        actions: [
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            child: Text('Sign out', style: T.inter(13, color: T.muted)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text('Error: ${snap.error}',
                    style: T.inter(14, color: T.muted)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = [...snap.data!.docs]..sort((a, b) {
              final ta = a.data()['submittedAt'] as Timestamp?;
              final tb = b.data()['submittedAt'] as Timestamp?;
              return (ta?.millisecondsSinceEpoch ?? 0)
                  .compareTo(tb?.millisecondsSinceEpoch ?? 0); // oldest first
            });
          if (docs.isEmpty) {
            return Center(
              child: Text('Queue is clear, alhamdulillah.',
                  style: T.inter(15, color: T.muted)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: docs.length,
            itemBuilder: (_, i) => _ApplicationCard(doc: docs[i]),
          );
        },
      ),
    );
  }
}

class _ApplicationCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _ApplicationCard({required this.doc});

  @override
  State<_ApplicationCard> createState() => _ApplicationCardState();
}

class _ApplicationCardState extends State<_ApplicationCard> {
  final _notes = TextEditingController();
  bool _busy = false;

  Map<String, dynamic> get _data => widget.doc.data();
  Map<String, dynamic> get _answers =>
      (_data['answers'] as Map<String, dynamic>?) ?? {};
  String get _uid => widget.doc.id;

  Future<void> _decide(String decision) async {
    setState(() => _busy = true);
    final db = FirebaseFirestore.instance;
    final moderatorUid = FirebaseAuth.instance.currentUser!.uid;
    final batch = db.batch();

    batch.update(db.doc('applications/$_uid'), {
      'decision': decision,
      'decidedAt': FieldValue.serverTimestamp(),
      'decidedBy': moderatorUid,
      'queue': 'done',
      if (_notes.text.trim().isNotEmpty) 'moderatorNotes': _notes.text.trim(),
    });
    final userUpdate = <String, dynamic>{'status': decision};
    if (decision == 'approved' &&
        _answers['e3_ribaPractice'] == 'exiting') {
      userUpdate['ribaDisclosureBadge'] = true;
    }
    batch.update(db.doc('users/$_uid'), userUpdate);

    try {
      await batch.commit();
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
    final sa = (_answers['shortAnswers'] as Map<String, dynamic>?) ?? {};
    final auto = (_data['autoScore'] as Map<String, dynamic>?) ?? {};
    final reasons =
        ((auto['reasons'] as List?) ?? []).map((e) => '$e').toList();
    final selfiePath = ((_data['verification']
            as Map<String, dynamic>?)?['selfie']
        as Map<String, dynamic>?)?['storagePath'] as String?;
    final submitted = (_data['submittedAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      constraints: const BoxConstraints(maxWidth: 900),
      decoration: BoxDecoration(
        color: T.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Application $_uid',
                  style: T.inter(13, weight: FontWeight.w600, color: T.muted)),
            ),
            if (submitted != null)
              Text('${submitted.day}/${submitted.month}/${submitted.year}',
                  style: T.inter(12, color: T.muted)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in reasons) _Chip(text: r, color: T.gold),
          ]),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selfiePath != null) ...[
                _SelfieThumb(storagePath: selfiePath),
                const SizedBox(width: 20),
              ],
              Expanded(
                child: Wrap(spacing: 24, runSpacing: 10, children: [
                  _Fact('Timeframe', _answers['timeframe']),
                  _Fact('Prayer', _answers['prayer']),
                  _Fact('Financially ready', _answers['financiallyReady']),
                  _Fact('Family aware', _answers['familyAware']),
                  _Fact('E1 tawhid', _answers['e1_tawhid']),
                  _Fact('E2 riba', _answers['e2_riba']),
                  _Fact('E3 practice', _answers['e3_ribaPractice']),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ShortAnswer('Why nikah, why now', sa['whyNow']),
          const SizedBox(height: 12),
          _ShortAnswer('Relationship with deen', sa['deenRelationship']),
          const SizedBox(height: 18),
          TextField(
            controller: _notes,
            style: T.inter(13.5, color: T.ivory),
            decoration: InputDecoration(
              hintText: 'Moderator notes (optional)',
              hintStyle: T.inter(13.5, color: T.muted),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: T.hairline)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: T.gold)),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            FilledButton(
              onPressed: _busy ? null : () => _decide('approved'),
              style: FilledButton.styleFrom(
                  backgroundColor: T.approve, foregroundColor: T.ivory),
              child: Text('Approve', style: T.inter(14, weight: FontWeight.w600)),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _busy ? null : () => _decide('soft_rejected'),
              style: FilledButton.styleFrom(
                  backgroundColor: T.reject, foregroundColor: T.ivory),
              child: Text('Soft reject',
                  style: T.inter(14, weight: FontWeight.w600)),
            ),
            if (_busy) ...[
              const SizedBox(width: 16),
              const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ]),
        ],
      ),
    );
  }
}

class _SelfieThumb extends StatelessWidget {
  final String storagePath;
  const _SelfieThumb({required this.storagePath});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(storagePath).getDownloadURL(),
      builder: (context, snap) {
        return Container(
          width: 130,
          height: 170,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: T.hairline),
          ),
          child: snap.hasData
              ? Image.network(snap.data!, fit: BoxFit.cover)
              : Center(
                  child: Text(snap.hasError ? 'selfie\nunavailable' : '…',
                      textAlign: TextAlign.center,
                      style: T.inter(11, color: T.muted))),
        );
      },
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final dynamic value;
  const _Fact(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: T.inter(10, weight: FontWeight.w600, color: T.muted)),
          Text('${value ?? "—"}', style: T.inter(13.5, color: T.ivory)),
        ],
      );
}

class _ShortAnswer extends StatelessWidget {
  final String label;
  final dynamic text;
  const _ShortAnswer(this.label, this.text);
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: T.inter(10, weight: FontWeight.w600, color: T.muted)),
          const SizedBox(height: 4),
          Text('${text ?? "—"}',
              style: T.inter(13.5, color: T.ivory, height: 1.6)),
        ],
      );
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(.5)),
        ),
        child: Text(text, style: T.inter(11.5, color: color)),
      );
}
