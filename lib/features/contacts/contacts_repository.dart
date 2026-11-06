import 'package:dio/dio.dart';

import '../../core/api_client.dart';

/// One email's discovery result: is this address already a Flaxxa user?
class ContactLookup {
  ContactLookup({
    required this.email,
    required this.registered,
    this.userId,
    this.name,
  });

  final String email;
  final bool registered;
  final int? userId;
  final String? name;

  factory ContactLookup.fromJson(Map<String, dynamic> j) {
    final user = j['user'];
    return ContactLookup(
      email: (j['email'] ?? '').toString(),
      registered: j['registered'] == true,
      userId: user is Map ? user['id'] as int? : null,
      name: user is Map ? user['name'] as String? : null,
    );
  }
}

/// Outcome of inviting an email into the caller's workspace.
enum InviteOutcome { invited, alreadyMember, self }

/// Contact discovery + invite over `/auth/mobile/contacts/*` (PAT-authed,
/// workspace-agnostic lookup; invite targets the caller's personal workspace).
class ContactsRepository {
  ContactsRepository._();
  static final ContactsRepository instance = ContactsRepository._();

  Dio get _dio => ApiClient.instance.dio;

  /// Which of [emails] are already Flaxxa users. Batched; order follows input.
  Future<List<ContactLookup>> lookup(List<String> emails) async {
    if (emails.isEmpty) return const [];
    final res = await _dio.post(
      '/auth/mobile/contacts/lookup',
      data: {'emails': emails},
    );
    final list = (res.data['data'] as List? ?? []);
    return list
        .map((e) => ContactLookup.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Invite an email into the caller's (personal) workspace. Sends the Omnio
  /// invitation; returns what happened.
  Future<InviteOutcome> invite(String email) async {
    try {
      await _dio.post('/auth/mobile/contacts/invite', data: {'email': email});
      return InviteOutcome.invited;
    } on DioException catch (e) {
      final body = e.response?.data;
      if (e.response?.statusCode == 409 &&
          body is Map &&
          body['already_member'] == true) {
        return InviteOutcome.alreadyMember;
      }
      if (e.response?.statusCode == 422 &&
          body is Map &&
          body['self_invite'] == true) {
        return InviteOutcome.self;
      }
      rethrow;
    }
  }
}
