#!/bin/sh
# Syntax-check every mod script with a Lua 5.4 interpreter (UE4SS 3.x uses Lua 5.4).
# Usage: LUA=/path/to/lua tools/check_lua.sh
LUA="${LUA:-lua5.4}"
status=0
for f in "$(dirname "$0")"/../mod/CoopProbe/Scripts/*.lua; do
  "$LUA" -e "local f, e = loadfile('$f'); if not f then print('FAIL ' .. e); os.exit(1) end; print('ok   $f')" || status=1
done
exit $status
