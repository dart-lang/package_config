// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'errors.dart';
import "package_config.dart";
import "util.dart";

export "package_config.dart";

class SimplePackageConfig implements PackageConfig {
  final int version;
  final Map<String, Package> _packages;
  final PackageTree _packageTree;
  final dynamic extraData;

  SimplePackageConfig(int version, Iterable<Package> packages,
      [dynamic extraData])
      : this._(_validateVersion(version), packages,
            [...packages]..sort(_compareRoot), extraData);

  /// Expects a
  SimplePackageConfig._(this.version, Iterable<Package> originalPackages,
      List<Package> packages, this.extraData)
      : _packageTree = _validatePackages(originalPackages, packages),
        _packages = {for (var p in packages) p.name: p};

  /// Used for sorting packages by root path.
  static int _compareRoot(Package p1, Package p2) =>
      p1.root.toString().compareTo(p2.root.toString());

  /// Creates empty configuration.
  ///
  /// The empty configuration can be used in cases where no configuration is
  /// found, but code expects a non-null configuration.
  const SimplePackageConfig.empty()
      : version = 1,
        _packageTree = const EmptyPackageTree(),
        _packages = const <String, Package>{},
        extraData = null;

  static int _validateVersion(int version) {
    if (version < 0 || version > PackageConfig.maxVersion) {
      throw PackageConfigArgumentError(version, "version",
          "Must be in the range 1 to ${PackageConfig.maxVersion}");
    }
    return version;
  }

  static PackageTree _validatePackages(
      Iterable<Package> originalPackages, List<Package> packages) {
    // Assumes packages are sorted.
    Map<String, Package> result = {};
    var tree = MutablePackageTree();
    SimplePackage package;
    for (var originalPackage in packages) {
      if (originalPackage is! SimplePackage) {
        // SimplePackage validates these properties.
        try {
          package = SimplePackage(
              originalPackage.name,
              originalPackage.root,
              originalPackage.packageUriRoot,
              originalPackage.languageVersion,
              originalPackage.extraData);
        } catch (e) {
          throw PackageConfigArgumentError(
              packages, "packages", "Package ${package.name}: ${e.message}");
        }
      } else {
        package = originalPackage;
      }
      var name = package.name;
      if (result.containsKey(name)) {
        throw PackageConfigArgumentError(
            name, "packages", "Duplicate package name");
      }
      result[name] = package;
      var existingPackage = tree.add(0, package);
      if (existingPackage != null) {
        // There is a conflict with an existing package.
        // Either they have the same root.
        if (existingPackage.root == package.root) {
          throw PackageConfigArgumentError(
              originalPackages,
              "packages",
              "Packages ${package.name} and ${existingPackage.name}"
                  "have the same root directory: ${package.root}.\n");
        }
        // Or package is inside the package URI root of the existing package.
        throw PackageConfigArgumentError(
            originalPackages,
            "packages",
            "Package ${package.name} is inside the package URI root of "
                "package ${existingPackage.name}.\n"
                "${existingPackage.name} URI root: "
                "${existingPackage.packageUriRoot}\n"
                "${package.name} root: ${package.root}\n");
      }
    }
    return tree;
  }

  Iterable<Package> get packages => _packages.values;

  Package /*?*/ operator [](String packageName) => _packages[packageName];

  /// Provides the associated package for a specific [file] (or directory).
  ///
  /// Returns a [Package] which contains the [file]'s path.
  /// That is, the [Package.rootUri] directory is a parent directory
  /// of the [file]'s location.
  /// Returns `null` if the file does not belong to any package.
  Package /*?*/ packageOf(Uri file) => _packageTree.packageOf(file);

  Uri /*?*/ resolve(Uri packageUri) {
    String packageName = checkValidPackageUri(packageUri, "packageUri");
    return _packages[packageName]?.packageUriRoot?.resolveUri(
        Uri(path: packageUri.path.substring(packageName.length + 1)));
  }

  Uri /*?*/ toPackageUri(Uri nonPackageUri) {
    if (nonPackageUri.isScheme("package")) {
      throw PackageConfigArgumentError(
          nonPackageUri, "nonPackageUri", "Must not be a package URI");
    }
    if (nonPackageUri.hasQuery || nonPackageUri.hasFragment) {
      throw PackageConfigArgumentError(nonPackageUri, "nonPackageUri",
          "Must not have query or fragment part");
    }
    // Find package that file belongs to.
    var package = _packageTree.packageOf(nonPackageUri);
    if (package == null) return null;
    // Check if it is inside the package URI root.
    var path = nonPackageUri.toString();
    var root = package.packageUriRoot.toString();
    if (_beginsWith(package.root.toString().length, root, path)) {
      var rest = path.substring(root.length);
      return Uri(scheme: "package", path: "${package.name}/$rest");
    }
    return null;
  }
}

/// Configuration data for a single package.
class SimplePackage implements Package {
  final String name;
  final Uri root;
  final Uri packageUriRoot;
  final String /*?*/ languageVersion;
  final dynamic extraData;

  SimplePackage._(this.name, this.root, this.packageUriRoot,
      this.languageVersion, this.extraData);

