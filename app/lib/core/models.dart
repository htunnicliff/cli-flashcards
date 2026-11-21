/// Stored records, ported from `src/core/storage/types.ts`. JSON shapes match
/// the web app's so backups move between the two unchanged. Times are epoch
/// milliseconds.
library;

import '../schema/deck.dart';

/// Where a card is in the FSRS life cycle.
enum CardPhase { newCard, learning, review, relearning }

extension CardPhaseJson on CardPhase {
  String get json => this == CardPhase.newCard ? 'new' : name;
  static CardPhase parse(String value) =>
      value == 'new' ? CardPhase.newCard : CardPhase.values.byName(value);
}

/// 1 = Again, 2 = Hard, 3 = Good, 4 = Easy.
enum Rating {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const Rating(this.value);
  final int value;

  static Rating of(int value) => Rating.values[value - 1];
}

num _num(Object? v) {
  if (v is num) return v;
  throw const FormatException('Expected a number');
}

class FsrsState {
  const FsrsState({
    required this.phase,
    required this.due,
    required this.stability,
    required this.difficulty,
    required this.elapsedDays,
    required this.scheduledDays,
    required this.learningSteps,
    required this.reps,
    required this.lapses,
    this.lastReview,
  });

  factory FsrsState.fromJson(Map<String, dynamic> json) => FsrsState(
    phase: CardPhaseJson.parse(json['phase'] as String),
    due: _num(json['due']).toInt(),
    stability: _num(json['stability']).toDouble(),
    difficulty: _num(json['difficulty']).toDouble(),
    elapsedDays: _num(json['elapsedDays']).toInt(),
    scheduledDays: _num(json['scheduledDays']).toInt(),
    learningSteps: _num(json['learningSteps']).toInt(),
    reps: _num(json['reps']).toInt(),
    lapses: _num(json['lapses']).toInt(),
    lastReview: (json['lastReview'] as num?)?.toInt(),
  );

  final CardPhase phase;

  /// When the card is next due.
  final int due;
  final double stability;
  final double difficulty;

  /// Days between the previous review and the last one.
  final int elapsedDays;

  /// Days the last review scheduled the card out by.
  final int scheduledDays;

  /// Index into the learning or relearning steps.
  final int learningSteps;
  final int reps;
  final int lapses;
  final int? lastReview;

  Map<String, dynamic> toJson() => {
    'phase': phase.json,
    'due': due,
    'stability': stability,
    'difficulty': difficulty,
    'elapsedDays': elapsedDays,
    'scheduledDays': scheduledDays,
    'learningSteps': learningSteps,
    'reps': reps,
    'lapses': lapses,
    if (lastReview != null) 'lastReview': lastReview,
  };

  @override
  bool operator ==(Object other) =>
      other is FsrsState &&
      other.phase == phase &&
      other.due == due &&
      other.stability == stability &&
      other.difficulty == difficulty &&
      other.elapsedDays == elapsedDays &&
      other.scheduledDays == scheduledDays &&
      other.learningSteps == learningSteps &&
      other.reps == reps &&
      other.lapses == lapses &&
      other.lastReview == lastReview;

  @override
  int get hashCode => Object.hash(
    phase,
    due,
    stability,
    difficulty,
    elapsedDays,
    scheduledDays,
    learningSteps,
    reps,
    lapses,
    lastReview,
  );

  @override
  String toString() => 'FsrsState(${toJson()})';
}

/// Scheduling state for one card. Never removed when a deck changes.
class CardState {
  const CardState({
    required this.cardId,
    required this.deckId,
    required this.optionId,
    required this.fsrs,
    this.suspended = false,
    this.buriedUntil,
    this.leech = false,
  });

  factory CardState.fromJson(Map<String, dynamic> json) => CardState(
    cardId: json['cardId'] as String,
    deckId: json['deckId'] as String,
    optionId: json['optionId'] as String,
    fsrs: FsrsState.fromJson(json['fsrs'] as Map<String, dynamic>),
    suspended: json['suspended'] as bool,
    buriedUntil: (json['buriedUntil'] as num?)?.toInt(),
    leech: json['leech'] as bool? ?? false,
  );

  final String cardId;
  final String deckId;
  final String optionId;
  final FsrsState fsrs;
  final bool suspended;

  /// Buried cards are skipped until this time.
  final int? buriedUntil;

  /// Forgotten `leechThreshold` times.
  final bool leech;

  CardState copyWith({
    FsrsState? fsrs,
    bool? suspended,
    int? Function()? buriedUntil,
    bool? leech,
  }) => CardState(
    cardId: cardId,
    deckId: deckId,
    optionId: optionId,
    fsrs: fsrs ?? this.fsrs,
    suspended: suspended ?? this.suspended,
    buriedUntil: buriedUntil == null ? this.buriedUntil : buriedUntil(),
    leech: leech ?? this.leech,
  );

