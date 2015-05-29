// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library package_config.packages_impl_vm;

import "packages_impl_html.dart";
import "dart:io" show Directory;
import "dart:collection" show UnmodifiableMapView;
import "package:path/path.dart" as path;

/// A [Packages] implementation based on a local directory.
class FilePackagesDirectoryPackages extends PackagesBase {
  final Directory _packageDir;
  FilePackagesDirectoryPackages(this._packageDir);

  Uri getBase(String packageName) =>
    new Uri.file(path.join(_packageDir.path, packageName, '.'));

  Iterable<String> _listPackageNames() {
    return _packageDir.listSync()
    .where((e) => e is Directory)
    .map((e) => path.basename(e.path));
  }

  Iterable<String> get packages {
    return _listPackageNames();
  }

  Map<String, Uri> asMap() {
    var result = <String, Uri>{};
    for (var packageName in _listPackageNames()) {
      result[packageName] = getBase(packageName);
    }
    return new UnmodifiableMapView<String, Uri>(result);
  }
}