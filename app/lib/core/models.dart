// Domain models mirroring docs/api/openapi.json. Parsing is defensive.

DateTime? _dt(Object? v) => v == null ? null : DateTime.parse(v as String);

enum OnboardingStep {
  verifyEmail('verify_email'),
  intro('intro'),
  connectToy('connect_toy'),
  childProfile('child_profile'),
  preferences('preferences'),
  done('done');

  const OnboardingStep(this.wire);
  final String wire;

  static OnboardingStep parse(String? v) =>
      values.firstWhere((s) => s.wire == v, orElse: () => OnboardingStep.intro);
}

class ParentProfile {
  const ParentProfile({
    required this.id,
    required this.email,
    this.displayName,
    required this.marketingOptIn,
    required this.storeTranscripts,
    required this.productAnalytics,
    required this.dataChoicesConfirmed,
    required this.onboardingStep,
    required this.notifySessionSummaries,
    required this.notifyDeviceOffline,
  });

  final String id;
  final String email;
  final String? displayName;
  final bool marketingOptIn;
  final bool storeTranscripts;
  final bool productAnalytics;
  final bool dataChoicesConfirmed;
  final OnboardingStep onboardingStep;
  final bool notifySessionSummaries;
  final bool notifyDeviceOffline;

  factory ParentProfile.fromJson(Map<String, dynamic> j) => ParentProfile(
    id: j['id'] as String,
    email: j['email'] as String,
    displayName: j['display_name'] as String?,
    marketingOptIn: j['marketing_opt_in'] as bool,
    storeTranscripts: j['store_transcripts'] as bool,
    productAnalytics: j['product_analytics'] as bool,
    dataChoicesConfirmed: j['data_choices_confirmed'] as bool,
    onboardingStep: OnboardingStep.parse(j['onboarding_step'] as String?),
    notifySessionSummaries: j['notify_session_summaries'] as bool,
    notifyDeviceOffline: j['notify_device_offline'] as bool,
  );
}

class Child {
  const Child({required this.id, required this.displayName, this.birthYear, required this.language});

  final String id;
  final String displayName;
  final int? birthYear;
  final String language;

  factory Child.fromJson(Map<String, dynamic> j) => Child(
    id: j['id'] as String,
    displayName: j['display_name'] as String,
    birthYear: j['birth_year'] as int?,
    language: j['language'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'display_name': displayName,
    'birth_year': birthYear,
    'language': language,
  };
}

enum ConfigSync { applied, pending, failed, none }

class Device {
  const Device({
    required this.id,
    required this.serial,
    required this.name,
    required this.online,
    this.lastSeenAt,
    this.firmwareVersion,
    required this.firmwareUpdateAvailable,
    this.wifiSsid,
    this.activeChildId,
    required this.configSync,
    required this.isSimulated,
  });

  final String id;
  final String serial;
  final String name;
  final bool online;
  final DateTime? lastSeenAt;
  final String? firmwareVersion;
  final bool firmwareUpdateAvailable;
  final String? wifiSsid;
  final String? activeChildId;
  final ConfigSync configSync;
  final bool isSimulated;

  factory Device.fromJson(Map<String, dynamic> j) => Device(
    id: j['id'] as String,
    serial: j['serial'] as String,
    name: j['name'] as String,
    online: j['online'] as bool,
    lastSeenAt: _dt(j['last_seen_at']),
    firmwareVersion: j['firmware_version'] as String?,
    firmwareUpdateAvailable: j['firmware_update_available'] as bool? ?? false,
    wifiSsid: j['wifi_ssid'] as String?,
    activeChildId: j['active_child_id'] as String?,
    configSync: ConfigSync.values.byName(j['config_sync'] as String? ?? 'none'),
    isSimulated: j['is_simulated'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'serial': serial,
    'name': name,
    'online': online,
    'last_seen_at': lastSeenAt?.toIso8601String(),
    'firmware_version': firmwareVersion,
    'firmware_update_available': firmwareUpdateAvailable,
    'wifi_ssid': wifiSsid,
    'active_child_id': activeChildId,
    'config_sync': configSync.name,
    'is_simulated': isSimulated,
  };
}

class Activity {
  const Activity({
    required this.key,
    required this.title,
    required this.summary,
    required this.optionsSchema,
    this.assessmentNote,
  });

