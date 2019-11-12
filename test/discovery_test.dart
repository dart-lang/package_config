// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library package_config.discovery_test;

import "dart:async";
import "dart:io";
import "package:test/test.dart";
import "package:package_config/package_config.dart";
import "package:path/path.dart" as path;

const packagesFile = """
# A comment
foo:file:///dart/packages/foo/
bar:/dart/packages/bar/
baz:packages/baz/
""";

const packageConfigFile = """
{
  "configVersion": 2,
  "package": [
    {
      "name": "foo",
      "rootUri": "file:///dart/packages/foo/",
    },
    {
      "name": "bar",
      "rootUri": "/dart/packages/bar/",
    },
    {
      "name": "baz",
      "rootUri": "../packages/baz/",
    }
  ]
}
""";

void validatePackagesFile(PackageConfig resolver, Directory location) {
  expect(resolver, isNotNull);
  expect(resolver.resolve(pkg("foo", "bar/baz")),
      equals(Uri.parse("file:///dart/packages/foo/bar/baz")));
  expect(resolver.resolve(pkg("bar", "baz/qux")),
      equals(Uri.parse("file:///dart/packages/bar/baz/qux")));
  expect(resolver.resolve(pkg("baz", "qux/foo")),
      equals(Uri.directory(location.path).resolve("packages/baz/qux/foo")));
  expect([for (var p in resolver.packages) p.name],
      unorderedEquals(["foo", "bar", "baz"]));
}

