/// A terminal-style field for typing the flag. Ported from `TypedAnswer.vue`.
library;

import 'package:material_ui/material_ui.dart';

import '../../core/answers.dart';
import '../theme.dart';
import '../widgets.dart';
import 'review_session.dart';

class TypedAnswer extends StatefulWidget {
  const TypedAnswer({
    super.key,
    required this.command,
    required this.result,
    required this.onSubmit,
    this.focusNode,
  });

  final String command;
  final TypedResult? result;
  final ValueChanged<String> onSubmit;
  final FocusNode? focusNode;

  @override
  State<TypedAnswer> createState() => _TypedAnswerState();
}

class _TypedAnswerState extends State<TypedAnswer> {
  final _controller = TextEditingController();

  @override
  void didUpdateWidget(TypedAnswer old) {
    super.didUpdateWidget(old);
    if (old.result != null && widget.result == null) _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final result = widget.result;
    final borderColor = result == null
        ? f.border
        : result.result.correct
        ? f.accent
        : f.again;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: Space.s4),
          decoration: BoxDecoration(
            color: f.sunken,
            borderRadius: BorderRadius.circular(Radii.code),
            border: Border.all(
              color: borderColor,
              width: result == null ? 1 : 2,
            ),
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Text(
                  '\$ ${widget.command} ',
                  style: context.mono.copyWith(color: f.muted),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  readOnly: result != null,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  style: context.mono,
                  decoration: InputDecoration(
                    hintText: 'type the flag',
                    hintStyle: context.mono.copyWith(color: f.muted),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onSubmitted: result == null ? widget.onSubmit : null,
                ),
              ),
              if (result == null) const Kbd('Enter'),
            ],
          ),
        ),
        if (result != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s2),
            child: Semantics(liveRegion: true, child: _ResultLine(result)),
          ),
      ],
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine(this.result);
  final TypedResult result;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final r = result.result;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final code = context.mono.copyWith(fontSize: TextSizes.sm);
    if (r.correct) {
      return Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(
              text: 'Correct',
              style: weight(base.copyWith(color: f.accent), FontWeight.w700),
            ),
            if (r.preferred != null) ...[
              const TextSpan(text: ' · short form: '),
              TextSpan(text: r.preferred, style: code),
            ],
          ],
        ),
      );
    }
    final diff = result.typed.trim().isEmpty
        ? const <DiffPart>[]
        : diffChars(result.typed.trim(), r.expected);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text: 'Not quite',
            style: weight(base.copyWith(color: f.again), FontWeight.w700),
          ),
          const TextSpan(text: ' · expected '),
          TextSpan(text: r.expected, style: code),
          if (diff.isNotEmpty) const TextSpan(text: '   '),
          for (final part in diff)
            TextSpan(
              text: part.text,
              semanticsLabel: '',
              style: code.copyWith(
                color: switch (part.kind) {
                  DiffKind.same => f.muted,
                  DiffKind.added => f.accent,
                  DiffKind.removed => f.again,
                },
                decoration: part.kind == DiffKind.removed
                    ? TextDecoration.lineThrough
                    : part.kind == DiffKind.added
                    ? TextDecoration.underline
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