  final String key;
  final String title;
  final String summary;
  final Map<String, dynamic> optionsSchema;
  final String? assessmentNote;

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
    key: j['key'] as String,
    title: j['title'] as String,
    summary: j['summary'] as String,
    optionsSchema: (j['options_schema'] as Map?)?.cast<String, dynamic>() ?? const {},
    assessmentNote: j['assessment_note'] as String?,
  );
}

class LearningPreferences {
  const LearningPreferences({required this.version, required this.payload, required this.updatedAt});

  final int version;
  final Map<String, dynamic> payload;
  final DateTime updatedAt;

  factory LearningPreferences.fromJson(Map<String, dynamic> j) => LearningPreferences(
    version: j['version'] as int,
    payload: (j['payload'] as Map).cast<String, dynamic>(),
    updatedAt: DateTime.parse(j['updated_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    'payload': payload,
    'updated_at': updatedAt.toIso8601String(),
  };

  Map<String, dynamic> activity(String key) =>
      ((payload['activities'] as Map?)?[key] as Map?)?.cast<String, dynamic>() ??
      {'enabled': true, 'difficulty': 'gentle', 'session_minutes': 10};

  int get dailyLimitMinutes => (payload['daily_limit_minutes'] as num?)?.toInt() ?? 30;
}

enum Outcome {
  correct('correct'),
  needsPractice('needs_practice'),
  uncertain('uncertain');

  const Outcome(this.wire);
  final String wire;

  static Outcome parse(String v) => values.firstWhere((o) => o.wire == v);
}

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.childId,
    required this.activityKey,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.summary,
    required this.correct,
    required this.needsPractice,
    required this.uncertain,
  });

  final String id;
  final String childId;
  final String activityKey;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? summary;
  final int correct;
  final int needsPractice;
  final int uncertain;

  int get total => correct + needsPractice + uncertain;

  factory SessionSummary.fromJson(Map<String, dynamic> j) => SessionSummary(
    id: j['id'] as String,
    childId: j['child_id'] as String,
    activityKey: j['activity_key'] as String,
    status: j['status'] as String,
    startedAt: DateTime.parse(j['started_at'] as String),
    endedAt: _dt(j['ended_at']),
    summary: j['summary'] as String?,
    correct: j['correct'] as int,
    needsPractice: j['needs_practice'] as int,
    uncertain: j['uncertain'] as int,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'child_id': childId,
    'activity_key': activityKey,
    'status': status,
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'summary': summary,
    'correct': correct,
    'needs_practice': needsPractice,
    'uncertain': uncertain,
  };
}

class AssessmentItem {
  const AssessmentItem({
    required this.seq,
    required this.itemIndex,
    required this.prompt,
    this.expected,
    this.response,
    required this.outcome,
    required this.attempt,
    required this.source,
  });

  final int seq;
  final int itemIndex;
  final String prompt;
  final String? expected;
  final String? response;
  final Outcome outcome;
  final int attempt;
  final String source;

  factory AssessmentItem.fromJson(Map<String, dynamic> j) => AssessmentItem(
    seq: j['seq'] as int,
    itemIndex: j['item_index'] as int? ?? j['seq'] as int,
    prompt: j['item_prompt'] as String,
    expected: j['expected'] as String?,
    response: j['response_text'] as String?,
    outcome: Outcome.parse(j['outcome'] as String),
    attempt: j['attempt'] as int,
    source: j['source'] as String,
  );
}

class Turn {
  const Turn({required this.seq, required this.speaker, this.text});

  final int seq;
  final String speaker;
  final String? text;

  factory Turn.fromJson(Map<String, dynamic> j) =>
      Turn(seq: j['seq'] as int, speaker: j['speaker'] as String, text: j['text'] as String?);
}

class SessionDetail {
  const SessionDetail({
    required this.summary,
    required this.items,
    required this.turns,
    required this.transcriptsAvailable,
  });

  final SessionSummary summary;
  final List<AssessmentItem> items;
  final List<Turn> turns;
  final bool transcriptsAvailable;

  factory SessionDetail.fromJson(Map<String, dynamic> j) => SessionDetail(
    summary: SessionSummary.fromJson(j),
    items: [for (final a in j['assessments'] as List) AssessmentItem.fromJson(a as Map<String, dynamic>)],
    turns: [for (final t in j['turns'] as List) Turn.fromJson(t as Map<String, dynamic>)],
    transcriptsAvailable: j['transcripts_available'] as bool,
  );
}

class Page<T> {
  const Page(this.items, this.nextCursor);

  final List<T> items;
  final String? nextCursor;
}

const activityTitles = {
  'phonics': 'Sounds',
  'vocabulary': 'Words',
  'spelling': 'Spelling',
  'maths': 'Numbers',
  'stories': 'Stories',
};
