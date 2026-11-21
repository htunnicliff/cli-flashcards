import 'package:cliflashcards/core/repository.dart';
import 'package:cliflashcards/schema/deck.dart';
import 'package:sembast/sembast_memory.dart';

var _n = 0;

Future<Repository> memoryRepository() =>
    Repository.open(databaseFactoryMemory, 'test-${_n++}.db');

Option option(
  String id,
  List<String> flags, {
  Tier tier = Tier.core,
  List<Example> examples = const [],
  String? sub,
}) => Option(
  id: id,
  flags: flags,
  summary: 'Summary of $id',
  tier: tier,
  examples: examples,
  subcommand: sub,
);

Deck deck(
  List<Option> options, {
  String tool = 'rg',
  String variant = 'default',
  int version = 1,
}) => Deck(
  id: '$tool-$variant',
  tool: tool,
  variant: variant,
  toolVersion: '1.0',
  deckVersion: version,
  source: 'manual',
  license: 'MIT',
  attribution: 'test',
  options: options,
);

/// 2026-03-02 12:00 local time.
final noon = DateTime(2026, 3, 2, 12).millisecondsSinceEpoch;
const minute = 60000;
const day = 86400000;
