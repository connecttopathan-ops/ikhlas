import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import 'questionnaire_models.dart';

/// Shared scaffold for one questionnaire step: progress hairline,
/// section eyebrow, Fraunces title, optional intro, content, CTA.
class StepScaffold extends StatelessWidget {
  final int step;
  final int totalSteps;
  final String eyebrow;
  final String title;
  final String? intro;
  final List<Widget> children;
  final String ctaLabel;
  final VoidCallback? onNext;
  final bool loading;

  const StepScaffold({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.eyebrow,
    required this.title,
    this.intro,
    required this.children,
    this.ctaLabel = 'Continue',
    this.onNext,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpace.screenMargin),
            child: StepProgress(step: step, total: totalSteps),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpace.screenMargin, 28,
                  AppSpace.screenMargin, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow.toUpperCase(),
                      style: AppType.eyebrow(DarkTokens.gold)),
                  const SizedBox(height: 14),
                  Text(title,
                      style: AppType.fraunces(28,
                          color: DarkTokens.ivory, height: 1.15)),
                  if (intro != null) ...[
                    const SizedBox(height: 10),
                    Text(intro!,
                        style: AppType.inter(13.5,
                            color: DarkTokens.muted(.62))),
                  ],
                  const SizedBox(height: 26),
                  ...children,
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.screenMargin, 4, AppSpace.screenMargin, 24),
            child:
                PrimaryCta(label: ctaLabel, loading: loading, onPressed: onNext),
          ),
        ],
      ),
    );
  }
}

/// Thin gold progress rule: filled portion at full gold, rest at hairline
/// opacity — consistent with the spec's hairline language.
class StepProgress extends StatelessWidget {
  final int step;
  final int total;
  const StepProgress({super.key, required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: SizedBox(
              height: 2,
              child: Row(
                children: [
                  Expanded(
                      flex: step,
                      child: Container(color: DarkTokens.gold)),
                  Expanded(
                      flex: total - step,
                      child: Container(color: DarkTokens.hairline())),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text('$step / $total',
            style: AppType.inter(11.5, color: DarkTokens.muted())),
      ],
    );
  }
}

/// Single-select option list — rows divided by hairlines, gold diamond
/// marker on the selected row (same vocabulary as the declaration screen).
class OptionList extends StatelessWidget {
  final List<Choice> options;
  final String? selected;
  final ValueChanged<String> onSelect;
  const OptionList(
      {super.key,
      required this.options,
      required this.selected,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < options.length; i++) ...[
          _OptionRow(
            label: options[i].label,
            note: options[i].note,
            selected: selected == options[i].value,
            onTap: () => onSelect(options[i].value),
          ),
          if (i < options.length - 1) const Hairline(),
        ],
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String label;
  final String? note;
  final bool selected;
  final VoidCallback onTap;
  const _OptionRow(
      {required this.label,
      this.note,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.checkbox),
                border: Border.all(
                    color: DarkTokens.gold.withOpacity(selected ? .9 : .45),
                    width: 1),
              ),
              alignment: Alignment.center,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: selected ? 1 : 0,
                child: const DiamondBullet(size: 10, color: DarkTokens.gold),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppType.inter(14.5,
                          color: DarkTokens.ivory, height: 1.45)),
                  if (note != null) ...[
                    const SizedBox(height: 3),
                    Text(note!,
                        style: AppType.inter(12,
                            color: DarkTokens.muted(), height: 1.5)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Labeled underline text field — the questionnaire's standard input.
class UnderlineField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final String? prefix;
  const UnderlineField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: AppType.eyebrow(DarkTokens.gold.withOpacity(.8))),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboardType,
          maxLines: maxLines,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          style: AppType.inter(16, color: DarkTokens.ivory),
          cursorColor: DarkTokens.gold,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            prefixText: prefix,
            prefixStyle: AppType.inter(16, color: DarkTokens.muted()),
            hintStyle: AppType.inter(16, color: DarkTokens.muted(.4)),
            enabledBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: DarkTokens.gold.withOpacity(.65))),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: DarkTokens.gold)),
          ),
        ),
      ],
    );
  }
}

/// Question sub-heading within a step.
class QuestionLabel extends StatelessWidget {
  final String text;
  const QuestionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 6),
        child: Text(text,
            style: AppType.inter(14.5,
                weight: FontWeight.w500,
                color: DarkTokens.ivory,
                height: 1.4)),
      );
}
