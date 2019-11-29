// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A package configuration is a way to assign file paths to package URIs,
/// and vice-versa,
library package_config.package_config;

import "dart:io" show File, Directory;
import "src/discovery.dart" as discover;
import "src/package_config.dart";
import "src/package_config_json.dart";

export "src/package_config.dart" show PackageConfig, Package;

/// Reads a specific package configuration file.
///
/// The file must exist and be readable.
/// It must be either a valid `package_config.json` file
/// or a valid `.packages` file.
/// It is considered a `package_config.json` file if its first character
/// is a `{`.
///
/// If the file is a `.packages` file, first checks if there is a
/// `.dart_tool/package_config.json` file next to the original file,
/// and if so, loads that instead.
///
/// If [extraData] is provided, and the loaded file is a `package_config.json`
/// file, then any unknown JSON object entries in the main JSON object of the
/// file are added to [extraData] with the same name.
Future<PackageConfig> loadPackageConfig(File file) => readAnyConfigFile(file);

/// Finds a package configuration relative to [directory].
///
/// If [directory] contains a package configuration,
/// either a `.dart_tool/package_config.json` file or,
/// if not, a `.packages`, then that file is loaded.
///
/// If no file is found in the current directory,
/// then the parent directories are checked instead recursively,
/// all the way to the root directory.
///
/// If no configuration file is found, the [PackageConfig.empty] constant object
/// is returned.
///
/// If [extraData] is provided, and the loaded file is a `package_config.json`
/// file, then any unknown JSON object entries in the main JSON object of the
/// file are added to [extraData] with the same name.
Future<PackageConfig> findPackageConfig(Directory directory) =>
    discover.findPackageConfig(directory);

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
/// A comment is generated if `extraData` contains a `"generator"` entry.
Future<void> savePackageConfig(
        PackageConfig configuration, Directory directory) =>
    writePackageConfigJson(configuration, directory);
