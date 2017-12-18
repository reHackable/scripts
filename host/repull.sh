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

# Description   : A host sided script that can download one or more documents from the reMarkable
#                 using the Web client

# Dependencies  : cURL, ssh, nc, date, grep

# Local
WEBUI_ADDRESS="10.11.99.1:80"

# Remote
PORT=9000 # Deault port to which the webui is tunneled to

function usage {
  echo "Usage: repull.sh [-r ip] [-p port] docname1 [docname2 ...]"
  echo
  echo "Options:"
  echo -e "-r\t\t\tPull remotely via ssh tunneling"
  echo -e "-p\t\t\tIf -r has been given, this option defines port to which the webui will be tunneled (default 9000)"
  echo
  echo "If multiple documents share the same name, the script will prompt you"
  echo "to select one or more documents from a list that is sorted by modficiation"
  echo "date. The first list entry represents the most recently updated document."
}

# Evaluate Options/Parameters
while getopts ":hr:p:" remote; do
  case "$remote" in
    r) # Pull Remotely
      SSH_ADDRESS="$OPTARG"
      ;;

    p) # Tunneling Port defined
      PORT="$OPTARG"
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
  echo "No document names provided"
  usage
  exit -1
fi

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

# Check if name matches document
# this way we can prevent unecessary pulling
echo "Checking device for documents..."
for n in "$@"; do
  REGEX="\"visibleName\": \"$n\""
  GREP="grep -l -r '$REGEX' /home/root/.local/share/remarkable/xochitl/*.metadata"
  id="$(ssh root@"$SSH_ADDRESS" "$GREP")"
  matches=($id)

  # Name assigned to multiple documents
  # Prepare for a mess
  # This was the most efficient and elegant
  # solution I could currently come up with
  if [ ${#matches[@]} -gt 1 ]; then
    REGEX="\"lastModified\": \".*"
    GREP="grep -o '$REGEX' ${matches[*]}"
    matchAndDate="$(ssh root@"$SSH_ADDRESS" "$GREP | sort -rn -t'\"' -k4")"

    fileids=($(echo "${matchAndDate[@]}" | grep -o '[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*'))
    modtimes=($(echo "${matchAndDate[@]}" | grep -o '"[0-9]*"' | grep -o '[0-9]*'))

    echo
    echo "$n matches multiple documents!"
    while true; do
      echo

      # Display file id's from most recently modified to oldest
      for (( i=0; i<${#fileids[@]}; i++ )); do
        echo "$(expr $i + 1). ${fileids[$i]} - Last modified $(date -d @$(expr ${modtimes[$i]} / 1000) '+%Y-%m-%d %H:%M:%S')"
      done

      echo
      read -r -p "Select one or more documents to be downloaded [ie. 1, 1 2 3 or 1-3]: " input

      # Input is a range
      if [[ "$input" =~ ^([1-9][0-9]*)\ *\-\ *([1-9][0-9]*)\ *$ ]]; then
        start=${BASH_REMATCH[1]}
        end=${BASH_REMATCH[2]}
        if [ "$start" -gt $i ] || [ "$end" -gt $i ] || [ "$start" -gt $end ]; then
          echo
          echo "Invalid order or index out of range"
          continue
        fi

        # Fetch requested files
        for (( i=$start-1; i<$end; i++ )); do
          date=$(date -d @"$(expr ${modtimes[$i]} / 1000)" '+%Y%m%d%H%M%S')
          f=$(curl --connect-timeout 2 -JLO http://"$WEBUI_ADDRESS"/download/"${fileids[$i]}"/placeholder | grep -oP "(?<=curl: Saved to filename ')[^']*");
          if [ $? -eq 1 ]; then
            echo "$n($date): Failed"
          else
            newf="${f%.*}($date).${f##*.}"
            mv "$f" "$newf"
            echo "$newf: Success"
          fi
        done
        break

      # Input is one or more numbers
      elif [[ "$input" =~ ^([1-9][0-9]*\ *)*$ ]]; then
        for i in $input; do
          ((i--)) # Decrement itterator to match array index
          date=$(date -d @"$(expr ${modtimes[$i]} / 1000)" '+%Y%m%d%H%M%S')
          f=$(curl --connect-timeout 2 -JLO http://"$WEBUI_ADDRESS"/download/"${fileids[$i]}"/placeholder | grep -oP "(?<=curl: Saved to filename ')[^']*");
          if [ $? -eq 1 ]; then
            echo "$n($date): Failed"
          else
            newf="${f%.*}($date).${f##*.}"
            mv "$f" "$newf"
            echo "$newf: Success"
          fi
        done
        break

      # Input is invalid
      else
        echo
        echo "Invalid input"
      fi
    done

  # Fetch document assigned to name
  elif [ ! -z "$matches" ]; then
    fid=$(echo "$matches" | grep -o '[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*')
    f=$(curl --connect-timeout 2 -JLO http://"$WEBUI_ADDRESS"/download/"$fid"/placeholder | grep -oP "(?<=curl: Saved to filename ')[^']*");
    if [ $? -eq 1 ]; then
      echo "$n: Failed"
    else
      echo "$f: Success"
    fi

  # Document not found
  else
    echo "Unable to find document for $n"
  fi
done

if [ "$SSH_ADDRESS" ]; then
  ssh -S remarkable-web-ui -O exit root@10.0.0.43
  echo "Closed conenction to the reMarkable web interface"
fi
