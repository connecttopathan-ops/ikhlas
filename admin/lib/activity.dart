import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Activity dashboard — platform KPIs + a searchable per-member list, both
/// read from the hourly rollup (metrics/overview + userActivity/*). Cheap:
/// the admin never scans raw matches/messages, only pre-computed docs.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _search = TextEditingController();
  String _sort = 'lastActive';
  String _q = '';
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('refreshMetrics')
          .call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _overview(),
                const SizedBox(height: 26),
                _controls(),
                const SizedBox(height: 16),
                _memberList(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- overview tiles ----
  Widget _overview() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.doc('metrics/overview').snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? const {};
        final by = (d['byStatus'] as Map?) ?? const {};
        final tiles = <Widget>[
          _tile('Members', d['members'], sub: '${by['approved'] ?? 0} approved'),
          _tile('Active this week', d['activeThisWeek']),
          _tile('Conversations', d['conversationsOpen'],
              sub: '${d['familyConversations'] ?? 0} at family stage'),
          _tile('Family Stage', d['familyStageInitiations'],
              accent: T.approve, sub: 'cumulative'),
          _tile('Open reports', d['openReports'],
              accent: (d['openReports'] ?? 0) > 0 ? T.reject : null),
          _tile('Digests pending', d['digestsPending'], accent: T.gold),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 14, runSpacing: 14, children: tiles),
            const SizedBox(height: 10),
            Row(children: [
              Text('as of ${_fmt(d['updatedAt'])}',
                  style: T.inter(11.5, color: T.muted)),
              const SizedBox(width: 14),
              _refreshing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton.icon(
                      onPressed: _refresh,
                      icon: Icon(Icons.refresh, size: 15, color: T.gold),
                      label: Text('Refresh now',
                          style: T.inter(12, color: T.gold)),
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    ),
            ]),
          ],
        );
      },
    );
  }

  Widget _tile(String label, dynamic value, {String? sub, Color? accent}) {
    return Container(
      width: 168,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: T.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (accent ?? T.gold).withOpacity(.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: T.inter(10.5, weight: FontWeight.w700, color: T.muted)),
        const SizedBox(height: 8),
        Text('${value ?? '—'}',
            style: T.fraunces(30, color: accent ?? T.ivory)),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(sub, style: T.inter(11.5, color: T.muted)),
        ],
      ]),
    );
  }

  // ---- search + sort ----
  Widget _controls() {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          style: T.inter(13.5, color: T.ivory),
          decoration: InputDecoration(
            hintText: 'Search name, email or uid',
            hintStyle: T.inter(13.5, color: T.muted),
            prefixIcon: Icon(Icons.search, size: 18, color: T.muted),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: T.hairline)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: T.gold)),
          ),
        ),
      ),
      const SizedBox(width: 20),
      Text('Sort', style: T.inter(12.5, color: T.muted)),
      const SizedBox(width: 8),
      DropdownButton<String>(
        value: _sort,
        dropdownColor: T.panel,
        underline: const SizedBox.shrink(),
        style: T.inter(13, color: T.ivory),
        items: const [
          DropdownMenuItem(value: 'lastActive', child: Text('Last active')),
          DropdownMenuItem(value: 'matchesReceived', child: Text('Matches')),
          DropdownMenuItem(value: 'messagesSent', child: Text('Messages')),
          DropdownMenuItem(
              value: 'openReportsAgainst', child: Text('Open reports')),
        ],
        onChanged: (v) => setState(() => _sort = v ?? 'lastActive'),
      ),
    ]);
  }

  // ---- per-member list ----
  Widget _memberList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('userActivity').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snap.data!.docs;
        if (_q.isNotEmpty) {
          docs = docs.where((d) {
            final m = d.data();
            final hay = [
              m['displayName'], m['email'], m['uid'],
            ].where((e) => e != null).join(' ').toLowerCase();
            return hay.contains(_q);
          }).toList();
        }
        int num(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;
        int lastMs(Map m) =>
            (m['lastActiveAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        docs = [...docs]..sort((a, b) {
            if (_sort == 'lastActive') return lastMs(b.data()).compareTo(lastMs(a.data()));
            return num(b.data(), _sort).compareTo(num(a.data(), _sort));
          });
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 30),
            child: Text('No members yet — the rollup runs hourly.',
                style: T.inter(14, color: T.muted)),
          );
        }
        return Column(children: docs.map((d) => _row(d.data())).toList());
      },
    );
  }

  Widget _row(Map<String, dynamic> m) {
    final openRep = (m['openReportsAgainst'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: T.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: openRep > 0 ? T.reject.withOpacity(.5) : T.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              m['displayName']?.toString() ??
                  m['email']?.toString() ??
                  m['uid']?.toString() ??
                  '—',
              style: T.inter(14.5, weight: FontWeight.w600, color: T.ivory),
            ),
          ),
          _statusChip(m['status']?.toString() ?? 'unknown'),
          const SizedBox(width: 10),
          Text(_rel(m['lastActiveAt']), style: T.inter(12, color: T.muted)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 22, runSpacing: 8, children: [
          _stat('Matches', m['matchesReceived']),
          _stat('Interest sent', m['interestsSent']),
          _stat('Interest recv', m['interestsReceived']),
          _stat('Convs', m['activeConversations']),
          _stat('Messages', m['messagesSent']),
          _stat('Reports', m['reportsAgainst'],
              danger: openRep > 0, extra: openRep > 0 ? '$openRep open' : null),
        ]),
      ]),
    );
  }

  Widget _stat(String label, dynamic value, {bool danger = false, String? extra}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
          style: T.inter(9.5, color: T.muted, weight: FontWeight.w600)),
      const SizedBox(height: 2),
      Row(children: [
        Text('${value ?? 0}',
            style: T.inter(15, color: danger ? T.reject : T.ivory,
                weight: FontWeight.w600)),
        if (extra != null) ...[
          const SizedBox(width: 6),
          Text(extra, style: T.inter(11, color: T.reject)),
        ],
      ]),
    ]);
  }

  Widget _statusChip(String s) {
    final c = s == 'approved'
        ? T.approve
        : (s == 'paused' ? T.gold : T.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(s, style: T.inter(11, color: c)),
    );
  }

  static String _rel(dynamic ts) {
    if (ts is! Timestamp) return '—';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  static String _fmt(dynamic ts) {
    if (ts is! Timestamp) return 'not yet computed';
    final d = ts.toDate();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)} ${p(d.hour)}:${p(d.minute)}';
  }
}
