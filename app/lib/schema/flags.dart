/// Flag spelling helpers, ported from `src/schema/flags.ts`.
///
/// A **short** flag is a single dash followed by exactly one character (`-i`).
/// A **long** flag is anything else: `--ignore-case`, or `-name` as `find` spells it.
library;

/// A flag spelling: `-x`, `--long-name`, or `-name`. No whitespace, `=` or `:`.
final flagPattern = RegExp(r'^--?[^\s=:-][^\s=:]*$');

bool isShortFlag(String flag) =>
    flag.length == 2 && flag.startsWith('-') && flag != '--';

bool isLongFlag(String flag) => !isShortFlag(flag);

/// Orders flags short forms first, keeping the order within each group.
List<String> normalizeFlags(Iterable<String> flags) => [
  ...flags.where(isShortFlag),
  ...flags.where(isLongFlag),
];
