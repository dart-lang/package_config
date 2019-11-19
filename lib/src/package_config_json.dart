// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:path/path.dart" as path;

import "package_config_impl.dart";
import "packages_file.dart" as packagesfile;
import "util.dart";

const String _configVersionKey = "configVersion";
const String _packagesKey = "packages";
const String _nameKey = "name";
const String _rootUriKey = "rootUri";
const String _packageUriKey = "packageUri";
const String _languageVersionKey = "languageVersion";
const String _generatedKey = "generated";
const String _generatorKey = "generator";
const String _generatorVersionKey = "generatorVersion";

/// Reads a package configuration file.
///
/// Detects whether the [file] is a version one `.packages` file or
/// a version two `package_config.json` file.
///
/// If the [file] is a `.packages` file, first checks whether there is an
/// adjacent `.dart_tool/package_config.json` file, and if so,
/// reads that instead.
///
/// The file must exist and be a normal file.
PackageConfig readAnyConfigFile(File file,
    [Map<String, dynamic> /*?*/ extraData]) {
  var bytes = file.readAsBytesSync();
  for (int i = 0; i < bytes.length; i++) {
    var char = bytes[i];
    if (char == 0x20 || char == 0x09 || char == 0x0a || char == 0x0d) {
      // Skip whitespace.
      continue;
    }
    if (char == 0x7b /*{*/) {
      // Probably JSON, definitely not .packages.
      return parsePackageConfigBytes(bytes, file, extraData);
    }
    break;
  }
  // File is not JSON.
  var alternateFile = File(
      path.join(path.dirname(file.path), ".dart_tool", "package_config.json"));
  if (alternateFile.existsSync()) {
    return parsePackageConfigBytes(
        alternateFile.readAsBytesSync(), alternateFile, extraData);
  }
  return _parseDotPackagesConfig(bytes, file);
}

PackageConfig readPackageConfigJsonFile(File file,
        [Map<String, dynamic> /*?*/ extraData]) =>
    parsePackageConfigBytes(file.readAsBytesSync(), file, extraData);

PackageConfig readDotPackagesFile(File file) =>
    packagesfile.parse(file.readAsBytesSync(), Uri.file(file.path));

PackageConfig parsePackageConfigBytes(Uint8List bytes, File file,
    [Map<String, dynamic> /*?*/ extraData]) {
  // TODO(lrn): Make this simpler. Maybe parse directly from bytes.
  return parsePackageConfigJson(
      json.fuse(utf8).decode(bytes), Uri.file(file.path), extraData);
}

