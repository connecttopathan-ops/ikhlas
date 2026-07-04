import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tokens.dart';

/// Dashboard: Queue (actionable, oldest first) + All applications
/// (full history, newest first). Every card shows the complete record —
/// applicant identity, profile, answers, declaration, selfie, device &
/// location signals, gate verdict and decision audit trail.
class ReviewQueueScreen extends StatelessWidget {
  const ReviewQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: T.bg,
          title: Row(children: [
            Text('Ikhlas', style: T.fraunces(22, color: T.gold)),
            const SizedBox(width: 12),
            Text('Review', style: T.inter(14, color: T.muted)),
          ]),
          actions: [
            TextButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              child: Text('Sign out', style: T.inter(13, color: T.muted)),
            ),
            const SizedBox(width: 12),
          ],
          bottom: TabBar(
            indicatorColor: T.gold,
            labelStyle: T.inter(13.5, weight: FontWeight.w600),
            tabs: const [Tab(text: 'Queue'), Tab(text: 'All applications')],
          ),
        ),
        body: const TabBarView(children: [
          _ApplicationsList(queueOnly: true),
          _ApplicationsList(queueOnly: false),
        ]),
      ),
    );
  }
}

class _ApplicationsList extends StatelessWidget {
  final bool queueOnly;
  const _ApplicationsList({required this.queueOnly});

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('applications');
    if (queueOnly) query = query.where('queue', isEqualTo: 'human');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
              child:
                  Text('Error: ${snap.error}', style: T.inter(14, color: T.muted)));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = [...snap.data!.docs]..sort((a, b) {
            final ta = (a.data()['submittedAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final tb = (b.data()['submittedAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return queueOnly ? ta.compareTo(tb) : tb.compareTo(ta);
          });
        if (docs.isEmpty) {
          return Center(
            child: Text(
                queueOnly
                    ? 'Queue is clear, alhamdulillah.'
                    : 'No applications yet.',
                style: T.inter(15, color: T.muted)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: docs.length,
          itemBuilder: (_, i) =>
              _ApplicationCard(doc: docs[i], actionable: queueOnly),
        );
      },
    );
  }
}

