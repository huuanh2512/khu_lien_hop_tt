class JsonUtils {
  static final RegExp _objectIdPattern = RegExp(r'^[0-9a-fA-F]{24}$');
  static final RegExp _objectIdWrapperPattern =
      RegExp(r'''^(?:new\s+)?ObjectId\s*\(\s*(?:["']?)([0-9a-fA-F]{24})(?:["']?)\s*\)$''');

  static String parseId(dynamic v) {
    if (v == null) return '';

    String? extractValue(Object? input) {
      if (input == null) return null;
      if (input is String) {
        final trimmed = input.trim();
        if (trimmed.isEmpty) return '';
        if (_objectIdPattern.hasMatch(trimmed)) return trimmed;
        final wrapperMatch = _objectIdWrapperPattern.firstMatch(trimmed);
        if (wrapperMatch != null) return wrapperMatch.group(1);
        return trimmed;
      }
      if (input is Map) {
        const preferredKeys = [r'$oid', 'oid', 'id', '_id'];
        for (final key in preferredKeys) {
          if (input.containsKey(key)) {
            final extracted = extractValue(input[key]);
            if (extracted != null && extracted.isNotEmpty) {
              return extracted;
            }
          }
        }
      }
      final text = input.toString().trim();
      if (text.isEmpty) return '';
      if (_objectIdPattern.hasMatch(text)) return text;
      final wrapperMatch = _objectIdWrapperPattern.firstMatch(text);
      if (wrapperMatch != null) return wrapperMatch.group(1);
      return text;
    }

    final normalized = extractValue(v);
    return normalized ?? '';
  }

  static String? parseIdOrNull(dynamic v) {
    final s = parseId(v);
    return s.isEmpty ? null : s;
  }
}
