#!/bin/zsh
# Manual hardware check. Needs an Opal attached and a preview app (Photo Booth) open on it.
set -e
BIN=${BIN:-.build/release/opal-autofocus}

echo "== status"
"$BIN" status

echo
echo "== disable: hold a hand about 10 cm from the lens and watch the preview"
"$BIN" disable
read "answer?Is the hand blurry, i.e. autofocus parked? [y/N] "
[[ "$answer" == y* ]] || { echo "unexpected: camera still focusing after disable"; exit 1 }

echo
echo "== enable"
"$BIN" enable
read "answer?Does the hand come into focus, and refocus when you move it? [y/N] "
[[ "$answer" == y* ]] || { echo "unexpected: autofocus did not resume after enable"; exit 1 }

echo
"$BIN" status
echo "smoke test passed"
