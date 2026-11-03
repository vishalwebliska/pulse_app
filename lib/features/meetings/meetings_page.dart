import 'package:flutter/material.dart';

import '../../shared/placeholder_page.dart';

class MeetingsPage extends StatelessWidget {
  const MeetingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Meetings',
      icon: Icons.videocam_outlined,
      note: 'Join and host LiveKit video rooms here in Phase 2.',
    );
  }
}
