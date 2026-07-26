import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'reports_queue.dart';
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: T.bg,
          title: Row(children: [
            Text('Ikhlaas', style: T.fraunces(22, color: T.gold)),
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
            tabs: const [
              Tab(text: 'Queue'),
              Tab(text: 'All applications'),
              Tab(text: 'Reports'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _ApplicationsList(queueOnly: true),
          _ApplicationsList(queueOnly: false),
          ReportsQueue(),
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
                      _Fact('City', (profile['residence'] as Map?)?['city']
                          ?? profile['city']),
                      _Fact('Town', (profile['residence'] as Map?)?['town']),
                      _Fact('State', (profile['residence'] as Map?)?['state']),
                      _Fact('Country', (profile['residence'] as Map?)?['country']
                          ?? profile['country']),
                      _Fact('Relocate', profile['willingToRelocate']),
                      _Fact('Height', () {
                        final h = profile['heightCm'] ?? profile['height'];
                        return h == null ? null : '$h cm';
                      }()),
                      _Fact('Languages',
                          (profile['languages'] as List?)?.join(', ')),
                      _Fact('Ethnicity', profile['ethnicity']),
                      _Fact('Nationality',
                          profile['nationality'] ?? profile['countryOfOrigin']),
                      _Fact('Residency', _lbl(profile['residencyStatus'])),
                      _Fact('Education', _lbl(profile['education'])),
                      _Fact('Profession', _lbl(profile['profession'])),
                      _Fact('Income', _lbl(profile['incomeBand'])),
                      _Fact('Family type', _lbl(profile['familyType'])),
                      _Fact('Family deen', _lbl(profile['familyReligiosity'])),
                      _Fact('Health', profile['healthDisclosure']),
                      _Fact('Sect', profile['sect']),
                      _Fact('Madhhab', profile['madhhab']),
                      _Fact('Timeframe', _lbl(_answers['timeframe'])),
                      _Fact('Prayer', _lbl(_answers['prayer'])),
                      _Fact('Fin. ready', _lbl(_answers['financiallyReady'])),
                      _Fact('Family aware', _lbl(_answers['familyAware'])),
                      _Fact('E1 tawhid', _lbl(_answers['e1_tawhid'])),
                      _Fact('E2 riba', _lbl(_answers['e2_riba'])),
                      _Fact('E3 practice', _lbl(_answers['e3_ribaPractice'])),
                      _Fact('E4 income', _lbl(_answers['e4_incomeSource'])),
                      // Section F (non-gating matching signal, from profile).
                      _Fact('Quran recitation', _lbl(
                          (profile['deenDetail'] as Map?)?['quranEngagement']
                              ?? (profile['deenDetail'] as Map?)?['quran'])),
                      _Fact('Quran memorization', _lbl(
                          (profile['deenDetail'] as Map?)?['quranMemorization'])),
                      _Fact('Islamic study', _lbl(
                          (profile['deenDetail'] as Map?)?['islamicStudy'])),
                      _Fact('Fasting', _lbl(
                          (profile['deenDetail'] as Map?)?['fasting']
                              ?? (profile['deenDetail'] as Map?)?['fastingBeyondRamadan'])),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ---- short answer (deen relationship is the only free-text
              // since the "right time" question was cut) ----
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

              // ---- government-ID (reviewed inline; the decision below covers
              // eligibility AND ID in one action) ----
              const SizedBox(height: 22),
              Container(height: 1, color: T.hairline),
              const SizedBox(height: 14),
              Text('IDENTITY VERIFICATION',
                  style: T.inter(11, weight: FontWeight.w700, color: T.gold)),
              const SizedBox(height: 12),
              _IdInlinePanel(uid: _uid),

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
                    child: Text('Approve (eligibility + ID)',
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
              ? Image.network(
                  snap.data!,
                  fit: BoxFit.cover,
                  loadingBuilder: (c, child, progress) => progress == null
                      ? child
                      : Center(
                          child: Text('…',
                              style: T.inter(11, color: T.muted))),
                  errorBuilder: (c, e, s) => Center(
                      child: Text('selfie\ncould not load',
                          textAlign: TextAlign.center,
                          style: T.inter(11, color: T.muted))),
                )
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
            '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'
            '${accuracyM != null ? ' (±${accuracyM!.round()}m)' : ''}  ↗',
            style: T.inter(13.5, color: T.gold),
          ),
        ),
      ],
    );
  }
}

