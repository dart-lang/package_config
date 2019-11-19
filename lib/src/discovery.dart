// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
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
///
/// This function currently only supports `file`, `http` and `https` URIs.
/// It needs to be able to load a `.packages` file from the URI, so only
/// recognized schemes are accepted.
///
/// To support other schemes, or more complex HTTP requests,
/// an optional [loader] function can be supplied.
/// It's called to load the `.packages` file for a non-`file` scheme.
/// The loader function returns the *contents* of the file
/// identified by the URI it's given.
/// The content should be a UTF-8 encoded `.packages` file, and must return an
/// error future if loading fails for any reason.
///
/// If [extraData] is provided, and the loaded file is a `package_config.json`
/// file, then any unknown JSON object entries in the main JSON object of the
/// file are added to [extraData] with the same name.
PackageConfig/*?*/ findPackageConfig(Directory baseDirectory,
    [Map<String, dynamic> /*?*/ extraData]) {
  var directory = baseDirectory;
  if (!directory.isAbsolute) directory = directory.absolute;
  if (!directory.existsSync()) {
    throw new ArgumentError.value(
        baseDirectory, "baseDirectory", "Directory does not exist.");
  }
  while (true) {
    // Check for $cwd/.packages
    var packageConfig = findPackagConfigInDirectory(directory, extraData);
    if (packageConfig != null) return packageConfig;
    // Check in cwd(/..)+/
    var parentDirectory = directory.parent;
    if (parentDirectory.path == directory.path) break;
  }
  return null;
}

PackageConfig /*?*/ findPackagConfigInDirectory(Directory directory,
    [Map<String, dynamic> /*?*/ extraData]) {
  var packageConfigFile = checkForPackageConfigJsonFile(directory);
  if (packageConfigFile != null) {
    return readPackageConfigJsonFile(packageConfigFile, extraData);
  }
  packageConfigFile = checkForDotPackagesFile(directory);
  if (packageConfigFile != null) {
    return readDotPackagesFile(packageConfigFile);
  }
  return null;
}

File /*?*/ checkForPackageConfigJsonFile(Directory directory) {
  assert(directory.isAbsolute);
  var file =
      File(path.join(directory.path, ".dart_tool", "package_config.json"));
  if (file.existsSync()) return file;
  return null;
}

File /*?*/ checkForDotPackagesFile(Directory directory) {
  var file = File(path.join(directory.path, ".packages"));
  if (file.existsSync()) return file;
  return null;
}
