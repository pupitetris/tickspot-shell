#!/bin/bash

usage() {
   {
      echo "Usage: $0 from-date [to-date]"
      echo
      echo "Dates are in date -d format. Range is inclusive."
      echo
      echo "If to-date is not specified, only the from-date is processed."
   } >&2
   exit 1
}

die() {
   echo $0: "$@" >&2
   exit 1
}

getDate() {
   date -d "$*" +%Y-%m-%d || die "Invalid date specifier '$*'"
}

getRepoLog() {
   git -C $1 log --reverse --after=$2 --before=$3 --author=$EMAIL |
      sed -n '/^\(commit\|Author:\)/b;s/^Date: \+[^ ]\+ \+[^ ]\+[^ ]\+ \+[^ ]\+ \+\([^ ]\+\).*/\1/;p'
}

getLogs() {
   local log
   find . -name .git -type d -exec dirname '{}' \; |
      while read repo; do
	 log=$(getRepoLog $repo $1 $2)
	 if [ ${#log} -gt 0 ]; then
	    echo ${repo:2}:
	    echo
	    echo "$log"
	    echo
	 fi
      done
}

[ -z "$DEBUG" ] || set -x

[ -z "$1" ] && usage

from=$(getDate $1)
shift

if [ -z "$1" ]; then
   to=$from
else
   to=$(getDate $1)
fi
shift

[ -z "$EMAIL" ] && EMAIL=$(git config --global --get user.email)
[ -z "$EMAIL" ] && die "EMAIL var not set and could not determine author email"

curr=$(getDate $from -1 day)
while [ $curr != $to ]; do
   after=$curr
   curr=$(getDate $curr +1 day)
   before=$(getDate $after +1 day)

   logs=$(getLogs $after $before)
   if [ ${#logs} -gt 0 ] && ! tickspot.sh has-entry $curr; then
      echo -n "Uploading log for $curr... "
      tickspot.sh set-entry $curr <<< $logs >&2
      if [ $? = 0 ]; then echo success; else echo failure; fi
   fi
done
