#!/bin/bash

# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# <http://www.apache.org/licenses/LICENSE-2.0>
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

SCRIPT_FOLDER=$( (cd "$(dirname "$0")" && pwd ))

# validate docker build
"$SCRIPT_FOLDER"/build.sh -t apigee-sackmesser

PATH="$PATH:$SCRIPT_FOLDER/bin"
APIGEE_X_TOKEN=$(gcloud auth print-access-token)
unset APIGEE_TOKEN

# Test Sackmesser Deploy

# Sackmesser X Deployment
BASE_PATH_X="/sackmesser-example-x"

sackmesser deploy \
  --googleapi \
  -d "$SCRIPT_FOLDER"/test/sackmesser-example \
  -n sackmesser-x-v0 \
  -b "$BASE_PATH_X" \
  -t "$APIGEE_X_TOKEN" \
  -o "$APIGEE_X_ORG" \
  -e "$APIGEE_X_ENV"

(cd "$SCRIPT_FOLDER"/test && \
  npm i --no-fund && \
  TEST_HOST="$APIGEE_X_HOSTNAME" \
  TEST_BASE_PATH="$BASE_PATH_X" \
  npm run test)

# Sackmesser Edge Deployment
BASE_PATH_EDGE="/sackmesser-example-edge"

sackmesser deploy \
  --apigeeapi \
  -d "$SCRIPT_FOLDER"/test/sackmesser-example \
  --name sackmesser-edge-v0 \
  --base-path "$BASE_PATH_EDGE" \
  --username "$APIGEE_USER" \
  --password "$APIGEE_PASS" \
  --organization "$APIGEE_ORG" \
  --environment "$APIGEE_ENV"

(cd "$SCRIPT_FOLDER"/test && \
  npm i --no-fund && \
  TEST_HOST="$APIGEE_ORG-$APIGEE_ENV.apigee.net" \
  TEST_BASE_PATH="$BASE_PATH_EDGE" \
  npm run test)

# Test Sackmesser Await
# (Test readiness of the deployed API proxy)
sackmesser await --googleapi -t "$APIGEE_X_TOKEN" proxy "sackmesser-x-v0"

docker run apigee-sackmesser await --apigeeapi --username "$APIGEE_USER" \
  --password "$APIGEE_PASS" --organization "$APIGEE_ORG" \
  --environment "$APIGEE_ENV" proxy "sackmesser-edge-v0"

# Test Sackmesser List
# (List all proxies to find the previously deployed API proxy)
sackmesser list --googleapi -t "$APIGEE_X_TOKEN" "organizations/$APIGEE_X_ORG/apis" | grep "sackmesser-x-v0"

docker run apigee-sackmesser list --apigeeapi -u "$APIGEE_USER" -p "$APIGEE_PASS" "organizations/$APIGEE_ORG/apis" | grep "sackmesser-edge-v0"

# Test Sackmesser Export
sackmesser export --googleapi -o "$APIGEE_X_ORG" -t "$APIGEE_X_TOKEN"
grep "$BASE_PATH_X" "$SCRIPT_PATH/$APIGEE_X_ORG/proxies/sackmesser-x-v0/apiproxy/proxies/default.xml"
grep "sackmesser-app" "$SCRIPT_PATH/$APIGEE_X_ORG/config/resources/edge/org/developerApps.json"
grep "janedoe@example.com" "$SCRIPT_PATH/$APIGEE_X_ORG/config/resources/edge/org/developers.json"
grep "SackMesserProduct1" "$SCRIPT_PATH/$APIGEE_X_ORG/config/resources/edge/org/apiProducts.json"
grep "SackMesserProduct2" "$SCRIPT_PATH/$APIGEE_X_ORG/config/resources/edge/org/apiProducts.json"

rm -rf "${SCRIPT_PATH:?}/$APIGEE_X_ORG"

