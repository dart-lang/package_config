// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:io";

import "package:package_config_x/package_config.dart";
import "package:test/test.dart";

import "src/util.dart";

main() {
  const emptyDir = <String, Object>{}; // To avoid repeating the types.
  var files = {
    "root": {
      ".packages": packagesFile,
      ".dart_tool": {
        "package_config.json": packageConfigJsonFile, // Used.
      },
      "foo": {
        ".packages": packagesFile, // Used.
        ".dart_tool": emptyDir,
      },
      "bar": {
        "packages": {
          // Package directory no longer supported.
          "foo": emptyDir,
          "bar": emptyDir,
          "baz": emptyDir,
        }
      },
      ".baz": {
        ".packages": packagesFile,
        ".dart_tool": {
          ".packages": packagesFile, // Ignored because inside .dart_tool
          "package_config.json": packageConfigJsonFile, // Used
        }
      },
    }
  };

  fileTest("basic", files, (Directory directory) {
    PackageConfig rootConfig = PackageConfig([]);
    PackageContext ctx =
        PackageContext.findAll(directory, root: rootConfig, onError: (dir, e) {
      fail("Error while reading context in $dir");
    });
    PackageConfig topConfig = ctx[directory];
    expect(topConfig, same(rootConfig));
    // A package_config.json found inside ./root/.dart_tool

    var rootDir = subdir(directory, "root");
    PackageConfig root = ctx[rootDir];
    //validatePackageConfig(root, rootDir, 2);

    var fooDir = subdir(rootDir, "foo");
    PackageConfig foo = ctx[fooDir];
    validatePackageConfig(foo, fooDir, 1);

    var barDir = subdir(rootDir, "bar");
    PackageConfig bar = ctx[barDir];
    expect(bar, same(root));

    // Not ignored.
    var bazDir = subdir(rootDir, ".baz");
    PackageConfig baz = ctx[bazDir];
    validatePackageConfig(baz, bazDir, 2);

    var bazToolDir = subdir(bazDir, ".dart_tool");
    PackageConfig bazTool = ctx[bazToolDir];
    expect(bazTool, same(baz));

    var map = ctx.asMap();
    expect(
        map.keys.map((dir) => dir.path),
        unorderedEquals(
            [directory.path, rootDir.path, fooDir.path, bazDir.path]));
    return null;
  });
}

void validatePackageConfig(
    PackageConfig config, Directory location, int version) {
  Uri locationUri = Uri.directory(location.path);
  expect(config, isNotNull);
  expect(config.version, version);
  expect({for (var p in config.packages) p.name}, {"foo", "bar", "baz"});
  expect(config.resolve(pkg("foo", "bar/baz")),
      equals(Uri.parse("file:///dart/foo/lib/bar/baz")));
  expect(config.resolve(pkg("bar", "baz/qux")),
      equals(Uri.parse("file:///dart/bar/lib/baz/qux")));
  expect(config.resolve(pkg("baz", "qux/foo")),
      equals(locationUri.resolve("lib/qux/foo")));
}

Uri pkg(String packageName, String packagePath) {
  var path;
  if (packagePath.startsWith('/')) {
    path = "$packageName$packagePath";
  } else {
    path = "$packageName/$packagePath";
  }
  return new Uri(scheme: "package", path: path);
}

const packagesFile = """
# A comment
foo:file:///dart/foo/lib/
bar:/dart/bar/lib/
baz:lib/
""";

const String packageConfigJsonFile = r"""
{
  "configVersion": 2,
  "packages": [
    {
      "name": "foo",
      "rootUri": "file:///dart/foo/",
      "packageUri": "lib/",
      "languageVersion": "2.5"
    },
    {
      "name": "bar",
      "rootUri": "/dart/bar/",
      "packageUri": "lib/",
      "languageVersion": "2.7"
    },
    {
      "name": "baz",
      "rootUri": "../",
      "packageUri": "lib/"
    }
  ]
}
""";