main() {
  fileTest(".packages", {
    ".packages": packagesFile,
    "script.dart": "main(){}",
    "packages": {"shouldNotBeFound": {}}
  }, (Directory location) async {
    PackageConfig resolver;
    resolver = await findPackageConfig(location);
    expect(resolver.version, 1);  // Found .packages file.
    validatePackagesFile(resolver, location);
  });

  fileTest("package_config.json", {
    ".packages": "invalid .packages file",
    "script.dart": "main(){}",
    "packages": {"shouldNotBeFound": {}},
    ".dart_tool": {"package_config.json": packageConfigFile}
  }, (Directory location) async {
    PackageConfig resolver;
    resolver = await findPackageConfig(location);
    expect(resolver.version, 2);  // Found package_config.json file.
    validatePackagesFile(resolver, location);
  });

  fileTest("underscore packages", {
    "packages": {"_foo": {}}
  }, (Directory location) async {
    PackageConfig resolver = await findPackages(location);
    expect(resolver.resolve(pkg("_foo", "foo.dart")),
        equals(subDirectory(directory, "packages/_foo/foo.dart")));
  });

  fileTest(".packages recursive", {
    ".packages": packagesFile,
    "subdir": {"script.dart": "main(){}"}
  }, (Directory location) async {
    PackageConfig resolver;
    resolver = await findPackages(subDirectory(directory, "subdir/"));
    validatePackagesFile(resolver, location);
    resolver = await findPackages(subDirectory(directory, "subdir/script.dart"));
    validatePackagesFile(resolver, location);
    resolver = await findPackagesFromFile(subDirectory(directory, "subdir/"));
    validatePackagesFile(resolver, location);
    resolver =
        await findPackagesFromFile(subDirectory(directory, "subdir/script.dart"));
    validatePackagesFile(resolver, location);
  });

  httpTest(".packages not recursive", {
    ".packages": packagesFile,
    "subdir": {"script.dart": "main(){}"}
  }, (Directory location) async {
    PackageConfig resolver;
    var subdir = subDirectory(directory, "subdir/");
    resolver = await findPackages(subdir);
    validatePackagesDir(resolver, subdir);
    resolver = await findPackages(subdir.resolve("script.dart"));
    validatePackagesDir(resolver, subdir);
    resolver = await findPackagesFromNonFile(subdir);
    validatePackagesDir(resolver, subdir);
    resolver = await findPackagesFromNonFile(subdir.resolve("script.dart"));
    validatePackagesDir(resolver, subdir);
  });

  fileTest("no packages", {"script.dart": "main(){}"}, (Directory location) async {
    // A file: location with no .packages or packages returns
    // Packages.noPackages.
    PackageConfig resolver;
    resolver = await findPackages(location);
    expect(resolver, same(Packages.noPackages));
    resolver = await findPackages(subDirectory(directory, "script.dart"));
    expect(resolver, same(Packages.noPackages));
    resolver = findPackagesFromFile(location);
    expect(resolver, same(Packages.noPackages));
    resolver = findPackagesFromFile(subDirectory(directory, "script.dart"));
    expect(resolver, same(Packages.noPackages));
  });

  httpTest("no packages", {"script.dart": "main(){}"}, (Directory location) async {
    // A non-file: location with no .packages or packages/:
    // Assumes a packages dir exists, and resolves relative to that.
    PackageConfig resolver;
    resolver = await findPackages(location);
    validatePackagesDir(resolver, location);
    resolver = await findPackages(subDirectory(directory, "script.dart"));
    validatePackagesDir(resolver, location);
    resolver = await findPackagesFromNonFile(location);
    validatePackagesDir(resolver, location);
    resolver = await findPackagesFromNonFile(subDirectory(directory, "script.dart"));
    validatePackagesDir(resolver, location);
  });

  test(".packages w/ loader", () async {
    Directory location = Uri.parse("krutch://example.com/path/");
    Future<List<int>> loader(Uri file) async {
      if (file.path.endsWith(".packages")) {
        return packagesFile.codeUnits;
      }
      throw "not found";
    }

    // A non-file: location with no .packages or packages/:
    // Assumes a packages dir exists, and resolves relative to that.
    PackageConfig resolver;
    resolver = await findPackages(location, loader: loader);
    validatePackagesFile(resolver, location);
    resolver =
        await findPackages(subDirectory(directory, "script.dart"), loader: loader);
    validatePackagesFile(resolver, location);
    resolver = await findPackagesFromNonFile(location, loader: loader);
    validatePackagesFile(resolver, location);
    resolver = await findPackagesFromNonFile(subDirectory(directory, "script.dart"),
        loader: loader);
    validatePackagesFile(resolver, location);
  });

  test("no packages w/ loader", () async {
    Directory location = Uri.parse("krutch://example.com/path/");
    Future<List<int>> loader(Uri file) async {
      throw "not found";
    }

    // A non-file: location with no .packages or packages/:
    // Assumes a packages dir exists, and resolves relative to that.
    PackageConfig resolver;
    resolver = await findPackages(location, loader: loader);
    validatePackagesDir(resolver, location);
    resolver =
        await findPackages(subDirectory(directory, "script.dart"), loader: loader);
    validatePackagesDir(resolver, location);
    resolver = await findPackagesFromNonFile(location, loader: loader);
    validatePackagesDir(resolver, location);
    resolver = await findPackagesFromNonFile(subDirectory(directory, "script.dart"),
        loader: loader);
    validatePackagesDir(resolver, location);
  });

  fileTest("loadPackageConfig", {".packages": packagesFile},
      (Directory directory) async {
    File file = File(path.join(directory.path, ".packages"));
    PackageConfig resolver = await loadPackageConfig(file);
    validatePackagesFile(resolver, file);
  });

  fileTest(
      "loadPackageConfig non-default name", {"pheldagriff": packagesFile},
      (Directory directory) async {
    File file = File(path.join(directory.path, "pheldagriff"));
    PackageConfig resolver = await loadPackageConfig(file);
    validatePackagesFile(resolver, file);
  });

  fileTest("loadPackageConfig not found", {}, (Directory directory) async {
    File file = File(path.join(directory.path, ".packages"));
    expect(
        loadPackageConfig(file),
        throwsA(anyOf(new TypeMatcher<FileSystemException>(),
            new TypeMatcher<HttpException>())));
  });

  fileTest("loadPackageConfig syntax error", {".packages": "syntax error"},
      (Directory directory) async {
    File file = File(path.join(directory.path, ".packages"));
    expect(loadPackageConfig(file), throwsFormatException);
  });

  fileTest("getPackagesDir", {
    "packages": {"foo": {}, "bar": {}, "baz": {}}
  }, (Directory directory) async {
    Uri packages = Directory(path.join(directory.path, "packages");
    PackageConfig resolver = getPackagesDirectory(packages);
    Uri resolved = resolver.resolve(pkg("foo", "flip/flop"));
    expect(resolved, packages.resolve("foo/flip/flop"));
  });
}

/// Creates a directory structure from [description] and runs [fileTest].
///
/// Description is a map, each key is a file entry. If the value is a map,
/// it's a sub-directory, otherwise it's a file and the value is the content
/// as a string.
void fileTest(String name, Map<String, Object> description,
    Future<void> fileTest(Directory directory)) {
  group("file-test", () {
    Directory/*?*/ tempDir;
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync("file-test");
      _createFiles(tempDir, description);
    });
    tearDown(() {
      tempDir?.deleteSync(recursive: true);
    });
    test(name, () => fileTest(tempDir/*!*/));
  });
}

/// Creates a directory tree with files as specified by [description].
///
/// See [fileTest] for description.
void _createFiles(Directory target, Map<String, Object> description) {
  description.forEach((String name, Object content) {
    if (content is Map<String, Object>) {
      Directory subDir = subDirectory(target, name);
      subDir.createSync();
      _createFiles(subDir, content);
    } else {
      File file = new File(path.join(target.path, name));
      file.writeAsStringSync(content.toString(), flush: true);
    }
  });
}

String configFromPackages(List<List<String>> packages) => """
{
  "configVersion": 2,
  "packages": [
${packages.map((nu) => """
    {
      "name": "${nu[0]}",
      "rootUri": "${nu[1]}"
    }""").join(",\n")}
  ]
}
""";

// Creates a sub-directory of a given directory.
Directory subDirectory(Directory parent, String subPath) =>
    Directory(path.joinAll([parent.path, ... subPath.split("/")]));

// Creates a package: URI.
Uri pkg(String packageName, String packagePath) {
  var path =
      "$packageName${packagePath.startsWith('/') ? "" : "/"}$packagePath";
  return new Uri(scheme: "package", path: path);
}

