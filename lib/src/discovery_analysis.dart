// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Analyse a directory structure and find packages resolvers for each
/// subdirectory.
///
/// The resolvers are generally the same that would be found by using
/// the `discovery.dart` library on each subdirectory in turn,
/// but more efficiently.
library package_config.discovery_analysis;

import "dart:collection" show HashMap;
import "dart:io" show Directory, Platform;

import "package:path/path.dart" as path;

import "package_config.dart";
import "discovery.dart";

/// Associates a [PackageConfig] with a directory.
///
/// The package resolution applies to the directory and any subdirectory
/// that doesn't have its own overriding child [PackageContext].
abstract class PackageContext {
  /// The directory which introduced the [packageCOnfig] resolver.
  Directory get directory;

  /// The [PackageConfig] that applies to the directory.
  ///
  /// Introduced either by a `.dart_tool/package_config.json` file or a
  /// `.packages` file in the [directory].
  PackageConfig get packageConfig;

  /// Look up the [PackageConfig] that applies to a specific directory.
  ///
  /// The [subdirectory] must be inside [directory].
  PackageConfig operator [](Directory subdirectory);

  /// Child immediate contexts that apply to subdirectories of [directory].
  Iterable<PackageContext> get children;

  /// A map from directory to package resolver.
  ///
  /// Has an entry for this package context and for each immediate child context
  /// contained in this one.
  Map<Directory, PackageConfig> asMap();

  /// Analyze [directory] and subdirectories for package configurations.
  ///
  /// Returns a context mapping subdirectories to [PackageConfig] objects.
  ///
  /// The analysis assumes that there are no package configuration files
  /// in a parent directory of `directory`.
  /// If there is, its corresponding [PackageConfig] object
  /// should be provided as [root].
  ///
  /// Each directory visited is checked for the presence of a `.packages`
  /// or `.dart_tool/package_config.json` file. If such a file exists,
  /// it is loaded. If loading fails, the directory is treated as if
  /// no configuration was found.
  /// If [onError] is supplied, the error that caused loading to fail
  /// is reported to that function, otherwise it's ignored.
  ///
  /// If [directoryFilter] is provided, each subdirectory is passed to this
  /// function, and if it returns `false`, the subdirectory is skipped in
  /// the analysis. If it returns `true`, the subdirectory is recursively
  /// analysed to find package configurations.
  /// If [directoryFilter] is omitted, it defaults
  /// to the [skipDartToolDir] filter.
  /// To skip all directories starting with `.`, the [skipDotDir] filter
  /// can be used.
  static PackageContext findAll(Directory directory,
      {PackageConfig root = PackageConfig.empty,
      bool directoryFilter(Directory subdir) = skipDartToolDir,
      void onError(Directory directory, Object error)}) {
    if (!directory.existsSync()) {
      throw ArgumentError("Directory not found: $directory");
    }
    directoryFilter ??= skipDartToolDir;
    var contexts = <PackageContext>[];
    void findRoots(Directory directory, List<PackageContext> contexts) {
      PackageConfig /*?*/ packageConfig;
      try {
        packageConfig = findPackagConfigInDirectory(directory);
      } catch (e) {
        if (onError != null) onError(directory, e);
      }
      List<PackageContext> subContexts = packageConfig == null ? contexts : [];
      for (var entry in directory.listSync()) {
        if (entry is Directory && directoryFilter(entry)) {
          findRoots(entry, subContexts);
        }
      }
      if (packageConfig != null) {
        contexts.add(_PackageContext(directory, packageConfig, subContexts));
      }
    }

    findRoots(directory, contexts);
    // If the root is not itself context root, add a the wrapper context.
    if (contexts.length == 1 && contexts[0].directory == directory) {
      return contexts[0];
    }
    return _PackageContext(directory, root, contexts);
  }

  /// A directory filter which includes all directories not named `.dart_tool`.
  ///
  /// This is the default filter used by [findAll].
  static bool skipDartToolDir(Directory directory) =>
      path.basename(directory.path) != ".dart_tool";

  /// A directory filter which includes all directories not starting with `.`.
  static bool skipDotDir(Directory directory) =>
      !path.basename(directory.path).startsWith(".");
}

class _PackageContext implements PackageContext {
  final Directory directory;
  final PackageConfig packageConfig;
  final List<PackageContext> children;
  _PackageContext(
      this.directory, this.packageConfig, List<PackageContext> children)
      : children = List<PackageContext>.unmodifiable(children);

  Map<Directory, PackageConfig> asMap() {
    var result = HashMap<Directory, PackageConfig>();
    void recurse(_PackageContext current) {
      result[current.directory] = current.packageConfig;
      for (var child in current.children) {
        recurse(child);
      }
    }

    recurse(this);
    return result;
  }

  PackageConfig operator [](Directory directory) {
    String path = directory.path;
    if (!path.startsWith(this.directory.path)) {
      throw ArgumentError("Not inside $path: $directory");
    }
    _PackageContext current = this;
    // The current path is know to agree with directory until deltaIndex.
    int deltaIndex = current.directory.path.length;
    List children = current.children;
    int i = 0;
    while (i < children.length) {
      _PackageContext child = children[i++];
      String childPath = child.directory.path;
      int childPathLength = childPath.length;
      if (_stringsAgree(path, childPath, deltaIndex, childPathLength)) {
        if (childPathLength == path.length) {
          return child.packageConfig;
        }
        if (path.startsWith(Platform.pathSeparator, childPathLength)) {
          deltaIndex = childPathLength + 1;
          current = child;
          children = current.children;
          i = 0;
        }
      }
    }
    return current.packageConfig;
  }

  static bool _stringsAgree(String a, String b, int start, int end) {
    if (a.length < end || b.length < end) return false;
    for (int i = start; i < end; i++) {
      if (a.codeUnitAt(i) != b.codeUnitAt(i)) return false;
    }
    return true;
  }
}
