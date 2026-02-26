#!/bin/sh

RUBY_SCRIPT=$(cat <<'END_RUBY_SCRIPT'
def ignore_exception
   begin
     yield  
   rescue Exception
   end
end

ignore_exception {
	data = YAML::load(STDIN.read)
	puts data['CHECKOUT OPTIONS']['DashSync'][:'commit'] 
}
END_RUBY_SCRIPT
)

PODFILE_VERSION=`cat Podfile.lock | ruby -ryaml -e "$RUBY_SCRIPT"`

if [ -z "${PODFILE_VERSION}" ]; then
	echo "Updating DashSyncCurrentCommit using LOCAL DashSync dependency..."

    # Prefer the documented external folder structure:
    #   ../DashSync/
    # but also support this monorepo layout where DashSync lives at:
    #   ../dashsync-iOS/
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    DASHSYNC_DIR="${SCRIPT_DIR}/../DashSync"
    if [ ! -f "${DASHSYNC_DIR}/DashSync.podspec" ] && [ -f "${SCRIPT_DIR}/../dashsync-iOS/DashSync.podspec" ]; then
      DASHSYNC_DIR="${SCRIPT_DIR}/../dashsync-iOS"
    fi

    if [ -d "${DASHSYNC_DIR}" ]; then
      pushd "${DASHSYNC_DIR}" >/dev/null
      DASHSYNC_COMMIT="$(git rev-parse HEAD 2>/dev/null || true)"
      popd >/dev/null
    fi

    if [ -z "${DASHSYNC_COMMIT}" ]; then
      echo "Warning: could not determine DashSync git commit (missing repo or not a git checkout)."
    else
      echo "$DASHSYNC_COMMIT" > DashSyncCurrentCommit
    fi

else
	echo "Updating DashSyncCurrentCommit using REMOTE DashSync dependency..."
	
	echo "$PODFILE_VERSION" > DashSyncCurrentCommit
fi
