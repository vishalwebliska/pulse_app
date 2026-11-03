/// A workspace (tenant) the signed-in user belongs to. Comes from the login
/// response and `GET /auth/mobile/workspaces` (`{id, name, slug, status}`).
class Workspace {
  const Workspace({required this.id, required this.name, this.slug});

  final String id; // tenant UUID — goes in the X-Tenant-ID header
  final String name;
  final String? slug;

  factory Workspace.fromJson(Map<String, dynamic> j) => Workspace(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Workspace').toString(),
        slug: j['slug']?.toString(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, if (slug != null) 'slug': slug};
}
