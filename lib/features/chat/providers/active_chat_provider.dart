import 'package:flutter_riverpod/flutter_riverpod.dart';

// Stores the ID of the chat session currently visible on the screen
final activeChatSessionProvider = StateProvider<String?>((ref) => null);
