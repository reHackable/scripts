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

# Dependencies  : cURL, ssh, nc

# Notations     : While this isn't directly related to this script, attempting to push epubs trough the web client
#                 may freeze the device

# Local
WEBUI_ADDRESS="10.11.99.1:80"

# Remote
PORT=9000 # Deault port to which the webui is tunneled to

function usage {
  echo "Usage: repush.sh [-d] [-r ip] [-p port] doc1 [doc2 ...]"
  echo
  echo "Options:"
  echo -e "-d\t\t\tDelete file after successful push"
  echo -e "-r\t\t\tPush remotely via ssh tunneling"
  echo -e "-p\t\t\tIf -r has been given, this option defines port to which the webui will be tunneled (default 9000)"
}

# Evaluate Options/Parameters
while getopts ":hdr:p:" remote; do
  case "$remote" in
    r) # Push Remotely
      SSH_ADDRESS="$OPTARG"
      ;;

    p) # Tunneling Port defined
      PORT="$OPTARG"
      ;;

    d) # Delete file after successful push
      DELETE_ON_PUSH=1
      ;;

    h) # Usage help
      usage
      exit 1
      ;;

    ?) # Unkown Option
      echo "Invalid option or missing arguments: -$OPTARG"
      usage
      exit -1
      ;;
  esac
done
shift $((OPTIND-1))

# Check for minimm argument count
if [ -z "$1" ];  then
  echo "No documents provided"
  usage
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

# Remote transfers (-r)
if [ "$SSH_ADDRESS" ]; then
  if nc -z localhost "$PORT" > /dev/null; then
    echo "Port $PORT is already used by a different process!"
    exit -1
  fi

  # Open SSH tunnel for the WebUI
  ssh -M -S remarkable-web-ui -q -f -L "$PORT":"$WEBUI_ADDRESS" root@"$SSH_ADDRESS" -N;

  if ! nc -z localhost "$PORT" > /dev/null; then
    echo "Failed to establish connection with the device!"
    exit -1
  fi

  WEBUI_ADDRESS="localhost:$PORT"
  echo "Established remote connection to the reMarkable web interface"
fi

# Transfer files
echo "Initiating file transfer..."
for f in "$@"; do
  stat=""
  attempt=""
  success=0
  while [[ ! "$stat" && "$attempt" != "n" ]]; do
    if curl --connect-timeout 2 --silent --output /dev/null --form file=@"$f" http://"$WEBUI_ADDRESS"/upload; then
      stat=1
      echo "$f: Success"

      # Dete flag (-d) provided
      if [ "$DELETE_ON_PUSH" ]; then
        rm "$f"
        if [ $? -ne 0 ]; then
          echo "Failed to remove $f"
        fi
      fi

      ((success++))
    else
      stat=""
      echo "$f: Failed"
      read -r -p "Failed to push file! Retry? [Y/n]: " attempt
    fi
  done
done

if [ "$SSH_ADDRESS" ]; then
  ssh -S remarkable-web-ui -O exit root@10.0.0.43
  echo "Closed conenction to the reMarkable web interface"
fi

if [ $success -ne 1 ]; then
  echo "Successfully transferred $success documents"
else
  echo "Successfully transferred $success document"
fi
