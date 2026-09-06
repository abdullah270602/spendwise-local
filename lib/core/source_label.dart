/// What to call an app when SpendWise has to talk about it.
///
/// Review asks questions like "nothing from X parsed as a transaction". When
/// X is `com.android.messaging` the question reads as being about someone
/// else's phone, and the user cannot answer it. Android knows the real label
/// for every installed app, so that is the first answer; the stored name is
/// the second; and only when the app is gone entirely do we fall back to
/// making the package id look like a word.
String sourceLabel({
  required String? packageName,
  required String stored,
  required Map<String, String> installedLabels,
}) {
  if (packageName == null || packageName.isEmpty) return stored;

  final live = installedLabels[packageName]?.trim();
  if (live != null && live.isNotEmpty && live != packageName) return live;

  final trimmed = stored.trim();
  if (trimmed.isNotEmpty &&
      trimmed != packageName &&
      trimmed != 'Unknown app') {
    return trimmed;
  }
  return prettyPackageLabel(packageName);
}

/// A last resort for an app Android can no longer name: take the most
/// specific part of the id and make it look like a word. It is a guess, not
/// the real label — but "Messaging" beats "com.android.messaging", and a
/// wrong-but-readable name is still answerable.
String prettyPackageLabel(String packageName) {
  final parts = packageName
      .split('.')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return packageName;

  // Trailing segments like `.app`, `.android` or `.mobile` are packaging, not
  // the name. Walk back to the last segment that carries meaning.
  const noise = {'app', 'apps', 'android', 'mobile', 'client', 'prod'};
  var index = parts.length - 1;
  while (index > 0 && noise.contains(parts[index].toLowerCase())) {
    index--;
  }

  final word = parts[index].replaceAll(RegExp(r'[_\d]+'), ' ').trim();
  if (word.isEmpty) return packageName;
  return word[0].toUpperCase() + word.substring(1);
}
