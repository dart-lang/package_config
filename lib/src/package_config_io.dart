// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// dart:io dependent functionality for reading and writing configuration files.

import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "errors.dart";
import "package_config_impl.dart";
import "package_config_json.dart";
import "packages_file.dart" as packages_file;
import "util.dart";
import "util_io.dart";

/// Reads a package configuration file.
///
/// Detects whether the [file] is a version one `.packages` file or
/// a version two `package_config.json` file.
///
/// If the [file] is a `.packages` file and [preferNewest] is true,
/// first checks whether there is an adjacent `.dart_tool/package_config.json`
/// file, and if so, reads that instead.
/// If [preferNewset] is false, the specified file is loaded even if it is
/// a `.packages` file and there is an available `package_config.json` file.
///
/// The file must exist and be a normal file.
Future<PackageConfig> readAnyConfigFile(
    File file, bool preferNewest, void onError(Object error)) async {
  if (preferNewest && fileName(file.path) == ".packages") {
    var alternateFile =
        File(pathJoin(dirName(file.path), ".dart_tool", "package_config.json"));
    if (alternateFile.existsSync()) {
      return await readPackageConfigJsonFile(alternateFile, onError);
    }
  }
  Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (e) {
    onError(e);
    return const SimplePackageConfig.empty();
  }
  return parseAnyConfigFile(bytes, file.uri, onError);
}

/// Like [readAnyConfigFile] but uses a URI and an optional loader.
Future<PackageConfig> readAnyConfigFileUri(
    Uri file,
    Future<Uint8List?> loader(Uri uri)?,
    void onError(Object error),
    bool preferNewest) async {
  if (file.isScheme("package")) {
    throw PackageConfigArgumentError(
        file, "file", "Must not be a package: URI");
  }
  if (loader == null) {
    if (file.isScheme("file")) {
      return await readAnyConfigFile(File.fromUri(file), preferNewest, onError);
    }
    loader = defaultLoader;
  }
  if (preferNewest && file.pathSegments.last == ".packages") {
    var alternateFile = file.resolve(".dart_tool/package_config.json");
    Uint8List? bytes;
    try {
      bytes = await loader(alternateFile);
    } catch (e) {
      onError(e);
      return const SimplePackageConfig.empty();
    }
    if (bytes != null) {
      return parsePackageConfigBytes(bytes, alternateFile, onError);
    }
  }
  Uint8List? bytes;
  try {
    bytes = await loader(file);
  } catch (e) {
    onError(e);
    return const SimplePackageConfig.empty();
  }
  if (bytes == null) {
    onError(PackageConfigArgumentError(
        file.toString(), "file", "File cannot be read"));
    return const SimplePackageConfig.empty();
  }
  return parseAnyConfigFile(bytes, file, onError);
}

/// Parses a `.packages` or `package_config.json` file's contents.
///
/// Assumes it's a JSON file if the first non-whitespace character
/// is `{`, otherwise assumes it's a `.packages` file.
PackageConfig parseAnyConfigFile(
    Uint8List bytes, Uri file, void onError(Object error)) {
  var firstChar = firstNonWhitespaceChar(bytes);
  if (firstChar != $lbrace) {
    // Definitely not a JSON object, probably a .packages.
    return packages_file.parse(bytes, file, onError);
  }
  return parsePackageConfigBytes(bytes, file, onError);
}

Future<PackageConfig> readPackageConfigJsonFile(
    File file, void onError(Object error)?) async {
  Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (error) {
    onError!(error);
    return const SimplePackageConfig.empty();
  }
  return parsePackageConfigBytes(bytes, file.uri, onError);
}

Future<PackageConfig> readDotPackagesFile(
    File file, void onError(Object error)?) async {
  Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (error) {
    onError!(error);
    return const SimplePackageConfig.empty();
  }
  return packages_file.parse(bytes, file.uri, onError);
}

Future<void> writePackageConfigJsonFile(
    PackageConfig config, Directory targetDirectory) async {
  // Write .dart_tool/package_config.json first.
  var file =
      File(pathJoin(targetDirectory.path, ".dart_tool", "package_config.json"));
  var baseUri = file.uri;
  var sink = file.openWrite(encoding: utf8);
  writePackageConfigJsonUtf8(config, baseUri, sink);
  var doneJson = sink.close();

  // Write .packages too.
  file = File(pathJoin(targetDirectory.path, ".packages"));
  baseUri = file.uri;
  sink = file.openWrite(encoding: utf8);
  writeDotPackages(config, baseUri, sink);
  var donePackages = sink.close();

  await Future.wait([doneJson, donePackages]);
}