  Map<String, dynamic> toJson() => {
    'cardId': cardId,
    'deckId': deckId,
    'optionId': optionId,
    'fsrs': fsrs.toJson(),
    'suspended': suspended,
    if (buriedUntil != null) 'buriedUntil': buriedUntil,
    if (leech) 'leech': true,
  };
}

/// One grade, appended and never edited.
class ReviewLogEntry {
  const ReviewLogEntry({
    this.id,
    required this.cardId,
    required this.deckId,
    required this.reviewedAt,
    required this.rating,
    required this.durationMs,
    required this.before,
    required this.after,
  });

  factory ReviewLogEntry.fromJson(Map<String, dynamic> json, {int? id}) =>
      ReviewLogEntry(
        id: id ?? (json['id'] as num?)?.toInt(),
        cardId: json['cardId'] as String,
        deckId: json['deckId'] as String,
        reviewedAt: _num(json['reviewedAt']).toInt(),
        rating: Rating.of(json['rating'] as int),
        durationMs: _num(json['durationMs']).toInt(),
        before: json['before'] == null
            ? null
            : FsrsState.fromJson(json['before'] as Map<String, dynamic>),
        after: FsrsState.fromJson(json['after'] as Map<String, dynamic>),
      );

  /// Assigned when stored.
  final int? id;
  final String cardId;
  final String deckId;
  final int reviewedAt;
  final Rating rating;
  final int durationMs;

  /// Null for the card's first review.
  final FsrsState? before;
  final FsrsState after;

  ReviewLogEntry withId(int id) => ReviewLogEntry(
    id: id,
    cardId: cardId,
    deckId: deckId,
    reviewedAt: reviewedAt,
    rating: rating,
    durationMs: durationMs,
    before: before,
    after: after,
  );

  Map<String, dynamic> toJson({bool withId = false}) => {
    if (withId && id != null) 'id': id,
    'cardId': cardId,
    'deckId': deckId,
    'reviewedAt': reviewedAt,
    'rating': rating.value,
    'durationMs': durationMs,
    'before': before?.toJson(),
    'after': after.toJson(),
  };
}

/// An installed deck with per-deck preferences.
class StoredDeck {
  const StoredDeck({
    required this.deck,
    required this.installedAt,
    required this.updatedAt,
    this.includeObscure = false,
    this.paused = false,
    this.typeAnswers = false,
  });

  factory StoredDeck.fromJson(Map<String, dynamic> json) => StoredDeck(
    deck: Deck.fromJson(json['deck'] as Map<String, dynamic>),
    installedAt: _num(json['installedAt']).toInt(),
    updatedAt: _num(json['updatedAt']).toInt(),
    includeObscure: json['includeObscure'] as bool? ?? false,
    paused: json['paused'] as bool? ?? false,
    typeAnswers: json['typeAnswers'] as bool? ?? false,
  );

  final Deck deck;
  final int installedAt;
  final int updatedAt;

  /// Obscure-tier options are left out of new cards unless this is on.
  final bool includeObscure;

  /// Paused decks show no cards until resumed.
  final bool paused;

  /// Meaning → flag and cloze cards ask for the flag to be typed.
  final bool typeAnswers;

  String get id => deck.id;
  int get deckVersion => deck.deckVersion;

  StoredDeck copyWith({
    Deck? deck,
    int? updatedAt,
    bool? includeObscure,
    bool? paused,
    bool? typeAnswers,
  }) => StoredDeck(
    deck: deck ?? this.deck,
    installedAt: installedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    includeObscure: includeObscure ?? this.includeObscure,
    paused: paused ?? this.paused,
    typeAnswers: typeAnswers ?? this.typeAnswers,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'deckVersion': deckVersion,
    'installedAt': installedAt,
    'updatedAt': updatedAt,
    'includeObscure': includeObscure,
    if (paused) 'paused': true,
    if (typeAnswers) 'typeAnswers': true,
    'deck': deck.toJson(),
  };
}

/// Implementation families of tools whose flags differ.
enum DeckFlavor { gnu, bsd }

class PendingDeckInstall {
  const PendingDeckInstall({
    required this.id,
    required this.deckVersion,
    required this.includeObscure,
  });

  factory PendingDeckInstall.fromJson(Map<String, dynamic> json) =>
      PendingDeckInstall(
        id: json['id'] as String,
        deckVersion: (json['deckVersion'] as num).toInt(),
        includeObscure: json['includeObscure'] as bool,
      );

  final String id;
  final int deckVersion;
  final bool includeObscure;

  Map<String, dynamic> toJson() => {
    'id': id,
    'deckVersion': deckVersion,
    'includeObscure': includeObscure,
  };
}