  /// Creates a [SimplePackage] with the provided content.
  ///
  /// The provided arguments must be valid.
  factory SimplePackage(String name, Uri root, Uri packageUriRoot,
      String /*?*/ languageVersion, dynamic extraData) {
    _validatePackageData(name, root, packageUriRoot, languageVersion);
    return SimplePackage._(
        name, root, packageUriRoot, languageVersion, extraData);
  }
}

void _validatePackageData(
    String name, Uri root, Uri packageUriRoot, String /*?*/ languageVersion) {
  if (!isValidPackageName(name)) {
    throw PackageConfigArgumentError(name, "name", "Not a valid package name");
  }
  if (!isAbsoluteDirectoryUri(root)) {
    throw PackageConfigArgumentError(
        "$root",
        "root",
        "Not an absolute URI with no query or fragment "
            "with a path ending in /");
  }
  if (!isAbsoluteDirectoryUri(packageUriRoot)) {
    throw PackageConfigArgumentError(
        packageUriRoot,
        "packageUriRoot",
        "Not an absolute URI with no query or fragment "
            "with a path ending in /");
  }
  if (!isUriPrefix(root, packageUriRoot)) {
    throw PackageConfigArgumentError(packageUriRoot, "packageUriRoot",
        "The package URI root is not below the package root");
  }
  if (languageVersion != null &&
      checkValidVersionNumber(languageVersion) >= 0) {
    throw PackageConfigArgumentError(
        languageVersion, "languageVersion", "Invalid language version format");
  }
}

abstract class PackageTree {
  SimplePackage /*?*/ packageOf(Uri file);
}

/// Packages of a package configuration ordered by root path.
///
/// A package is said to be inside another package if the root path URI of
/// the latter is a prefix of the root path URI of the former.
/// No two packages of a package may have the same root path, so this
/// path prefix ordering defines a tree-like partial ordering on packages
/// of a configuration.
///
/// The package tree contains an ordered mapping of unrelated packages
/// (represented by their name) to their immediately nested packages' names.
class MutablePackageTree implements PackageTree {
  final List<SimplePackage> packages = [];
  Map<String, MutablePackageTree /*?*/ > /*?*/ _packageChildren;

  /// Tries to (add) `package` to the tree.
  ///
  /// If another package is found with the *same* path, adding fails
  /// and that package is returned. Returns `null` on success.
  SimplePackage /*?*/ add(int start, SimplePackage package) {
    var path = package.root.toString();
    for (var childPackage in packages) {
      var childPath = childPackage.root.toString();
      assert(childPath.length > start);
      assert(path.startsWith(childPath.substring(0, start)));
      if (_beginsWith(start, childPath, path)) {
        var childPathLength = childPath.length;
        if (path.length == childPathLength) return childPackage;
        var childPackageRoot = childPackage.packageUriRoot.toString();
        if (_beginsWith(childPathLength, childPackageRoot, path)) {
          // Conflict with package root of [childPackage].
          return childPackage;
        }
        return _treeOf(childPackage).add(childPathLength, package);
      }
    }
    packages.add(package);
    return null;
  }

  SimplePackage /*?*/ packageOf(Uri file) {
    return findPackageOf(0, file.toString());
  }

  /// Finds package containing [path] in this tree.
  ///
  /// Returns `null` if no such package is found.
  ///
  /// Assumes the first [start] characters of path agrees with all
  /// the packages at this level of the tree.
  SimplePackage /*?*/ findPackageOf(int start, String path) {
    for (var childPackage in packages) {
      var childPath = childPackage.root.toString();
      if (_beginsWith(start, childPath, path)) {
        // The [package] is inside [childPackage].
        var childPathLength = childPath.length;
        if (path.length == childPathLength) return childPackage;
        var uriRoot = childPackage.packageUriRoot.toString();
        // Is [package] is inside the URI root of [childPackage].
        if (uriRoot.length == childPathLength ||
            _beginsWith(childPathLength, uriRoot, path)) {
          return childPackage;
        }
        // Otherwise add [package] as child of [childPackage].
        // TODO(lrn): When NNBD comes, convert to:
        // return _packageChildren?[childPackage.name]
        //     ?.packageOf(childPathLength, path) ?? childPackage;
        if (_packageChildren == null) return childPackage;
        var childTree = _packageChildren[childPackage.name];
        if (childTree == null) return childPackage;
        return childTree.findPackageOf(childPathLength, path) ?? childPackage;
      }
    }
    return null;
  }

  /// Returns the [PackageTree] of the children of [package].
  ///
  /// Ensures that the object is allocated if necessary.
  MutablePackageTree _treeOf(SimplePackage package) =>
      (_packageChildren ??= {})[package.name] ??= MutablePackageTree();
}

class EmptyPackageTree implements PackageTree {
  const EmptyPackageTree();

  SimplePackage packageOf(Uri file) => null;
}

/// Checks whether [longerPath] begins with [parentPath].
///
/// Skips checking the [start] first characters which are assumed to
/// already have been matched.
bool _beginsWith(int start, String parentPath, String longerPath) {
  if (longerPath.length < parentPath.length) return false;
  for (int i = start; i < parentPath.length; i++) {
    if (longerPath.codeUnitAt(i) != parentPath.codeUnitAt(i)) return false;
  }
  return true;
}
