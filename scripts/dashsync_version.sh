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

    pushd "../DashSync/"
	DASHSYNC_COMMIT=`git rev-parse HEAD`
	popd

	echo "$DASHSYNC_COMMIT" > DashSyncCurrentCommit
else
	echo "Updating DashSyncCurrentCommit using REMOTE DashSync dependency..."
	
	echo "$PODFILE_VERSION" > DashSyncCurrentCommit
fi