/// Enum-key → human label for the questionnaire/profile values. Only the
/// multi-word keys need explicit entries; the rest fall back to a title-case
/// of the key (so new enum values still render legibly, never as raw snake).
const _adminLabels = {
  'high_school': 'High school',
  'islamic_studies': 'Islamic studies',
  'engineering_it': 'Engineering / IT',
  'under_3l': '< ₹3L', 'r3_6l': '₹3–6L', 'r6_12l': '₹6–12L',
  'r12_24l': '₹12–24L', 'r24_50l': '₹24–50L', 'r50l_plus': '₹50L+',
  'prefer_not': 'Prefer not to say',
  'permanent_resident': 'Permanent resident', 'long_term_visa': 'Long-term visa',
  'work_visa': 'Work visa', 'student_visa': 'Student visa',
  'very_practising': 'Very practising', 'structured_self': 'Structured self-study',
  'not_halal': 'Not halal', 'not_affirm': 'Do not affirm',
  'five_daily': 'Five daily', 'never_married': 'Never married',
  '6m': 'Within 6 months', '6_12m': '6–12 months', '12_24m': '12–24 months',
  'exiting': 'Exiting debt', 'will_involve': 'Will involve',
  // Section F — split Quran + fasting (post-questionnaire-rewrite values).
  'daily_recitation': 'Daily recitation', 'learning_to_read': 'Learning to read',
  'seeking': 'Seeking to start', 'juz_amma_plus': 'Juz ʿAmma and more',
  'some_surahs': 'Some surahs', 'hafiz': 'Hafiz (complete)',
  'beyond_ramadan_regularly': 'Ramadan + regularly beyond',
  'beyond_ramadan_sometimes': 'Ramadan + sometimes beyond',
  'ramadan_only': 'Ramadan only', 'not_ramadan': 'Not fasting Ramadan currently',
};

String _pretty(String s) => s
    .split('_')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String? _lbl(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  if (s.isEmpty) return null;
  return _adminLabels[s] ?? _pretty(s);
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

/// Read-only government-ID review, folded into the application card so the
/// moderator reviews eligibility AND identity in one place, then makes a
/// SINGLE decision with the Approve / Soft-reject buttons below. Approving
/// finalizes the ID (server trigger); rejecting purges it from quarantine.
class _IdInlinePanel extends StatefulWidget {
  final String uid;
  const _IdInlinePanel({required this.uid});
  @override
  State<_IdInlinePanel> createState() => _IdInlinePanelState();
}

class _IdInlinePanelState extends State<_IdInlinePanel> {
  static const _imgBase =
      'https://asia-south1-ikhlas-caecf.cloudfunctions.net/idDocImageRaw';
  String? _idUrl, _selfieUrl;
  bool _loading = false;

  Future<void> _reveal() async {
    setState(() => _loading = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw 'Not signed in';
      setState(() {
        _idUrl = '$_imgBase?uid=${widget.uid}&which=id&token=$token';
        _selfieUrl = '$_imgBase?uid=${widget.uid}&which=selfie&token=$token';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load images: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .doc('idReview/${widget.uid}')
          .snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data();
        if (d == null) {
          return Text('No ID submitted with this application.',
              style: T.inter(13, color: T.muted));
        }
        final pending = d['analysisPending'] == true;
        final nameScore = d['nameMatchScore'];
        final status = (d['status'] ?? '').toString();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 24, runSpacing: 10, children: [
            _stat('Document', (d['type'] ?? '—').toString().toUpperCase()),
            _stat('ID status', status.isEmpty ? '—' : status),
            _stat('Name match',
                pending ? 'analysing…' : nameScore == null
                    ? '—' : '${((nameScore as num) * 100).round()}%'),
            _stat('OCR name',
                pending ? 'analysing…' : (d['ocrName'] ?? '—').toString()),
            _stat('ID last4',
                pending ? 'analysing…' : (d['last4'] ?? '—').toString()),
            _stat('Face on ID', _yn(d['idFacePresent'])),
            _stat('Face on selfie', _yn(d['selfieFacePresent'])),
            _stat('Liveness', _yn(d['livenessPassed'])),
          ]),
          const SizedBox(height: 14),
          if (_idUrl == null && !_loading)
            OutlinedButton.icon(
              onPressed: _reveal,
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: Text('Reveal ID + selfie', style: T.inter(13)),
            ),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator()),
          if (_idUrl != null)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _labelled('ID document', _idUrl!)),
              const SizedBox(width: 14),
              Expanded(child: _labelled('Selfie (on file)', _selfieUrl!)),
            ]),
        ]);
      },
    );
  }

  Widget _labelled(String label, String url) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: T.inter(11.5, color: T.muted)),
            const Spacer(),
            Text('tap to zoom', style: T.inter(10.5, color: T.gold)),
          ]),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _openFull(url, label),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(url,
                  height: 460, width: double.infinity, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                      height: 460,
                      alignment: Alignment.center,
                      color: Colors.black26,
                      child: Text('could not load',
                          style: T.inter(12, color: T.muted)))),
            ),
          ),
        ],
      );

  void _openFull(String url, String label) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(.92),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6,
              child: Center(child: Image.network(url, fit: BoxFit.contain)),
            ),
          ),
          Positioned(
            top: 8, left: 12,
            child: Text(label,
                style: T.inter(13, weight: FontWeight.w600, color: Colors.white)),
          ),
          Positioned(
            top: 0, right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 26),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String k, String v) => SizedBox(
        width: 150,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: T.inter(11, color: T.muted)),
          const SizedBox(height: 2),
          Text(v, style: T.inter(13.5, color: T.ivory)),
        ]),
      );

  String _yn(dynamic v) => v == true ? 'Yes' : v == false ? 'No' : '—';
}
