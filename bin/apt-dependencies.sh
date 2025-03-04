#!/usr/bin/env bash

# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing,
#   software distributed under the License is distributed on an
#   "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#   KIND, either express or implied.  See the License for the
#   specific language governing permissions and limitations
#   under the License.

# This shell script installs all OS package dependencies for Apache
# CouchDB 2.x for deb-based systems.
#
# While these scripts are primarily written to support building CI
# Docker images, they can be used on any workstation to install a
# suitable build environment.

# stop on error
set -e

# TODO: support Mint, Devuan, etc.

# Check if running as root
if [ ${EUID} -ne 0 ]; then
  echo "Sorry, this script must be run as root."
  echo "Try: sudo $0 $*"
  exit 1
fi

# install lsb-release
apt-get update && apt-get install --no-install-recommends -y lsb-release

SCRIPTPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. ${SCRIPTPATH}/detect-arch.sh >/dev/null
. ${SCRIPTPATH}/detect-os.sh >/dev/null
debians='(jessie|stretch|buster)'
ubuntus='(bionic|focal)'
echo "Detected Ubuntu/Debian version: ${VERSION_CODENAME}   arch: ${ARCH}"

# bionic Docker image seems to be missing /etc/timezone...
if [ ! -f /etc/timezone ]; then
  rm -f /etc/localtime
  ln -snf /usr/share/zoneinfo/Etc/UTC /etc/localtime
  echo "Etc/UTC" > /etc/timezone
  chmod 0644 /etc/timezone
  apt-get install --no-install-recommends -y tzdata
  export TZ=Etc/UTC
fi

# Upgrade all packages
apt-get --no-install-recommends -y dist-upgrade

# install build-time dependencies

# build deps, doc build deps, pkg building, then userland helper stuff
apt-get install --no-install-recommends -y apt-transport-https curl git pkg-config \
    python3 libpython3-dev python3-setuptools python3-pip python3-venv \
    sudo wget zip unzip \
    build-essential ca-certificates libcurl4-openssl-dev \
    libicu-dev libnspr4-dev \
    help2man python3-sphinx \
    curl debhelper devscripts dh-exec dh-python equivs \
    dialog equivs lintian libwww-perl quilt \
    reprepro rsync \
    vim-tiny screen procps dirmngr ssh-client


# createrepo_c or createrepo, depending on packaging support
if [ ${VERSION_CODENAME} == "bullseye" ]; then
  apt-get install --no-install-recommends -y createrepo-c || true
else
  # python 2 based; gone from focal / bullseye. look for createrepo_c eventually
  # hopefully via: https://github.com/rpm-software-management/createrepo_c/issues/145
  apt-get install --no-install-recommends -y createrepo || true
fi

# Node.js
if [ "${ARCH}" == "ppc64le" -o "${ARCH}" == "s390x" ]; then
  apt-get install --no-install-recommends -y nodejs npm
else
  wget https://deb.nodesource.com/setup_${NODEVERSION}.x
  if /bin/bash setup_${NODEVERSION}.x; then
    apt-get install --no-install-recommends -y nodejs
  fi
  rm setup_${NODEVERSION}.x
fi
# maybe install node from scratch if pkg install failed...
if [ -z "$(which node)" ]; then
  apt-get purge -y nodejs || true
  # extracting the right version to dl is a pain :(
  if [ ${ARCH} == "x86_64" ]; then
    NODEARCH=x64
  else
    NODEARCH=${ARCH}
  fi
  node_filename="$(curl -s https://nodejs.org/dist/latest-v${NODEVERSION}.x/SHASUMS256.txt | grep linux-${NODEARCH}.tar.gz | cut -d ' ' -f 3)"
  wget https://nodejs.org/dist/latest-v${NODEVERSION}.x/${node_filename}
  tar --directory=/usr --strip-components=1 -xzf ${node_filename}
  rm ${node_filename}
  # fake a package install
  cat << EOF > nodejs-control