sackmesser export --apigeeapi -u "$APIGEE_USER" -p "$APIGEE_PASS" -o "$APIGEE_ORG"
grep "$BASE_PATH_EDGE" "$SCRIPT_PATH/$APIGEE_ORG/proxies/sackmesser-edge-v0/apiproxy/proxies/default.xml"
grep "sackmesser-app" "$SCRIPT_PATH/$APIGEE_ORG/config/resources/edge/org/developerApps.json"
grep "janedoe@example.com" "$SCRIPT_PATH/$APIGEE_ORG/config/resources/edge/org/developers.json"
grep "SackMesserProduct1" "$SCRIPT_PATH/$APIGEE_ORG/config/resources/edge/org/apiProducts.json"
grep "SackMesserProduct2" "$SCRIPT_PATH/$APIGEE_ORG/config/resources/edge/org/apiProducts.json"

# Test Sackmesser Clean
sackmesser clean proxy sackmesser-edge-v0 --apigeeapi -u "$APIGEE_USER" -p "$APIGEE_PASS" -o "$APIGEE_ORG" --quiet
proxiesremaining=$(sackmesser list --apigeeapi -u "$APIGEE_USER" -p "$APIGEE_PASS" "organizations/$APIGEE_ORG/apis")
if [ "$(echo "$proxiesremaining" | jq 'map(select(. == "sackmesser-edge-v0"))')" != "[]" ];then
  echo "failed to delete"
  exit 1
fi

docker run apigee-sackmesser clean proxy sackmesser-x-v0 --googleapi -t "$APIGEE_X_TOKEN" -o "$APIGEE_X_ORG" --quiet

proxiesremaining=$(sackmesser list --googleapi -t "$APIGEE_X_TOKEN" "organizations/$APIGEE_X_ORG/apis")
if [ "$(echo "$proxiesremaining" | jq 'map(select(. == "sackmesser-x-v0"))')" != "[]" ];then
  echo "failed to delete proxy"
  exit 1
fi

# Delete Test App to test Re-Import Edge Export in X
testappId=$(sackmesser list --googleapi -t "$APIGEE_X_TOKEN" "organizations/$APIGEE_X_ORG/developers/janedoe@example.com/apps/sackmesser-app" | jq -r '.appId')

sackmesser clean app "$testappId" --googleapi -t "$APIGEE_X_TOKEN" -o "$APIGEE_X_ORG" --quiet
sackmesser clean developer "janedoe@example.com" --googleapi -t "$APIGEE_X_TOKEN" -o "$APIGEE_X_ORG" --quiet
sackmesser clean product "SackMesserProduct1" --googleapi -t "$APIGEE_X_TOKEN" -o "$APIGEE_X_ORG" --quiet
sackmesser clean product "SackMesserProduct2" --googleapi -t "$APIGEE_X_TOKEN" -o "$APIGEE_X_ORG" --quiet

sackmesser deploy \
  --googleapi \
  -d "$SCRIPT_FOLDER/$APIGEE_ORG/config" \
  -t "$APIGEE_X_TOKEN" \
  -o "$APIGEE_X_ORG" \
  -e "$APIGEE_X_ENV"

sackmesser deploy \
  --googleapi \
  -d "$SCRIPT_FOLDER/$APIGEE_ORG/proxies/sackmesser-edge-v0" \
  -t "$APIGEE_X_TOKEN" \
  -o "$APIGEE_X_ORG" \
  -e "$APIGEE_X_ENV"

sackmesser list --googleapi -t "$APIGEE_X_TOKEN" "organizations/$APIGEE_X_ORG/apis" | grep "sackmesser-edge-v0"
sackmesser list --googleapi -t "$APIGEE_X_TOKEN" "organizations/$APIGEE_X_ORG/developers" | grep "janedoe@example.com"
sackmesser list --googleapi -t "$APIGEE_X_TOKEN" "organizations/$APIGEE_X_ORG/developers/janedoe@example.com/apps" | grep "sackmesser-app"
sackmesser list --googleapi -t "$APIGEE_X_TOKEN" "organizations/$APIGEE_X_ORG/apiproducts" | grep "SackMesserProduct1"
sackmesser list --googleapi -t "$APIGEE_X_TOKEN" "organizations/$APIGEE_X_ORG/apiproducts" | grep "SackMesserProduct2"

rm -rd "${SCRIPT_FOLDER:?}/$APIGEE_ORG"
