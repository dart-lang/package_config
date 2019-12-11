// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A package configuration is a way to assign file paths to package URIs,
/// and vice-versa,
library package_config.package_config;

import "dart:io" show File, Directory;
import "dart:typed_data" show Uint8List;
import "src/discovery.dart" as discover;
import "src/package_config.dart";
import "src/package_config_json.dart";

export "src/package_config.dart" show PackageConfig, Package;
export "src/errors.dart" show PackageConfigError;

/// Reads a specific package configuration file.
///
/// The file must exist and be readable.
/// It must be either a valid `package_config.json` file
/// or a valid `.packages` file.
/// It is considered a `package_config.json` file if its first character
/// is a `{`.
///
/// If the file is a `.packages` file, also checks if there is a
/// `.dart_tool/package_config.json` file next to the original file,
/// and if so, loads that instead.
Future<PackageConfig> loadPackageConfig(File file) => readAnyConfigFile(file);

/// Reads a specific package configuration URI.
///
/// The file of the URI must exist and be readable.
/// It must be either a valid `package_config.json` file
/// or a valid `.packages` file.
/// It is considered a `package_config.json` file if its first
/// non-whitespace character is a `{`.
///
/// If the file is a `.packages` file, first checks if there is a
/// `.dart_tool/package_config.json` file next to the original file,
/// and if so, loads that instead.
/// The [file] *must not* be a `package:` URI.
///
/// If [loader] is provided, URIs are loaded using that function.
/// The future returned by the loader must complete with a [Uint8List]
/// containing the entire file content,
/// or with `null` if the file does not exist.
/// The loader may throw at its own discretion, for situations where
/// it determines that an error might be need user attention,
/// but it is always allowed to return `null`.
/// This function makes no attempt to catch such errors.
///
/// If no [loader] is supplied, a default loader is used which
/// only accepts `file:`,  `http:` and `https:` URIs,
/// and which uses the platform file system and HTTP requests to
/// fetch file content. The default loader never throws because
/// of an I/O issue, as long as the location URIs are valid.
/// As such, it does not distinguish between a file not existing,
/// and it being temporarily locked or unreachable.
Future<PackageConfig> loadPackageConfigUri(Uri file,
        {Future<Uint8List/*?*/> loader(Uri uri) /*?*/}) =>
    readAnyConfigFileUri(file, loader);

/// Finds a package configuration relative to [directory].
///
/// If [directory] contains a package configuration,
/// either a `.dart_tool/package_config.json` file or,
/// if not, a `.packages`, then that file is loaded.
///
/// If no file is found in the current directory,
/// then the parent directories are checked recursively,
/// all the way to the root directory, to check if those contains
/// a package configuration.
/// If [recurse] is set to [false], this parent directory check is not
/// performed.
///
/// Returns `null` if no configuration file is found.
Future<PackageConfig> findPackageConfig(Directory directory,
        {bool recurse = true}) =>
    discover.findPackageConfig(directory, recurse);

/// Finds a package configuration relative to [location].
///
/// If [location] contains a package configuration,
/// either a `.dart_tool/package_config.json` file or,
/// if not, a `.packages`, then that file is loaded.
/// The [location] URI *must not* be a `package:` URI.
/// It should be a hierarchical URI which is supported
/// by [loader].
///
/// If no file is found in the current directory,
/// then the parent directories are checked recursively,
/// all the way to the root directory, to check if those contains
/// a package configuration.
/// If [recurse] is set to [false], this parent directory check is not
/// performed.
///
/// If [loader] is provided, URIs are loaded using that function.
/// The future returned by the loader must complete with a [Uint8List]
/// containing the entire file content,
/// or with `null` if the file does not exist.
/// The loader may throw at its own discretion, for situations where
/// it determines that an error might be need user attention,
/// but it is always allowed to return `null`.
/// This function makes no attempt to catch such errors.
///
/// If no [loader] is supplied, a default loader is used which
/// only accepts `file:`,  `http:` and `https:` URIs,
/// and which uses the platform file system and HTTP requests to
/// fetch file content. The default loader never throws because
/// of an I/O issue, as long as the location URIs are valid.
/// As such, it does not distinguish between a file not existing,
/// and it being temporarily locked or unreachable.
///
/// Returns `null` if no configuration file is found.
Future<PackageConfig> findPackageConfigUri(Uri location,
        {bool recurse = true, Future<Uint8List /*?*/ > loader(Uri uri)}) =>
    discover.findPackageConfigUri(location, loader, recurse);

/// Writes a package configuration to the provided directory.
///
/// Writes `.dart_tool/package_config.json` relative to [directory].
/// If the `.dart_tool/` directory does not exist, it is created.
/// If it cannot be created, this operation fails.
///
/// If [extraData] contains any entries, they are added to the JSON
/// written to the `package_config.json` file. Entries with the names
/// `"configVersion"` or `"packages"` are ignored, all other entries
/// are added verbatim.
/// This is intended for, e.g., the
/// `"generator"`, `"generated"` and `"generatorVersion"`
/// properties.
///
/// Also writes a `.packages` file in [directory].
/// This will stop happening eventually as the `.packages` file becomes
/// discontinued.
/// A comment is generated if `[PackageConfig.extraData]` contains a
/// `"generator"` entry.
Future<void> savePackageConfig(
        PackageConfig configuration, Directory directory) =>
    writePackageConfigJson(configuration, directory);