Section: misc
Priority: optional
Standards-Version: 3.9.2
Package: nodejs
Provides: nodejs
Version: ${NODEVERSION}.99.99
Description: Fake nodejs package to appease package builder
EOF
  equivs-build nodejs-control
  apt-get install --no-install-recommends -y ./nodejs*.deb
  rm nodejs-control nodejs*deb
fi
# update to latest npm
npm install npm@latest -g --unsafe-perm

# rest of python dependencies
pip3 --default-timeout=10000 install --upgrade sphinx_rtd_theme nose requests hypothesis==3.79.0

# relaxed lintian rules for CouchDB
mkdir -p /usr/share/lintian/profiles/couchdb
chmod 0755 /usr/share/lintian/profiles/couchdb
if [[ ${VERSION_CODENAME} =~ ${debians} ]]; then
  cp ${SCRIPTPATH}/../files/debian.profile /usr/share/lintian/profiles/couchdb/main.profile
  if [ ${VERSION_CODENAME} == "jessie" ]; then
    # remove unknown lintian rule privacy-breach-uses-embedded-file
    sed -i -e 's/, privacy-breach-uses-embedded-file//' /usr/share/lintian/profiles/couchdb/main.profile
    # add rule to suppress python-script-but-no-python-dep
    sed -i -e 's/Disable-Tags: /Disable-Tags: python-script-but-no-python-dep, /' /usr/share/lintian/profiles/couchdb/main.profile
  fi
elif [[ ${VERSION_CODENAME} =~ ${ubuntus} ]]; then
  cp ${SCRIPTPATH}/../files/ubuntu.profile /usr/share/lintian/profiles/couchdb/main.profile
else
  echo "Unrecognized Debian-like release: ${VERSION_CODENAME}! Skipping lintian work."
fi

MAINPROFILE=/usr/share/lintian/profiles/couchdb/main.profile
if [ -e ${MAINPROFILE} ]; then
    chmod 0644 ${MAINPROFILE}
fi

# js packages, as long as we're not told to skip them
if [ "$1" != "nojs" ]; then
  # older releases don't have libmozjs60+, and we provide 1.8.5
  if [ "${VERSION_CODENAME}" != "focal" -a "${VERSION_CODENAME}" != "bullseye" -a "${ARCH}" != "s390x" ]; then
    curl https://couchdb.apache.org/repo/keys.asc | gpg --dearmor | tee /usr/share/keyrings/couchdb-archive-keyring.gpg >/dev/null 2>&1
    source /etc/os-release
    echo "deb [signed-by=/usr/share/keyrings/couchdb-archive-keyring.gpg] https://apache.jfrog.io/artifactory/couchdb-deb/ ${VERSION_CODENAME} main" \
    | tee /etc/apt/sources.list.d/couchdb.list >/dev/null
    apt-get update
    apt-get install --no-install-recommends -y couch-libmozjs185-dev
  fi
  # newer releases have newer libmozjs
  if [ "${VERSION_CODENAME}" == "buster" ]; then
    apt-get install --no-install-recommends -y libmozjs-60-dev
  fi
  if [ "${VERSION_CODENAME}" == "focal" ]; then
    apt-get install --no-install-recommends -y libmozjs-68-dev
  fi
  if [ "${VERSION_CODENAME}" == "bullseye" ]; then
    apt-get install --no-install-recommends -y libmozjs-78-dev
  fi
else
  # install js build-time dependencies only
  # we can't add the CouchDB repo here because the plat may not exist yet
  apt-get install --no-install-recommends -y libffi-dev pkg-kde-tools autotools-dev
fi

# Erlang is installed by apt-erlang.sh

# FoundationDB - but only for amd64 right now!!!!
if [ "${ARCH}" == "x86_64" ]; then
  wget https://github.com/apple/foundationdb/releases/download/6.3.23/foundationdb-clients_6.3.23-1_amd64.deb
  wget https://github.com/apple/foundationdb/releases/download/6.3.23/foundationdb-server_6.3.23-1_amd64.deb
  dpkg -i ./foundationdb*deb
  pkill -f fdb || true
  pkill -f foundation || true
  rm -rf ./foundationdb*deb
fi

# clean up
apt-get clean
