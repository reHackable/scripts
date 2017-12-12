#!/bin/bash

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Author        :  Patrick Pedersen <ctx.xda@gmail.com>,
#                  Part of the reHackable organization <https://github.com/reHackable>

# Description   : Host sided script that can push one or more documents to the reMarkable
#                 using the Web client

# Dependencies  : cURL

# Notations     : While this isn't directly related to this script, attempting to push epubs trough the web client
#                 may freeze the device

# Device address when connected to USB
ADDR=10.11.99.1

# Check for minimm argument count
if [ -z "$1" ];  then
  echo "No arguments provided"
  echo
  echo "Usage: repush.sh doc1 [doc2 ...]"

  exit -1
fi

# Check file validity before initiating push
for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "No such file: $f"
    exit -1
  elif ! file -F '|' "$f" | grep -qoP "(?<=\| )(PDF|EPUB)"; then
    echo "Unsupported file format: $f"
    echo "Only PDFs and EPUBs are supported"
    exit -1
  fi
done

# Transfer files
for f in "$@"; do
  stat=""
  attempt=""
  while [[ ! "$stat" && "$attempt" != "n" ]]; do
    if curl --connect-timeout 2 --silent --output /dev/null --form file=@"$f" http://"$ADDR"/upload; then
      stat=1
      echo "$f: Success"
    else
      stat=""
      echo "$f: Failed"
      read -r -p "Failed to push file! Retry? [Y/n]: " attempt
    fi
  done
done
