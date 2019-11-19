// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Analyse a directory structure and find packages resolvers for each
/// sub-directory.
///
/// The resolvers are generally the same that would be found by using
/// the `discovery.dart` library on each sub-directory in turn,
/// but more efficiently and with some heuristics for directories that
/// wouldn't otherwise have a package resolution strategy, or that are
/// determined to be "package directories" themselves.
library package_config.discovery;

import "dart:collection" show HashMap;
import "dart:io" show Directory;

import "package_config.dart";
import "discovery.dart";

/// Associates a [Packages] package resolution strategy with a directory.
///
/// The package resolution applies to the directory and any sub-directory
/// that doesn't have its own overriding child [PackageContext].
abstract class PackageContext {
  /// The directory which introduced the [packages] resolver.
  Directory get directory;

  /// The [PackageConfiguration] that applies to the directory.
  ///
  /// Introduced either by a `.dart_tool/package_config.json` file or a
  /// `.packages` file in the [directory].
  PackageConfig get packageConfig;

  /// Child contexts that apply to sub-directories of [directory].
  List<PackageContext> get children;

  /// Look up the [PackageContext] that applies to a specific directory.
  ///
  /// The directory must be inside [directory].
  PackageContext operator [](Directory directory);

  /// A map from directory to package resolver.
  ///
  /// Has an entry for this package context and for each child context
  /// contained in this one.
  Map<Directory, PackageConfig> asMap();

  /// Analyze [directory] and sub-directories for package configurations.
  ///
  /// Returns a context mapping sub-directories to [Packages] objects.
  ///
  /// The analysis assumes that there are no package configuration files
  /// in a parent directory of `directory`.
  /// If there is, its corresponding [PackageConfig] object
  /// should be provided as [root].
  static PackageContext findAll(Directory directory,
      {PackageConfig root: PackageConfig.empty}) {
    if (!directory.existsSync()) {
      throw ArgumentError("Directory not found: $directory");
    }
    var contexts = <PackageContext>[];
    void findRoots(Directory directory, List<PackageContext> contexts) {
      PackageConfig /*?*/ packageConfig =
          findPackagConfigInDirectory(directory);
      List<PackageContext> subContexts = packageConfig == null ? contexts : [];
      for (var entry in directory.listSync()) {
        if (entry is Directory) {
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

  PackageContext operator [](Directory directory) {
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
      // TODO(lrn): Sort children and use binary search.
      _PackageContext child = children[i];
      String childPath = child.directory.path;
      if (_stringsAgree(path, childPath, deltaIndex, childPath.length)) {
        deltaIndex = childPath.length;
        if (deltaIndex == path.length) {
          return child;
        }
        current = child;
        children = current.children;
        i = 0;
        continue;
      }
      i++;
    }
    return current;
  }

  static bool _stringsAgree(String a, String b, int start, int end) {
    if (a.length < end || b.length < end) return false;
    for (int i = start; i < end; i++) {
      if (a.codeUnitAt(i) != b.codeUnitAt(i)) return false;
    }
    return true;
  }
}
