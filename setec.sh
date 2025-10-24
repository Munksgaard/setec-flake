#!/usr/bin/env bash

set -eEuo pipefail

SERVER=https://setec-test-2.cod-micro.ts.net

./result/bin/setec -s $SERVER "$@"
