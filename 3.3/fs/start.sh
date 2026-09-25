#!/bin/sh
#
# Copyright 2017 The Kubernetes Authors. All rights reserved.
#
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

set -e

if [ $# -gt 0 ] && [ "$(echo $1 | cut -b1-2)" != "--" ]; then
    # Probably a `docker run -ti`, so exec and exit
    exec "$@"
fi

export EXTRA_OPTIONS="$@"

# Any non-empty USE_SIGUSR1 makes haproxy drain with SIGUSR1 on shutdown. That
# is haproxy's stop-signal, which gopherd cannot template, so it selects the
# config the Dockerfile derived for it. An explicit GOPHERD_CONFIG wins.
if [ -n "${USE_SIGUSR1}" ] && [ -z "${GOPHERD_CONFIG}" ]; then
    export GOPHERD_CONFIG=/etc/gopherd/gopherd-sigusr1.yml
fi

exec /usr/local/bin/gopherd
