# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG erlang
FROM erlang:${erlang}

ARG erlang
ARG node=17
ARG fdb=6.3.23

# Create Jenkins user and group
RUN groupadd --gid 910 jenkins; \
  useradd --uid 910 --gid jenkins --create-home jenkins

# Jenkins builds in /usr/src/couchdb
RUN mkdir -p /usr/src/couchdb; \
  chown -R jenkins:jenkins /usr/src/couchdb

# Install all dependencies
COPY install-dependencies.sh /tmp/
RUN ERLANG_VSN=$erlang NODE_VSN=$node FDB_VSN=$fdb /tmp/install-dependencies.sh

# Allow Jenkins to sudo
RUN echo "jenkins ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/jenkins

USER jenkins

# overwrite this with 'CMD []' in a dependent Dockerfile
CMD ["/bin/bash"]

