import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'widgets.dart';

/// Shared wheel-picker bottom sheets — Cupertino wheels with a haptic tick per
/// detent — so numeric profile inputs (height, weight) feel identical to the
/// date-of-birth picker in the gate flow. Values are stored metric (cm / kg);
/// the imperial toggle is entry-only.

CupertinoPicker _wheel({
  required FixedExtentScrollController controller,
  required int count,
  required String Function(int) labelOf,
  required ValueChanged<int> onChanged,
}) =>
    CupertinoPicker.builder(
      scrollController: controller,
      itemExtent: 40,
      squeeze: 1.1,
      diameterRatio: 1.25,
      magnification: 1.05,
      useMagnifier: true,
      selectionOverlay: Container(
        decoration: BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(color: DarkTokens.gold.withOpacity(.35)),
          ),
        ),
      ),
      childCount: count,
      itemBuilder: (_, i) => Center(
        child: Text(labelOf(i),
            style: AppType.inter(18, color: DarkTokens.ivory)),
      ),
      onSelectedItemChanged: (i) {
        HapticFeedback.selectionClick();
        onChanged(i);
      },
    );

Widget _unitPill(String label, bool on, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: on ? DarkTokens.gold.withOpacity(.12) : null,
            border: Border.all(
                color: on ? DarkTokens.gold : DarkTokens.hairline(.5)),
          ),
          child: Text(label,
              style: AppType.inter(12.5,
                  color: on ? DarkTokens.gold : DarkTokens.muted())),
        ),
      ),
    );

Widget _shell(
  BuildContext ctx, {
  required String title,
  required List<Widget> toggles,
  required Widget wheels,
  required VoidCallback onSet,
}) =>
    Container(
      decoration: BoxDecoration(
        color: DarkTokens.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: DarkTokens.hairline(.4)),
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom + 12, top: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
              color: DarkTokens.hairline(),
              borderRadius: BorderRadius.circular(2)),
        ),
        Text(title, style: AppType.fraunces(20, color: DarkTokens.ivory)),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: toggles),
        const SizedBox(height: 4),
        SizedBox(
          height: 200,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpace.screenMargin),
            child: wheels,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpace.screenMargin),
          child: PrimaryCta(label: 'Set', onPressed: onSet),
        ),
      ]),
    );

/// Height in cm (140–210), with a ft-in / cm toggle. Returns the chosen cm,
/// or null if dismissed.
Future<int?> showHeightWheel(BuildContext context, {int? initialCm}) {
  var cm = (initialCm ?? 170);
  if (cm < 140) cm = 140;
  if (cm > 210) cm = 210;
  var imperial = true;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      final Widget wheels;
      if (imperial) {
        final totalIn = (cm / 2.54).round();
        var feet = totalIn ~/ 12;
        if (feet < 4) feet = 4;
        if (feet > 7) feet = 7;
        final inch = totalIn % 12;
        final ftCtrl = FixedExtentScrollController(initialItem: feet - 4);
        final inCtrl = FixedExtentScrollController(initialItem: inch);
        wheels = Row(children: [
          Expanded(
            child: _wheel(
                controller: ftCtrl,
                count: 4,
                labelOf: (i) => '${i + 4} ft',
                onChanged: (i) {
                  final f = i + 4;
                  final inNow = (cm / 2.54).round() % 12;
                  cm = (((f * 12) + inNow) * 2.54).round();
                }),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _wheel(
                controller: inCtrl,
                count: 12,
                labelOf: (i) => '$i in',
                onChanged: (i) {
                  final ftNow = (cm / 2.54).round() ~/ 12;
                  cm = (((ftNow * 12) + i) * 2.54).round();
                }),
          ),
        ]);
      } else {
        final cmCtrl = FixedExtentScrollController(initialItem: cm - 140);
        wheels = Row(children: [
          Expanded(
            child: _wheel(
                controller: cmCtrl,
                count: 71,
                labelOf: (i) => '${140 + i} cm',
                onChanged: (i) => cm = 140 + i),
          ),
        ]);
      }
      return _shell(
        ctx,
        title: 'Height',
        toggles: [
          _unitPill('ft / in', imperial, () => setSheet(() => imperial = true)),
          _unitPill('cm', !imperial, () => setSheet(() => imperial = false)),
        ],
        wheels: wheels,
        onSet: () => Navigator.pop(ctx, cm),
      );
    }),
  );
}

/// Weight in kg (40–150), with a kg / lb toggle. Returns the chosen kg,
/// or null if dismissed.
Future<int?> showWeightWheel(BuildContext context, {int? initialKg}) {
  var kg = (initialKg ?? 65);
  if (kg < 40) kg = 40;
  if (kg > 150) kg = 150;
  var metric = true;
  const minLb = 90, maxLb = 330;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      final Widget wheels;
      if (metric) {
        final c = FixedExtentScrollController(initialItem: kg - 40);
        wheels = Row(children: [
          Expanded(
            child: _wheel(
                controller: c,
                count: 111,
                labelOf: (i) => '${40 + i} kg',
                onChanged: (i) => kg = 40 + i),
          ),
        ]);
      } else {
        var lb = (kg * 2.20462).round();
        if (lb < minLb) lb = minLb;
        if (lb > maxLb) lb = maxLb;
        final c = FixedExtentScrollController(initialItem: lb - minLb);
        wheels = Row(children: [
          Expanded(
            child: _wheel(
                controller: c,
                count: maxLb - minLb + 1,
                labelOf: (i) => '${minLb + i} lb',
                onChanged: (i) => kg = ((minLb + i) / 2.20462).round()),
          ),
        ]);
      }
      return _shell(
        ctx,
        title: 'Weight',
        toggles: [
          _unitPill('kg', metric, () => setSheet(() => metric = true)),
          _unitPill('lb', !metric, () => setSheet(() => metric = false)),
        ],
        wheels: wheels,
        onSet: () => Navigator.pop(ctx, kg),
      );
    }),
  );
}