/// Creates a [PackageConfig] from a parsed JSON-like object structure.
///
/// The [json] argument must be a JSON object (`Map<String, dynamic>`)
/// containing a `"configVersion"` entry with an integer value in the range
/// 1 to [PackageConfig.maxVersion],
/// and with a `"packages"` entry which is a JSON array (`List<dynamic>`)
/// containing JSON objects which each has the following properties:
///
/// * `"name"`: The package name as a string.
/// * `"rootUri"`: The root of the package as a URI stored as a string.
/// * `"packageUri"`: Optionally the root of for `package:` URI resolution
///     for the package, as a relative URI below the root URI
///     stored as a string.
/// * `"languageVersion"`: Optionally a language version string which is a
///     an integer numeral, a decimal point (`.`) and another integer numeral,
///     where the integer numeral cannot have a sign, and can only have a
///     leading zero if the entire numeral is a single zero.
///
/// All other properties are ignored.
///
/// The [baseLocation] is used as base URI to resolve the "rootUri"
/// URI referencestring.
PackageConfig parsePackageConfigJson(dynamic json, Uri baseLocation,
    [Map<String, dynamic> /*?*/ extraData]) {
  if (!baseLocation.hasScheme || baseLocation.isScheme("package")) {
    throw ArgumentError.value(baseLocation.toString(), "baseLocation",
        "Must be an absolute non-package: URI");
  }
  if (!baseLocation.path.endsWith("/")) {
    baseLocation = baseLocation.resolveUri(Uri(path: "."));
  }
  var map = json;
  if (map is Map<String, dynamic>) {
    var version = map[_configVersionKey];
    if (version is int && version > 0 && version <= PackageConfig.maxVersion) {
      var packageList = map[_packagesKey];
      if (packageList is List<dynamic>) {
        List<Package> accumulator = [];
        for (var packageEntry in packageList) {
          if (packageEntry is Map<String, dynamic>) {
            Object /*?*/ name = packageEntry[_nameKey];
            if (name is String) {
              Object /*?*/ root = packageEntry[_rootUriKey];
              if (root is String) {
                Uri rootUri = baseLocation.resolve(root);
                Uri packageUriRootUri = rootUri;
                Object /*?*/ packageUriRoot = packageEntry[_packageUriKey];
                if (packageUriRoot != null ||
                    packageEntry.containsKey(_packageUriKey)) {
                  // The value is optional.
                  if (packageUriRoot is String) {
                    packageUriRootUri = rootUri.resolve(packageUriRoot);
                  } else {
                    throw FormatException(
                        "Package $name's packageUri is not a string",
                        packageUriRoot);
                  }
                }
                Object /*?*/ languageVersion =
                    packageEntry[_languageVersionKey];
                if (packageEntry.containsKey(_languageVersionKey) &&
                    languageVersion is! String) {
                  throw FormatException(
                      "Package $name's languageVersion is not a string",
                      languageVersion);
                }
                Package package;
                try {
                  package = SimplePackage(
                      name, rootUri, packageUriRootUri, languageVersion);
                } on ArgumentError catch (e) {
                  throw FormatException(e.message, e.invalidValue);
                }
                accumulator.add(package);
                continue;
              } else {
                throw FormatException(
                    root == null
                        ? "Missing package root"
                        : "Package root is not a string",
                    root);
              }
            } else {
              throw FormatException(
                  name == null
                      ? "Missing package name"
                      : "Package name is not a string",
                  name);
            }
          } else {
            throw FormatException(
                "Package entry is not a JSON object", packageEntry);
          }
        }
        if (extraData != null) {
          for (var key in map.keys) {
            if (key != _configVersionKey && key != _packagesKey) {
              extraData[key] = map[key];
            }
          }
        }
        try {
          return SimplePackageConfig(version, accumulator);
        } on ArgumentError catch (e) {
          throw FormatException(e.message, e.invalidValue);
        }
      }
      throw FormatException(
          packageList == null
              ? "Missing packages list"
              : 'Invalid packages: Not a list',
          packageList);
    }
    throw FormatException(
        version == null
            ? "Missing configVersion"
            : "Invalid configVersion number",
        version);
  }
  throw FormatException("Not a JSON object", map);
}

PackageConfig _parseDotPackagesConfig(Uint8List bytes, File file) {
  return packagesfile.parse(bytes, Uri.file(file.path));
}

void writePackageConfigJson(PackageConfig config, Directory targetDirectory,
    Map<String, dynamic> /*?*/ extraData) {
  // Write .dart_tool/package_config.json first.
  var file = File(
      path.join(targetDirectory.path, ".dart_tool", "package_config.json"));
  var baseUri = Uri.file(file.path);
  var data = <String, dynamic>{
    _configVersionKey: PackageConfig.maxVersion,
    _packagesKey: [
      for (var package in config.packages)
        <String, dynamic>{
          _nameKey: package.name,
          _rootUriKey: relativizeUri(package.root, baseUri),
          if (package.root != package.packageUriRoot)
            _packageUriKey: relativizeUri(package.packageUriRoot, package.root),
          if (package.languageVersion != null)
            _languageVersionKey: package.languageVersion
        }
    ]
  };

  extraData?.forEach((key, value) {
    if (key == _configVersionKey || key == _packagesKey) return; // Ignore.
    data[key] = value;
  });

  file.writeAsStringSync(JsonEncoder.withIndent("  ").convert(data));

  // Write .packages too.
  String /*?*/ generator = extraData[_generatorKey];
  String /*?*/ comment;
  if (generator != null) {
    String /*?*/ generated = extraData[_generatedKey];
    String /*?*/ generatorVersion = extraData[_generatorVersionKey];
    comment = "Generated by $generator"
        "${generatorVersion != null ? " $generatorVersion" : ""}"
        "${generated != null ? " on $generated" : ""}.";
  }
  file = File(path.join(targetDirectory.path, ".packages"));
  baseUri = Uri.file(file.path);
  var buffer = StringBuffer();
  packagesfile.write(buffer, config, baseUri: baseUri, comment: comment);
  file.writeAsStringSync(buffer.toString());
}
