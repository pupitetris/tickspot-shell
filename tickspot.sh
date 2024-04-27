#!/bin/bash

# API docs:
# https://github.com/tick/tick-api

die() {
   echo $0: "$@" >&2
   exit 1
}

tickRequest() {
   local auth deb path

   if [ -z "$TOKEN" ]; then
      auth=(-u "$LOGIN:$PASSWD")
   else
      auth=(-H "Authorization: Token token=$TOKEN")
   fi

   if [ -z "$DEBUG" ]; then
      deb=(-s)
   else
      deb=()
   fi

   path=$1
   shift

   local headers=$TICKDIR/response-headers
   curl -D "$headers" -o "$TICKDIR"/response "${deb[@]}" "${auth[@]}" \
	-A "$USER_AGENT" "$BASE_URL$path" "$@"

   sed -i 's/\r//g' "$headers"
   REQUEST_STATUS=$(sed 's/^HTTP\/2 \([0-9]\+\).*/\1/;q' "$headers")
   echo >> "$TICKDIR"/response

   if [ -z "$DEBUG" ]; then
      cat
   else
      cat "$headers" >&2
      if [ "${REQUEST_STATUS:0:1}" = 2 ] &&
	    grep -qi '^content-type: application/json' "$headers"; then
	 jq
      else
	 cat
      fi |
	 tee /dev/stderr
   fi < "$TICKDIR"/response

   [ "${REQUEST_STATUS:0:1}" = 2 ] && return 0
   if [ -z "$DEBUG" -a "$REQUEST_STATUS" != 404 ]; then
      echo "$0: $path: (HTTP Status $REQUEST_STATUS)"
      cat "$TICKDIR"/response
      echo
   fi >&2
   return $REQUEST_STATUS
}

tickGet() {
   local path=$1
   shift

   local args=(-G)
   while [ $# != 0 ]; do
      args+=(--data-urlencode "$1")
      shift
   done

   tickRequest "$path" "${args[@]}"
}

tickPost() {
   local path=$1
   shift

   if [ -z "$DEBUG" ]; then
      cat
   else
      tee /dev/stderr
   fi |
      tee $TICKDIR/request-body |
      tickRequest "$path" -H "Content-Type: application/json; charset=utf-8" \
		  --data-binary @- "$@"
}

tickDelete() {
   local path=$1
   shift

   tickRequest "$path" -X DELETE 
}

getRoles() {
   tickGet /api/v2/roles.json | tee "$ROLESFILE"
}

getProjects() {
   tickGet /$SUBID/api/v2/projects.json | tee "$PROJFILE"
}

getTasks() {
   tickGet /$SUBID/api/v2/tasks.json | tee "$TASKSFILE"
}

getClients() {
   tickGet /$SUBID/api/v2/clients/all.json
}

getUsers() {
   tickGet /$SUBID/api/v2/users.json
}

renewToken() {
   TOKEN=
   [ -e "$ROLESFILE" ] || getRoles > /dev/null
   TOKEN=$(jq -r '.[0].api_token' "$ROLESFILE")
   SUBID=$(jq -r '.[0].subscription_id' "$ROLESFILE")

   [ -e "$PROJFILE" ] || getProjects > /dev/null
   DEF_PROJECT=$(jq -r '.[0].id' "$PROJFILE")

   [ -e "$TASKSFILE" ] || getTasks > /dev/null
   DEF_TASK=$(jq -r --arg p "$DEF_PROJECT" \
		 'map(select(.project_id == ($p | tonumber)))[0].id' "$TASKSFILE")

   {
      echo "TOKEN=$TOKEN"
      echo "SUBID=$SUBID"
      echo "DEF_PROJECT=$DEF_PROJECT"
      echo "DEF_TASK=$DEF_TASK"
   } > "$SESSFILE"
}

getDate() {
   date -d "$1" +%Y-%m-%d || die "Invalid date specifier '$1'"
}

getEntries() {
   local date=$(getDate "$1")
   tickGet /$SUBID/api/v2/entries.json start_date=$date end_date=$date
}

hasEntry() {
   getEntries "$1" |
      jq 'if type == "array" and length > 0 then 0 else 1 end' 2>/dev/null || echo 2
}

appendEntry() {
   jq -R -s --arg d "$1" --arg t "$TASK" \
      '{ date: $d, hours: 8, notes: sub("\n"; "\r\n"; "g"), task_id: $t | tonumber }' |
      tickPost /$SUBID/api/v2/entries.json 
}

createEntry() {
   [ $(hasEntry "$1") = 0 ] && return 1
   appendEntry "$@"
}

removeEntry() {
   local entry=$(getEntries "$1" | jq -r '.[0].id')
   [ -z "$entry" -o $entry = null ] && return 1
   tickDelete /$SUBID/api/v2/entries/$entry.json
}

[ -z "$DEBUG" ] || set -x

umask 0077

USER_AGENT='tickspot.sh (arturo.espinosa@epicor.com)'

[ -z "$RCFILE" ] && RCFILE=$HOME/.tickspot
[ -e "$RCFILE" ] && . "$RCFILE"

BASE_URL=https://$COMPANY.$DOMAIN
SESSFILE=$TICKDIR/session
ROLESFILE=$TICKDIR/roles.json
PROJFILE=$TICKDIR/projects.json
TASKSFILE=$TICKDIR/tasks.json

mkdir -p "$TICKDIR"

[ -e "$SESSFILE" ] && . "$SESSFILE"
[ -z "$TOKEN" ] && renewToken
[ -z "$PROJECT" ] && PROJECT=$DEF_PROJECT
[ -z "$TASK" ] && TASK=$DEF_TASK

cmd=$1
shift

case "$cmd" in
   '')
      die $'must provide a command:\n\tget-roles get-projects get-tasks get-clients get-users\n\tget-entries has-entry set-entry add-entry del-entry'
      ;;
   get-roles)
      TOKEN=
      getRoles
      exit $?
      ;;
   get-projects)
      getProjects
      exit $?
      ;;
   get-tasks)
      getTasks
      exit $?
      ;;
   get-clients)
      getClients
      exit $?
      ;;
   get-users)
      getUsers
      exit $?
      ;;
   get-entries)
      [ -z "$1" ] && die "get-entries requires a date (YYYY-MM-DD)"
      getEntries "$1"
      exit $?
      ;;
   has-entry)
      [ -z "$1" ] && die "has-entry requires a date (YYYY-MM-DD)"
      exit $(hasEntry "$1")
      ;;
   set-entry)
      [ -z "$1" ] && die "set-entry requires a date (YYYY-MM-DD)"
      [ -t 0 ] && die "set-entry requires notes text over stdin"
      createEntry "$1"
      exit $?
      ;;
   add-entry)
      [ -z "$1" ] && die "add-entry requires a date (YYYY-MM-DD)"
      [ -t 0 ] && die "add-entry requires notes text over stdin"
      appendEntry "$1"
      exit $?
      ;;
   del-entry)
      [ -z "$1" ] && die "del-entry requires a date (YYYY-MM-DD)"
      removeEntry "$1"
      exit $?
      ;;
   *)
      die "Unknown command $cmd"
      ;;
esac
