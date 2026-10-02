import '../api/api_client.dart';
import '../models.dart';

/// Parent-facing API. All ownership is enforced server-side from the token.
class ZivooApi {
  ZivooApi(this._c);

  final ApiClient _c;

  Future<ParentProfile> me() async => ParentProfile.fromJson(await _c.get<Map<String, dynamic>>('/v1/me'));

  Future<ParentProfile> updateMe(Map<String, dynamic> changes) async =>
      ParentProfile.fromJson(await _c.patch<Map<String, dynamic>>('/v1/me', changes));

  Future<void> deleteAccount() => _c.post<dynamic>('/v1/me/delete', {'confirm': 'DELETE'});

  Future<List<Child>> children() async => [
    for (final j in await _c.get<List<dynamic>>('/v1/children')) Child.fromJson(j as Map<String, dynamic>),
  ];

  Future<Child> createChild({required String name, int? birthYear, String language = 'en-GB'}) async =>
      Child.fromJson(
        await _c.post<Map<String, dynamic>>('/v1/children', {
          'display_name': name,
          'birth_year': ?birthYear,
          'language': language,
        }),
      );

  Future<Child> updateChild(String id, Map<String, dynamic> changes) async =>
      Child.fromJson(await _c.patch<Map<String, dynamic>>('/v1/children/$id', changes));

  Future<void> deleteChild(String id) => _c.delete('/v1/children/$id');

  Future<LearningPreferences> preferences(String childId) async =>
      LearningPreferences.fromJson(await _c.get<Map<String, dynamic>>('/v1/children/$childId/preferences'));

  Future<LearningPreferences> savePreferences(
    String childId,
    Map<String, dynamic> payload,
    int baseVersion,
  ) async => LearningPreferences.fromJson(
    await _c.put<Map<String, dynamic>>('/v1/children/$childId/preferences', {
      ...payload,
      'base_version': baseVersion,
    }),
  );

  Future<List<Device>> devices() async => [
    for (final j in await _c.get<List<dynamic>>('/v1/devices')) Device.fromJson(j as Map<String, dynamic>),
  ];

  Future<Device> device(String id) async =>
      Device.fromJson(await _c.get<Map<String, dynamic>>('/v1/devices/$id'));

  Future<Device> updateDevice(String id, Map<String, dynamic> changes) async =>
      Device.fromJson(await _c.patch<Map<String, dynamic>>('/v1/devices/$id', changes));

  Future<void> removeDevice(String id) => _c.delete('/v1/devices/$id/ownership');

  Future<Device> resendConfig(String id) async =>
      Device.fromJson(await _c.post<Map<String, dynamic>>('/v1/devices/$id/config/resend'));

  /// Idempotent: [commandId] is a client-generated UUID; retries reuse it.
  Future<Map<String, dynamic>> sendCommand(String deviceId, String commandId, String kind) =>
      _c.post<Map<String, dynamic>>('/v1/devices/$deviceId/commands', {'id': commandId, 'kind': kind});

  Future<Map<String, dynamic>> command(String deviceId, String commandId) =>
      _c.get<Map<String, dynamic>>('/v1/devices/$deviceId/commands/$commandId');

  Future<Map<String, dynamic>> startClaim(String serial, String setupCode) =>
      _c.post<Map<String, dynamic>>('/v1/claims', {'serial': serial, 'setup_code': setupCode});

  Future<Map<String, dynamic>> claim(String id) => _c.get<Map<String, dynamic>>('/v1/claims/$id');

  Future<void> cancelClaim(String id) => _c.post<dynamic>('/v1/claims/$id/cancel');

  Future<List<Activity>> activities() async => [
    for (final j in await _c.get<List<dynamic>>('/v1/activities'))
      Activity.fromJson(j as Map<String, dynamic>),
  ];

  Future<Page<SessionSummary>> sessions({String? childId, String? cursor, int limit = 20}) async {
    final j = await _c.get<Map<String, dynamic>>(
      '/v1/sessions',
      query: {'child_id': ?childId, 'cursor': ?cursor, 'limit': limit},
    );
    return Page([
      for (final s in j['items'] as List) SessionSummary.fromJson(s as Map<String, dynamic>),
    ], j['next_cursor'] as String?);
  }

  Future<SessionDetail> session(String id) async =>
      SessionDetail.fromJson(await _c.get<Map<String, dynamic>>('/v1/sessions/$id'));

  Future<void> deleteSession(String id) => _c.delete('/v1/sessions/$id');
}
