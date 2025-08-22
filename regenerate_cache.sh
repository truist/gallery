#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
	echo "args: <domain name>" >&2
	exit 1
fi

domain="$1"

wget -nv -nd -r -l inf -np --spider -e robots=off --no-hsts --no-cookies "--domains=$domain" "http://$domain" 2> >(grep -v '^unlink: No such file or directory$')

