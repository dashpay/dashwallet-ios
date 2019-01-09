#!/usr/bin/env bash

pushd "../DashSync/"
DASHSYNC_COMMIT=`git rev-parse HEAD`
popd
echo "$DASHSYNC_COMMIT" > DashSyncCurrentCommit
