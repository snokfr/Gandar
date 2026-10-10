import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the library search query so the page can filter without a rebuild of
/// the underlying future provider.
class LibrarySearchController extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;

  void clear() => state = '';
}