class _ApplicationCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool actionable;
  const _ApplicationCard({required this.doc, required this.actionable});

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
    if (decision == 'approved' && _answers['e3_ribaPractice'] == 'exiting') {
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
    final reasons = ((auto['reasons'] as List?) ?? []).map((e) => '$e').toList();
    final decl = (_data['intentDeclaration'] as Map<String, dynamic>?) ?? {};
    final client = (_data['client'] as Map<String, dynamic>?) ?? {};
    final device = (client['device'] as Map<String, dynamic>?) ?? {};
    final location = client['location'] as Map<String, dynamic>?;
    final selfiePath =
        ((_data['verification'] as Map<String, dynamic>?)?['selfie']
            as Map<String, dynamic>?)?['storagePath'] as String?;
    final decision = _data['decision'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      constraints: const BoxConstraints(maxWidth: 980),
      decoration: BoxDecoration(
        color: T.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.hairline),
      ),
      child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.doc('users/$_uid').get(),
        builder: (context, userSnap) {
          final user = userSnap.data?.data() ?? {};
          final profile = (user['profile'] as Map<String, dynamic>?) ?? {};
          final dob = (user['dob'] as Timestamp?)?.toDate();
          final age = dob == null
              ? null
              : (DateTime.now().difference(dob).inDays ~/ 365);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- header: who ----
              Row(children: [
                Expanded(
                  child: Text(
                    '${user['email'] ?? _uid}'
                    '${user['phone'] != null ? '  ·  ${user['phone']}' : ''}',
                    style: T.inter(14.5, weight: FontWeight.w600, color: T.ivory),
                  ),
                ),
                Text(_fmt((_data['submittedAt'] as Timestamp?)?.toDate()),
                    style: T.inter(12, color: T.muted)),
              ]),
              const SizedBox(height: 4),
              Text('uid $_uid  ·  login ${user['authProvider'] ?? '—'}',
                  style: T.inter(11, color: T.muted)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (user['status'] != null)
                  _Chip(text: 'status: ${user['status']}', color: T.ivory),
                if (decision != null)
                  _Chip(
                      text: 'decision: $decision',
                      color:
                          decision == 'approved' ? T.approve : T.reject),
                _Chip(text: 'gate: ${auto['result'] ?? 'pending'}', color: T.gold),
                for (final r in reasons) _Chip(text: r, color: T.gold),
              ]),
              const SizedBox(height: 18),

              // ---- selfie + facts ----
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selfiePath != null) ...[
                    _SelfieThumb(storagePath: selfiePath),
                    const SizedBox(width: 20),
                  ],
                  Expanded(
                    child: Wrap(spacing: 24, runSpacing: 12, children: [
                      _Fact('Gender', user['gender']),
                      _Fact('Age', age),
                      _Fact('Marital', profile['maritalStatus']),
                      _Fact('Children', profile['hasChildren']),
                      _Fact('Revert', profile['revert']),
                      _Fact('City', profile['city']),
                      _Fact('Country', profile['country']),
                      _Fact('Relocate', profile['willingToRelocate']),
                      _Fact('Languages',
                          (profile['languages'] as List?)?.join(', ')),
                      _Fact('Ethnicity', profile['ethnicity']),
                      _Fact('Education', profile['education']),
                      _Fact('Profession', profile['profession']),
                      _Fact('Sect', profile['sect']),
                      _Fact('Madhhab', profile['madhhab']),
                      _Fact('Timeframe', _answers['timeframe']),
                      _Fact('Prayer', _answers['prayer']),
                      _Fact('Fin. ready', _answers['financiallyReady']),
                      _Fact('Family aware', _answers['familyAware']),
                      _Fact('E1 tawhid', _answers['e1_tawhid']),
                      _Fact('E2 riba', _answers['e2_riba']),
                      _Fact('E3 practice', _answers['e3_ribaPractice']),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ---- short answers ----
              _ShortAnswer('Why nikah, why now', sa['whyNow']),
              const SizedBox(height: 12),
              _ShortAnswer('Relationship with deen', sa['deenRelationship']),
              const SizedBox(height: 18),

              // ---- declaration ----
              _ShortAnswer(
                  'Intent declaration — signed "${decl['typedName'] ?? '—'}"',
                  ((decl['affirmations'] as List?) ?? []).join('  ·  ')),
              const SizedBox(height: 18),

              // ---- device & location signals ----
              Wrap(spacing: 24, runSpacing: 12, children: [
                _Fact(
                    'Device',
                    device.isEmpty
                        ? null
                        : '${device['manufacturer'] ?? ''} ${device['model'] ?? ''}'
                            ' · ${device['platform'] ?? ''} ${device['osVersion'] ?? ''}'
                            '${device['isPhysicalDevice'] == false ? ' · EMULATOR' : ''}'),
                _Fact('App version', device['appVersion']),
                _Fact('Location status', client['locationStatus']),
                if (location != null)
                  _LocationFact(
                      lat: (location['lat'] as num).toDouble(),
                      lng: (location['lng'] as num).toDouble(),
                      accuracyM: (location['accuracyM'] as num?)?.toDouble()),
              ]),

              // ---- decision audit / actions ----
              const SizedBox(height: 18),
              if (decision != null) ...[
                Container(height: 1, color: T.hairline),
                const SizedBox(height: 12),
                Text(
                  'Decided ${_fmt((_data['decidedAt'] as Timestamp?)?.toDate())}'
                  ' by ${_data['decidedBy'] == 'auto' ? 'gate engine (auto)' : _data['decidedBy']}'
                  '${_data['moderatorNotes'] != null ? '\nNotes: ${_data['moderatorNotes']}' : ''}',
                  style: T.inter(12.5, color: T.muted, height: 1.6),
                ),
              ] else if (widget.actionable) ...[
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
                    child: Text('Approve',
                        style: T.inter(14, weight: FontWeight.w600)),
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
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ]),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _fmt(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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

class _LocationFact extends StatelessWidget {
  final double lat;
  final double lng;
  final double? accuracyM;
  const _LocationFact({required this.lat, required this.lng, this.accuracyM});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LOCATION',
            style: T.inter(10, weight: FontWeight.w600, color: T.muted)),
        InkWell(
          onTap: () => launchUrl(
              Uri.parse('https://www.google.com/maps?q=$lat,$lng'),
              mode: LaunchMode.externalApplication),
          child: Text(
            '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
            '${accuracyM != null ? ' (±${accuracyM!.round()}m)' : ''}  ↗',
            style: T.inter(13.5, color: T.gold),
          ),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final dynamic value;
  const _Fact(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    if (value == null || '$value'.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: T.inter(10, weight: FontWeight.w600, color: T.muted)),
        Text('$value', style: T.inter(13.5, color: T.ivory)),
      ],
    );
  }
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
          Text('${text ?? "—"}', style: T.inter(13.5, color: T.ivory, height: 1.6)),
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
