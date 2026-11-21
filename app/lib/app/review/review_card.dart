/// One flashcard, front and back. Ported from `src/app/review/ReviewCard.vue`.
library;

import 'package:material_ui/material_ui.dart' hide Card;

import '../../core/review_format.dart';
import '../../schema/cards.dart';
import '../../schema/deck.dart';
import '../theme.dart';
import '../widgets.dart';

const prompts = {
  CardType.flagToMeaning: 'What does this flag do?',
  CardType.meaningToFlag: 'Which flag does this?',
  CardType.cloze: 'Fill in the blank.',
  CardType.shortToLong: "What's the long form?",
  CardType.longToShort: "What's the short form?",
};

class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.card,
    required this.option,
    required this.tool,
    required this.revealed,
    required this.flagPairs,
    this.reduceMotion = false,
  });

  final Card card;
  final Option? option;
  final String tool;
  final bool revealed;

  /// The front shows one form of a flag, never both.
  final bool flagPairs;
  final bool reduceMotion;

  String get _command {
    final sub = option?.subcommand;
    return sub == null ? tool : '$tool $sub';
  }

  /// Highlights every spelling of the card's option in a command.
  List<Part> _highlight(String text) {
    final answers = card.answers.toSet();
    return [
      for (final part in commandParts(text))
        if (part.kind == PartKind.blank)
          part
        else if (part.kind == PartKind.flag &&
            !answers.contains(part.text.split('=').first))
          Part(PartKind.tool, part.text)
        else if (part.kind == PartKind.tool &&
            answers.contains(part.text.split('=').first))
          Part(PartKind.flag, part.text)
        else
          part,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final flagSize = narrow ? 30.0 : TextSizes.x3l;
    final aliases = card.answers.skip(1).toList();
    final arg = option?.argument;
    final argument = arg == null
        ? null
        : arg.optional
        ? '[${arg.name}]'
        : arg.name;
    final example = card.type == CardType.cloze
        ? (command: card.command!, description: card.exampleDescription)
        : option?.examples.firstOrNull == null
        ? null
        : (
            command: option!.examples.first.command,
            description: option!.examples.first.description,
          );

    Widget flags(List<String> spellings, {bool front = false}) => Wrap(
      spacing: Space.s4,
      runSpacing: Space.s2,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Text(
          spellings.first,
          style: weight(
            context.mono.copyWith(
              color: f.accent,
              fontSize: front ? flagSize : TextSizes.xl,
              height: 1.15,
            ),
            FontWeight.w600,
          ),
        ),
        if (!front && argument != null)
          Text(argument, style: context.monoCasual),
        for (final alias in spellings.skip(1))
          Text(alias, style: context.mono.copyWith(color: f.muted)),
      ],
    );

    final toolLine = Text(
      _command,
      style: context.mono.copyWith(color: f.muted),
    );
    final front = switch (card.type) {
      CardType.flagToMeaning => [
        toolLine,
        flags([card.flag, if (!flagPairs) ...aliases], front: true),
      ],
      CardType.shortToLong || CardType.longToShort => [
        toolLine,
        flags([card.shown!], front: true),
      ],
      CardType.meaningToFlag => [
        toolLine,
        Text(
          card.summary,
          style: Theme.of(context).textTheme.headlineSmall!
              .copyWith(fontSize: narrow ? TextSizes.lg : TextSizes.xl),
        ),
      ],
      CardType.cloze => [
        CommandLine(_highlight(card.cloze!), large: true),
        if (card.exampleDescription != null)
          Text(card.exampleDescription!, style: context.hint),
      ],
    };

    final back = Column(
      key: const ValueKey('back'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: Space.s8),
        flags(card.answers),
        const SizedBox(height: Space.s3),
        Text(card.summary, style: Theme.of(context).textTheme.bodyLarge),
        if (example != null) ...[
          const SizedBox(height: Space.s4),
          CommandLine(_highlight(example.command)),
          if (example.description != null && card.type != CardType.cloze)
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: Text(example.description!, style: context.hint),
            ),
        ],
        if (card.detail.isNotEmpty && card.detail != card.summary)
          _FullDescription(card.detail),
      ],
    );

    return Semantics(
      label: prompts[card.type],
      container: true,
      child: Glass(
        padding: EdgeInsets.all(narrow ? Space.s6 : Space.s10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 220),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(prompts[card.type]!, style: context.casual),
              const SizedBox(height: Space.s5),
              for (final (i, w) in front.indexed) ...[
                if (i > 0) const SizedBox(height: Space.s3),
                w,
              ],
              AnimatedSwitcher(
                duration: Duration(milliseconds: reduceMotion ? 0 : 220),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
                child: revealed ? back : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullDescription extends StatelessWidget {
  const _FullDescription(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.s3),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: Space.s2),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(
            'Full description',
            style: Theme.of(context).textTheme.labelLarge!
                .copyWith(color: Frost.of(context).accent),
          ),
          children: [SelectableText(text, style: context.hint)],
        ),
      ),
    );
  }
}
