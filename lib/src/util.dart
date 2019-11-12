// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Utility methods used by more than one library in the package.
library package_config.util;

import "package:charcode/ascii.dart";

// All ASCII characters that are valid in a package name, with space
// for all the invalid ones (including space).
const String _validPackageNameCharacters =
    r"                                 !  $ &'()*+,-. 0123456789 ; =  "
    r"@ABCDEFGHIJKLMNOPQRSTUVWXYZ    _ abcdefghijklmnopqrstuvwxyz   ~ ";

/// Tests whether something is a valid Dart package name.
bool isValidPackageName(String string) {
  return checkPackageName(string) < 0;
}

/// Check if a string is a valid package name.
///
/// Valid package names contain only characters in [_validPackageNameCharacters]
/// and must contain at least one non-'.' character.
///
/// Returns `-1` if the string is valid.
/// Otherwise returns the index of the first invalid character,
/// or `string.length` if the string contains no non-'.' character.
int checkPackageName(String string) {
  // Becomes non-zero if any non-'.' character is encountered.
  int nonDot = 0;
  for (int i = 0; i < string.length; i++) {
    var c = string.codeUnitAt(i);
    if (c > 0x7f || _validPackageNameCharacters.codeUnitAt(c) <= $space) {
      return i;
    }
    nonDot += c ^ $dot;
  }
  if (nonDot == 0) return string.length;
  return -1;
}

/// Validate that a Uri is a valid package:URI.
String checkValidPackageUri(Uri packageUri) {
  if (packageUri.scheme != "package") {
    throw new ArgumentError.value(
        packageUri, "packageUri", "Not a package: URI");
  }
  if (packageUri.hasAuthority) {
    throw new ArgumentError.value(
        packageUri, "packageUri", "Package URIs must not have a host part");
  }
  if (packageUri.hasQuery) {
    // A query makes no sense if resolved to a file: URI.
    throw new ArgumentError.value(
        packageUri, "packageUri", "Package URIs must not have a query part");
  }
  if (packageUri.hasFragment) {
    // We could leave the fragment after the URL when resolving,
    // but it would be odd if "package:foo/foo.dart#1" and
    // "package:foo/foo.dart#2" were considered different libraries.
    // Keep the syntax open in case we ever get multiple libraries in one file.
    throw new ArgumentError.value(
        packageUri, "packageUri", "Package URIs must not have a fragment part");
  }
  if (packageUri.path.startsWith('/')) {
    throw new ArgumentError.value(
        packageUri, "packageUri", "Package URIs must not start with a '/'");
  }
  int firstSlash = packageUri.path.indexOf('/');
  if (firstSlash == -1) {
    throw new ArgumentError.value(packageUri, "packageUri",
        "Package URIs must start with the package name followed by a '/'");
  }
  String packageName = packageUri.path.substring(0, firstSlash);
  int badIndex = checkPackageName(packageName);
  if (badIndex >= 0) {
    if (packageName.isEmpty) {
      throw new ArgumentError.value(
          packageUri, "packageUri", "Package names mus be non-empty");
    }
    if (badIndex == packageName.length) {
      throw new ArgumentError.value(packageUri, "packageUri",
          "Package names must contain at least one non-'.' character");
    }
    assert(badIndex < packageName.length);
    int badCharCode = packageName.codeUnitAt(badIndex);
    var badChar = "U+" + badCharCode.toRadixString(16).padLeft(4, '0');
    if (badCharCode >= 0x20 && badCharCode <= 0x7e) {
      // Printable character.
      badChar = "'${packageName[badIndex]}' ($badChar)";
    }
    throw new ArgumentError.value(
        packageUri, "packageUri", "Package names must not contain $badChar");
  }
  return packageName;
}

