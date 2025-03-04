# CouchDB Continuous Integration (CI) support repo

The main purpose of this repository is to provide scripts that:

* Install the necessary build-time dependencies for CouchDB on a number of platforms, either inside or outside of a container or VM
* Build Docker containers with those dependencies necessary to build binary JavaScript (SpiderMonkey 1.8.5) packages
* Build Docker containers with all dependencies necessary to build CouchDB, including Erlang and JavaScript

It intends to cover a range of both operating systems (Linux, macOS, BSD, Windows) and Erlang versions (17.x, 18.x, 19.x, etc.)

These images are used by [Apache Jenkins CI](https://ci-couchdb.apache.org/blue/organizations/jenkins/pipelines) to build CouchDB with every checkin to `main`, `3.x`, a release branch (*e.g.*, `2.3.0`), or an open Pull Request. CouchDB's CI build philosophy is to validate CouchDB against different Erlang versions with each commit to a Pull Request, and to validate CouchDB against different OSes and architectures on merged commits to `main`, `3.x`, and release branches. Where possible, Jenkins also auto-builds convenience binaries or packages. The eventual goal is that these auto-built binaries/packages/Docker images will be auto-pushed to our distribution repos for downstream consumption.

# Supported Configurations

See Docker Hub for the latest supported images:

- https://hub.docker.com/r/apache/couchdbci-debian/tags
- https://hub.docker.com/r/apache/couchdbci-ubuntu/tags
- https://hub.docker.com/r/apache/couchdbci-centos/tags

---

# Docker

For those OSes that support Docker, we run builds inside of Docker containers. These containers are built using the `build.sh` command at the root level.

## Authenticating to Docker Hub

1.  You need a Docker Cloud account with access to the `apache` organization to upload images. Ask the CouchDB PMC for assistance with this.
2. `export DOCKER_ID_USER="username"`
3. `docker login -u "username"` and enter your password.

## Building a "platform image"

The platform images include all of the build dependencies necessary to build and full test CouchDB on a given OS/version/architecture combination.

Build a platform image with:

```
./build.sh platform <distro>-<version>
```

## Overriding the Erlang, Elixir or Node version

We want to generate a `rebar` binary compatible with all versions of Erlang we support. If we do this on too new a version, older Erlangs won't recognize it. So we always keep an image around with that version.

On the other hand, some OSes won't run older Erlangs because of library changes, so you need to override that environment variable.

Just specify on the command line any of the `ERLANGVERSION`, `NODEVERSION`, or `ELIXIRVERSION` environment variables:

```
NODEVERSION=8 ELIXIRVERSION=v1.6.1 ERLANGVERSION=17.5.3 ./build.sh platform debian-jessie
```

The tool also recognizes a special `ERLANGVERSION=all` value for the `debian-buster`
platform. This builds the lowest, default, and highest versions of Erlang using
the [kerl](https://github.com/kerl/kerl) build system, and installs them to
`/usr/local/kerl` for activation before builds. This version is intended for use
in standard CI runs, such as for pull requests.

## Building images for other architectures

### Multi-arch images with Docker Buildx

We can use Docker's
[Buildx](https://docs.docker.com/buildx/working-with-buildx/) plugin to generate
multi-architecture container images with a single command invocation. Docker
Desktop ships with buildx support, but you'll need to create a new builder to
use it:

```
docker buildx create --name apache-couchdb --use
```

The `build.sh` script has `buildx-base` and `buildx-platform` targets that will
will build **and upload** a new multi-arch container image to the registry. For
example:

```
./build.sh buildx-platform debian-bullseye
```

The `$BUILDX_PLATFORMS` environment variable can be used to override the default
set of target platforms that will be supplied to the buildx builder.

### Cross-building with $CONTAINERARCH

Alternatively, we can build individual images for each architecture. This only works from an `x86_64` build host.

First, configure your machine with the correct dependencies to build multi-arch binaries:

```
docker run --privileged --rm tonistiigi/binfmt --install all
```

This is a one-time setup step. This docker container run will install the correct qemu static binaries necessary for running foreign architecture binaries on your host machine. It includes special magic to ensure `sudo` works correctly inside a container, too.

Then, override the `CONTAINERARCH` environment variable when starting `build.sh`:

```
CONTAINERARCH=arm64v8 ./build.sh platform debian-bullseye
```

## Publishing a container

If you built a single-architecture container image and did not supply `--push`
as a build arg to upload it automatically you can upload the image using

```
./build.sh platform-upload <distro>-<version>
```

---

# Useful things you can do

## Full `build.sh` options

```
./build.sh <command> [OPTIONS]

Recognized commands:
  clean <plat>              Removes all images for <plat>.
  clean-all                 Removes all images for all platforms.

  *buildx-base <plat>       Builds a multi-architecture base image.
  *buildx-platform <plat>   Builds a multi-architecture image with Erlang & JS support.

  base <plat>               Builds the image for <plat> without Erlang or JS support.
  base-all                  Builds all images without Erlang or JS support.
  *base-upload <plat>       Uploads the apache/couchdbci-{os} base images to Docker Hub.
  *base-upload-all          Uploads all the apache/couchdbci base images to Docker Hub.

  platform <plat>           Builds the image for <plat> with Erlang & JS support.
  platform-all              Builds all images with Erlang and JS support.
  *platform-upload <plat>   Uploads the apache/couchdbci-{os} images to Docker Hub.
  *platform-upload-all      Uploads all the apache/couchdbci images to Docker Hub.

  couch <plat>              Builds and tests CouchDB for <plat>.
  couch-all                 Builds and tests CouchDB on all platforms.

  Commands marked with * require appropriate Docker Hub credentials.
```

## Interactively working in a built container

After building the image as above:

```
docker run -it couchdbdev/<tag>
```

where `<tag>` is of the format `<distro>-<version>-<type>`, such as `debian-stretch-erlang-19.3.6`.

## Running the CouchDB build in a published container

```
./build.sh couch <distro>-<version>
```

## Building SpiderMonkey 1.8.5 convenience packages

This is only needed if a platform does not have a supported SpiderMonkey library. As of April 2021, this is no currently supported platform.

First, build the 'base' image with:

```
./build.sh base <distro>-<version>
```

After building the base image as above, head over to the [apache/couchdb-pkg](https://github.com/apache/couchdb-pkg) repository and follow the instructions there.

## Adding support for a new release/platform/architecture

1. Update the build scripts in the `bin/` directory to install the dependencies correctly on your new OS/version/platform. Push a PR with these changes.
1. Copy and customize an appropriate Dockerfile in the `dockerfiles` directory for your new OS.
1. If a supported SpiderMonkey library is not available on the target platform, build a base image using `./build.sh base <distro>-<version>`. Solve any problems with the build process here.
1. Using the [apache/couchdb-pkg](https://github.com/apache/couchdb-pkg) repository, validate you can build the JS package. Fix any problems in that repo that arise and raise a new PR. Open a new issue on that PR requesting that the JS packages be made available through the CouchDB repository/download infrastructure.
1. Build a full platform image with `./build.sh platform <distro>-<version>`. Solve any problems with the build process here.
1. Submit a PR against the [apache/couchdb](https://github.com/apache/couchdb) repository, adding the new platform to the top level `Jenkinsfile`. Ask if you need help.

---

# Other platforms

We are eager for contributions to enhance the build scripts to support setting up machines with the necessary build environment for:

* NetBSD
* OpenBSD
* macOS
* Windows x64 (see [apache/couchdb-glazier](https://github.com/apache/couchdb-glazier]) for the current approach)

as well as alternative architectures for the already supported image types (armhf, ppc64le, s390x, sparc, etc).

We know that Docker won't support some of these, but we should be able to at least expand the install scripts for all of these platforms.

# Background 

See: 
* this [thread](https://www.mail-archive.com/dev%40couchdb.apache.org/msg43591.html) on the couchdb-dev mailing list and
* this [ASF Infra ticket](https://issues.apache.org/jira/browse/INFRA-10126).
for the origins of this work.
