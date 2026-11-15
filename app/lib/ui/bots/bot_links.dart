import 'package:flutter/material.dart';

import '../session/workspace_files.dart' show FilePreviewPage;

/// Opens a link that points into the conversation's workspace.
///
/// A Bot writes `[名字](quick-note.md)`: tapping it should show that file, not
/// hand the string to a browser. Only that shape is taken here — a real URL, a
/// mail address or a fragment returns false, so the default handler keeps its
/// behaviour for everything else.
///
/// [sessionId] is the Session whose working directory resolves the path: a Bot's
/// own Session on its page, the speaker's Session on a group line.
bool openLinkedFile(BuildContext context, {required String? sessionId, required String href}) {
  final id = sessionId;
  if (id == null || id.isEmpty) return false;
  final path = href.trim();
  if (path.isEmpty) return false;
  final lower = path.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('mailto:') ||
      lower.startsWith('tel:') ||
      path.startsWith('#')) {
    return false;
  }
  Navigator.of(context).push(FilePreviewPage.route(sessionId: id, path: path));
  return true;
}