/// Checks whether [version] is a valid Dart language version string.
///
/// The format is (as RegExp) `(0|[1-9]\d+)\.(0|[1-9]\d+)`.
///
/// Returns the position of the first invalid character, or -1 if
/// the string is valid.
/// If the string is terminated early, the result is the length of the string.
int checkValidVersionNumber(String version) {
  int index = 0;
  int dotsSeen = 0;
  outer:
  for (;;) {
    // Check for numeral.
    if (index == version.length) return index;
    int char = version.codeUnitAt(index++);
    int digit = char ^ 0x30;
    if (digit != 0) {
      if (digit < 9) {
        while (index < version.length) {
          char = version.codeUnitAt(index++);
          digit = char ^ 0x30;
          if (digit < 9) continue;
          if (char == 0x2e /*.*/) {
            if (dotsSeen > 0) return index - 1;
            dotsSeen = 1;
            continue outer;
          }
        }
        if (dotsSeen > 0) return -1;
        return index;
      }
      return index - 1;
    }
    // Leading zero means numeral is over.
    if (index >= version.length) {
      if (dotsSeen > 0) return -1;
      return index;
    }
    if (dotsSeen > 0) return index;
    char = version.codeUnitAt(index++);
    if (char != 0x2e /*.*/) return index - 1;
  }
}

/// Checks whether URI is just an absolute directory.
///
/// * It must have a scheme.
/// * It must not have a query or fragment.
/// * The path must start and end with `/`.
bool isAbsoluteDirectoryUri(Uri uri) {
  if (uri.hasQuery) return false;
  if (uri.hasFragment) return false;
  if (!uri.hasScheme) return false;
  var path = uri.path;
  if (!path.startsWith("/")) return false;
  if (!path.endsWith("/")) return false;
  return true;
}

/// Whether the former URI is a prefix of the latter.
bool isUriPrefix(Uri prefix, Uri path) {
  assert(!prefix.hasFragment);
  assert(!prefix.hasQuery);
  assert(!path.hasQuery);
  assert(!path.hasFragment);
  assert(prefix.path.endsWith('/'));
  return path.toString().startsWith(prefix.toString());
}

/// Attempts to return a relative URI for [uri].
///
/// The result URI satisfies `baseUri.resolveUri(result) == uri`,
/// but may be relative.
/// The `baseUri` must be absolute.
Uri relativizeUri(Uri uri, Uri baseUri) {
  assert(baseUri.isAbsolute);
  if (uri.hasQuery || uri.hasFragment) {
    uri = new Uri(
        scheme: uri.scheme,
        userInfo: uri.hasAuthority ? uri.userInfo : null,
        host: uri.hasAuthority ? uri.host : null,
        port: uri.hasAuthority ? uri.port : null,
        path: uri.path);
  }

  // Already relative. We assume the caller knows what they are doing.
  if (!uri.isAbsolute) return uri;

  if (baseUri.scheme != uri.scheme) {
    return uri;
  }

  // If authority differs, we could remove the scheme, but it's not worth it.
  if (uri.hasAuthority != baseUri.hasAuthority) return uri;
  if (uri.hasAuthority) {
    if (uri.userInfo != baseUri.userInfo ||
        uri.host.toLowerCase() != baseUri.host.toLowerCase() ||
        uri.port != baseUri.port) {
      return uri;
    }
  }

  baseUri = baseUri.normalizePath();
  List<String> base = baseUri.pathSegments.toList();
  if (base.isNotEmpty) {
    base = new List<String>.from(base)..removeLast();
  }
  uri = uri.normalizePath();
  List<String> target = uri.pathSegments.toList();
  if (target.isNotEmpty && target.last.isEmpty) target.removeLast();
  int index = 0;
  while (index < base.length && index < target.length) {
    if (base[index] != target[index]) {
      break;
    }
    index++;
  }
  if (index == base.length) {
    if (index == target.length) {
      return new Uri(path: "./");
    }
    return new Uri(path: target.skip(index).join('/'));
  } else if (index > 0) {
    return new Uri(
        path: '../' * (base.length - index) + target.skip(index).join('/'));
  } else {
    return uri;
  }
}