/// Every stored setting. Defaults match `SETTING_DEFAULTS`.
class Settings {
  const Settings({
    this.desiredRetention = 0.9,
    this.newCardsPerDay = 20,
    this.maxReviewsPerDay = 200,
    this.dayRolloverHour = 4,
    this.leechThreshold = 6,
    this.lastBackupAt,
    this.flagPairs = true,
    this.pendingDeckInstalls = const [],
    this.deckFlavor,
    this.onboardingDone = false,
    this.reduceTransparency = false,
  });

  factory Settings.fromJson(Map<String, dynamic> json) {
    const d = Settings();
    final flavor = json['deckFlavor'] as String?;
    return Settings(
      desiredRetention:
          (json['desiredRetention'] as num?)?.toDouble() ?? d.desiredRetention,
      newCardsPerDay:
          (json['newCardsPerDay'] as num?)?.toInt() ?? d.newCardsPerDay,
      maxReviewsPerDay:
          (json['maxReviewsPerDay'] as num?)?.toInt() ?? d.maxReviewsPerDay,
      dayRolloverHour:
          (json['dayRolloverHour'] as num?)?.toInt() ?? d.dayRolloverHour,
      leechThreshold:
          (json['leechThreshold'] as num?)?.toInt() ?? d.leechThreshold,
      lastBackupAt: (json['lastBackupAt'] as num?)?.toInt(),
      flagPairs: json['flagPairs'] as bool? ?? d.flagPairs,
      pendingDeckInstalls: [
        for (final p in (json['pendingDeckInstalls'] as List<dynamic>?) ?? [])
          PendingDeckInstall.fromJson(p as Map<String, dynamic>),
      ],
      deckFlavor: flavor == null ? null : DeckFlavor.values.byName(flavor),
      onboardingDone: json['onboardingDone'] as bool? ?? false,
      reduceTransparency: json['reduceTransparency'] as bool? ?? false,
    );
  }

  /// Probability of recall FSRS aims for.
  final double desiredRetention;

  /// New cards per day, across all decks.
  final int newCardsPerDay;

  /// Review (not learning) cards per day, across all decks.
  final int maxReviewsPerDay;

  /// Local hour at which a new study day starts.
  final int dayRolloverHour;

  /// Lapses after which a card is tagged a leech and suspended.
  final int leechThreshold;

  /// When a backup was last exported.
  final int? lastBackupAt;

  /// Adds short → long and long → short cards.
  final bool flagPairs;

  /// Decks an imported backup used that aren't installed yet.
  final List<PendingDeckInstall> pendingDeckInstalls;

  /// The flavor the user picked, or null to follow what's installed.
  final DeckFlavor? deckFlavor;

  /// Whether the welcome tour has been finished or skipped.
  final bool onboardingDone;

  /// Solid surfaces instead of frosted glass.
  final bool reduceTransparency;

  Settings copyWith({
    double? desiredRetention,
    int? newCardsPerDay,
    int? maxReviewsPerDay,
    int? dayRolloverHour,
    int? leechThreshold,
    int? Function()? lastBackupAt,
    bool? flagPairs,
    List<PendingDeckInstall>? pendingDeckInstalls,
    DeckFlavor? Function()? deckFlavor,
    bool? onboardingDone,
    bool? reduceTransparency,
  }) => Settings(
    desiredRetention: desiredRetention ?? this.desiredRetention,
    newCardsPerDay: newCardsPerDay ?? this.newCardsPerDay,
    maxReviewsPerDay: maxReviewsPerDay ?? this.maxReviewsPerDay,
    dayRolloverHour: dayRolloverHour ?? this.dayRolloverHour,
    leechThreshold: leechThreshold ?? this.leechThreshold,
    lastBackupAt: lastBackupAt == null ? this.lastBackupAt : lastBackupAt(),
    flagPairs: flagPairs ?? this.flagPairs,
    pendingDeckInstalls: pendingDeckInstalls ?? this.pendingDeckInstalls,
    deckFlavor: deckFlavor == null ? this.deckFlavor : deckFlavor(),
    onboardingDone: onboardingDone ?? this.onboardingDone,
    reduceTransparency: reduceTransparency ?? this.reduceTransparency,
  );

  Map<String, dynamic> toJson() => {
    'desiredRetention': desiredRetention,
    'newCardsPerDay': newCardsPerDay,
    'maxReviewsPerDay': maxReviewsPerDay,
    'dayRolloverHour': dayRolloverHour,
    'leechThreshold': leechThreshold,
    'lastBackupAt': lastBackupAt,
    'flagPairs': flagPairs,
    'pendingDeckInstalls': [for (final p in pendingDeckInstalls) p.toJson()],
    'deckFlavor': deckFlavor?.name,
    'onboardingDone': onboardingDone,
    'reduceTransparency': reduceTransparency,
  };
}
