# setup-builder

A GitHub Action that installs builder, the C++ build system, on a Windows, Linux or macOS runner. It downloads the release archive for the runner's host,
checks its SHA-256, puts `builder` on `PATH` for every later step, and keeps the packages builds
fetch between runs, so a project's dependencies are not downloaded again on every job.

## Usage

```yaml
jobs:
  build:
    strategy:
      matrix:
        os: [ windows-2022, ubuntu-24.04, macos-15 ]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v7
      - uses: praetorian555/setup-builder@v1
        with:
          version: 0.1.0
      - run: builder build --config=Release
      - run: builder test --config=Release --junit=reports
```

On Windows builder finds the Visual Studio the image installs, and the Ninja that comes with it.

On Linux the runner image has both GCC and clang on `PATH`, and builder does not choose between
them, so every command there names one. `--toolchain=gcc` or `--toolchain=clang` takes the
image's default `g++` or `clang++`; `--compiler=<driver>` takes any other, by name on `PATH` or by
path, such as a newer clang installed from apt.llvm.org, and needs no `--toolchain` beside it:

```yaml
  linux:
    runs-on: ubuntu-24.04
    strategy:
      matrix:
        compiler: [ g++-14, clang++-20 ]
    steps:
      - uses: actions/checkout@v7
      - if: matrix.compiler == 'clang++-20'
        run: wget -qO- https://apt.llvm.org/llvm.sh | sudo bash -s 20
      - uses: praetorian555/setup-builder@v1
        with:
          version: 0.1.0
      - run: builder build --config=Release --compiler=${{ matrix.compiler }}
      - run: builder test --config=Release --compiler=${{ matrix.compiler }}
```

The Linux release links its C++ runtime statically and needs glibc 2.38 or newer: `ubuntu-24.04`
and later runners.

On macOS builder finds Apple's clang and the macOS SDK through `xcrun`, from the Xcode the image
selects, so a command needs no `--toolchain`. The macOS release is built for Apple silicon and
needs macOS 15 or newer: `macos-15` and later runners.

## Inputs

| Input            | Default                          | Meaning |
|------------------|----------------------------------|---------|
| `version`        | required                         | The builder release to install, such as `0.1.0`. |
| `repository`     | `praetorian555/setup-builder`    | The repository whose `builder-<version>` releases hold the archives. |
| `sha256`         | empty                            | The archive's SHA-256 for this host. Empty checks the download against the `.sha256` file published next to it; set it to pin the archive yourself, which then needs a matrix value per host. |
| `cache-packages` | `true`                           | Keep the package cache between runs with `actions/cache`, keyed on the project's `builder.json` files. |
| `install-ninja`  | `true`                           | On Linux and macOS, install Ninja with apt or Homebrew when it is not on `PATH`. |

## Outputs

| Output      | Meaning |
|-------------|---------|
| `path`      | The directory that holds the builder executable, its rules SDK and its toolchain files. |
| `version`   | The version the installed builder reports. |
| `cache-dir` | The package cache directory, which the action also exports as `BUILDER_CACHE_DIR`. |

A `BUILDER_CACHE_DIR` already set in the job's environment is kept, and the cache step saves that
directory instead.

## What a release must look like

Builder's releases live in this repository, beside the action's own. They are tagged
`builder-<version>`, so they never collide with the action's `v<major>` tags, and are never marked
latest, so the latest release stays the action's. Each carries one archive per host and a checksum
file next to each:

```
builder-<version>-win32.zip
builder-<version>-win32.zip.sha256
builder-<version>-linux.tar.gz
builder-<version>-linux.tar.gz.sha256
builder-<version>-macos.tar.gz
builder-<version>-macos.tar.gz.sha256
```

Each archive holds a single top-level directory, `builder-<version>-<host>/`, with the executable,
`sdk/` and `toolchains/` directly inside it, the layout builder finds its own files in. A checksum
file is the output of `sha256sum <archive>`: the hash, then the file name. Builder's
`build-release.bat` and `build-release.sh` produce and publish exactly these, given this
repository: `build-release.bat praetorian555/setup-builder`. The macOS archive comes from
builder's `release-macos` workflow, which runs `build-release.sh` on a Mac.

## How it works

The action is a composite action: one bash step, which runs in Git Bash on Windows runners, and
`actions/cache`. The archive is extracted under the runner's tool cache, so a self-hosted runner
that keeps its tool cache installs a version once and reuses it. Paths written to `PATH`, to the
environment and to the outputs use the host's native spelling, so later steps work the same in
bash and in PowerShell.

## Testing

`.github/workflows/test.yml` checks the script with shellcheck and the workflows with actionlint on
every push. Installing a real release on each host runs only when started by hand from the Actions
tab with a version, since it needs a published release to download.

## License

MIT; see [LICENSE](LICENSE).
