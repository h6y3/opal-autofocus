#!/bin/zsh
# Manual hardware check. Needs an Opal attached and a preview app (Photo Booth) open on it.
set -e
BIN=${BIN:-.build/release/opal-autofocus}
LABEL=com.opal-autofocus.agent
DOMAIN=gui/$(id -u)
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist

agent_was_loaded=false
if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    agent_was_loaded=true
fi

restore_agent() {
    if $agent_was_loaded && ! launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
        launchctl bootstrap "$DOMAIN" "$PLIST" && echo "(launchd agent restored)"
    fi
}
trap restore_agent EXIT INT TERM

ask() {
    read "answer?$1 [y/N] "
    [[ "$answer" == y* ]]
}

echo "== cold start"
if $agent_was_loaded; then
    launchctl bootout "$DOMAIN/$LABEL"
    echo "(launchd agent paused so it cannot fix the camera before you look)"
fi
echo "Unplug the Opal's own cable (not an upstream hub, which can keep it powered),"
echo "wait 5 seconds, plug it back in, and wait about 10 seconds."
read "?Press Return when the preview shows video again. "
if ! ask "Hold a hand about 10 cm from the lens. Is it blurry, i.e. autofocus parked?"; then
    echo "The camera is already focusing on a cold plug-in, so something else is enabling"
    echo "autofocus (for example Opal Composer's background helper). This test cannot tell"
    echo "whether opal-autofocus works until that is stopped."
    exit 1
fi
"$BIN" run
ask "Does the hand come into focus now?" || { echo "unexpected: run did not start autofocus on a cold camera"; exit 1 }
restore_agent

echo
echo "== status"
"$BIN" status

echo
echo "== disable: hold a hand about 10 cm from the lens and watch the preview"
"$BIN" disable
ask "Is the hand blurry, i.e. autofocus parked?" || { echo "unexpected: camera still focusing after disable"; exit 1 }

echo
echo "== enable"
"$BIN" enable
ask "Does the hand come into focus, and refocus when you move it?" || { echo "unexpected: autofocus did not resume after enable"; exit 1 }

echo
"$BIN" status
echo "smoke test passed"
