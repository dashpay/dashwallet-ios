#!/bin/sh

RUBY_SCRIPT=$(cat <<'END_RUBY_SCRIPT'
data = YAML::load(STDIN.read)
puts data['CHECKOUT OPTIONS']['DashSync'][:'commit'] 
END_RUBY_SCRIPT
)

echo "Updating DashSyncCurrentCommit..."
cat Podfile.lock | ruby -ryaml -e "$RUBY_SCRIPT" > DashSyncCurrentCommit
