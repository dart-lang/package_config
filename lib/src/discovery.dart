// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:io";

import "package:path/path.dart" as path;

import "package_config_impl.dart";
import "package_config_json.dart";

/// Discover the package configuration for a Dart script.
///
/// The [baseDirectory] points to the directory of the Dart script.
/// A package resolution strategy is found by going through the following steps,
/// and stopping when something is found.
///
/// * Check if a `.dart_tool/package_config.json` file exists in the directory.
/// * Check if a `.packages` file exists in a directory.
/// * Repeat these checks for the parent directories until reaching the
///   root directory.
///
/// If any of these tests succeed, a `PackageConfig` class is returned.
/// Returns `null` if no configuration was found. If a configuration
/// is needed, then the caller can supply [PackageConfig.empty].
Future<PackageConfig /*?*/ > findPackageConfig(Directory baseDirectory) async {
  var directory = baseDirectory;
  if (!directory.isAbsolute) directory = directory.absolute;
  if (!await directory.exists()) {
    throw new ArgumentError.value(
        baseDirectory, "baseDirectory", "Directory does not exist.");
  }
  while (true) {
    // Check for $cwd/.packages
    var packageConfig = await findPackagConfigInDirectory(directory);
    if (packageConfig != null) return packageConfig;
    // Check in cwd(/..)+/
    var parentDirectory = directory.parent;
    if (parentDirectory.path == directory.path) break;
    directory = parentDirectory;
  }
  return null;
}

/// Finds a `.packages` or `.dart_tool/package_config.json` file in [directory].
///
/// Loads the file, if it is there, and returns the resulting [PackageConfig].
/// Returns `null` if the file isn't there.
/// Throws [FormatException] if a file is there but is not valid.
///
/// If [extraData] is supplied and the `package_config.json` contains extra
/// entries in the top JSON object, those extra entries are stored into
/// [extraData].
Future<PackageConfig /*?*/ > findPackagConfigInDirectory(
    Directory directory) async {
  var packageConfigFile = await checkForPackageConfigJsonFile(directory);
  if (packageConfigFile != null) {
    return await readPackageConfigJsonFile(packageConfigFile);
  }
  packageConfigFile = await checkForDotPackagesFile(directory);
  if (packageConfigFile != null) {
    return await readDotPackagesFile(packageConfigFile);
  }
  return null;
}

Future<File> /*?*/ checkForPackageConfigJsonFile(Directory directory) async {
  assert(directory.isAbsolute);
  var file =
      File(path.join(directory.path, ".dart_tool", "package_config.json"));
  if (await file.exists()) return file;
  return null;
}

Future<File /*?*/ > checkForDotPackagesFile(Directory directory) async {
  var file = File(path.join(directory.path, ".packages"));
  if (await file.exists()) return file;
  return null;
}
