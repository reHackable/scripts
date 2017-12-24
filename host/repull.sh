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

# Default Values
WEBUI_ADDRESS="10.11.99.1:80"
SSH_ADDRESS="10.11.99.1"
PORT=9000                     # Deault port to which the webui is tunneled to

function usage {
  echo "Usage: repull.sh [-o out] [-r ip] [-p port] docname1 [docname2 ...]"
  echo
  echo "Options:"
  echo -e "-o\t\t\tOutput file or directory"
  echo -e "-r\t\t\tPull remotely via ssh tunneling"
  echo -e "-r\t\t\tPull remotely via ssh tunneling"
  echo -e "-p\t\t\tIf -r has been given, this option defines port to which the webui will be tunneled (default 9000)"
  echo
  echo "If multiple documents share the same name, the script will prompt you"
  echo "to select one or more documents from a list that is sorted by modification"
  echo "date. The first list entry represents the most recently updated document."
}

# Downloads document trough the webui

# $1 - WebUI address (10.11.99.1)
# $2 - File ID
# $3 - Output name or dir (Opt)
# $4 - Text to be appended to file name (before extension) (Opt)
function download {
  f=$(curl --connect-timeout 2 -JLO http://"$1"/download/"$2"/placeholder | grep -oP "(?<=curl: Saved to filename ')[^']*");

  # Check if name or appendation has been provided
  if [ "$?" -eq 0 ] && [ "$3" ] || [ "$4" ]; then
    oldf="$f"

    # Defined name or dir
    if [ "$3" ]; then
      if [ -d "$3" ]; then # Dir
        f="${3%/}/$f"
      else
        f="$3" # Name
      fi
    fi

    # Append to name
    if [ "$4" ]; then
      if [[ $f =~ ^.*\..*$ ]]; then
        ext=".${f##*.}"
      fi
      f="${f%.*}$4$ext"
    fi

    # Move/Rename file
    mv "$oldf" "$f"
    if [ "$?" -eq 1 ]; then
      echo "repull: Failed to move or rename $oldf to $f"
      return
    fi
  fi
}

# Evaluate Options/Parameters
while getopts ":ho:r:p:" remote; do
  case "$remote" in
    o) # Output path
      OUTPUT="$OPTARG"
      ;;

    r) # Pull Remotely
      SSH_ADDRESS="$OPTARG"
      REMOTE=1
      ;;

    p) # Tunneling Port defined
      PORT="$OPTARG"
      ;;

    h) # Usage help
      usage
      exit 1
      ;;

    ?) # Unkown Option
      echo "repull: Invalid option or missing arguments: -$OPTARG"
      usage
      exit -1
      ;;
  esac
done
shift $((OPTIND-1))

# Check for minimm argument count
if [ -z "$1" ];  then
  echo "repull: No document names provided"
  usage
  exit -1
fi

if [ $# -gt 1 ] && [ ! -d "$OUTPUT" ]; then
  echo "repull: Output path '$OUTPUT' is not a directory"
  exit -1
fi

# Remote transfers (-r)
if [ "$REMOTE" ]; then
  if nc -z localhost "$PORT" > /dev/null; then
    echo "repull: Port $PORT is already used by a different process!"
    exit -1
  fi

  # Open SSH tunnel for the WebUI
  ssh -M -S remarkable-web-ui -q -f -L "$PORT":"$WEBUI_ADDRESS" root@"$SSH_ADDRESS" -N;

  if ! nc -z localhost "$PORT" > /dev/null; then
    echo "repull: Failed to establish connection with the device!"
    exit -1
  fi

  WEBUI_ADDRESS="localhost:$PORT"
  echo "repull: Established remote connection to the reMarkable web interface"
fi

# Check if name matches document
# this way we can prevent unecessary pulling
echo "repull: Checking device for documents..."
for n in "$@"; do
  # Retrieve file name(s)/uuid(s) for visible name
  REGEX="\"visibleName\": \"$n\""
  GREP="grep -l -r '$REGEX' /home/root/.local/share/remarkable/xochitl/*.metadata"
  uuid=($(ssh root@"$SSH_ADDRESS" "$GREP")) # List of matched file name(s)/uuid(s)

  # Name assigned to multiple documents
  # Prepare for a mess
  # This was the most efficient and elegant
  # solution I could currently come up with
  if [ ${#uuid[@]} -gt 1 ]; then
    REGEX="\"lastModified\": \".*"
    GREP="grep -o '$REGEX' ${uuid[*]}"
    metadata="$(ssh root@"$SSH_ADDRESS" "$GREP | sort -rn -t'\"' -k4")"

    # Create synchronized arrays consisting of file metadata
    uuid=($(echo "${metadata[@]}" | grep -o '[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*')) # UUIDs sorted by date
    lastModified=($(echo "${metadata[@]}" | grep -o '"[0-9]*"' | grep -o '[0-9]*'))                   # Date and time of last modification

    echo
    echo "'$n' matches multiple documents!"
    while true; do
      echo

      # Display file id's from most recently modified to oldest
      for (( i=0; i<${#fileids[@]}; i++ )); do
        echo "$(expr $i + 1). ${fileids[$i]} - Last modified $(date -d @$(expr ${lastModified[$i]} / 1000) '+%Y-%m-%d %H:%M:%S')"
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
          date=$(date -d @"$(expr ${lastModified[$i]} / 1000)" '+%Y%m%d%H%M%S')
          download "$WEBUI_ADDRESS" "${fileids[i]}" "$OUTPUT" "($date)"
          if [ $? -eq 0 ]; then
            echo "$f: Success"
          else
            echo "$n($date): Failed"
          fi
        done
        break

      # Input is one or more numbers
      elif [[ "$input" =~ ^([1-9][0-9]*\ *)*$ ]]; then

        # Check input validity before pulling
        INPUT_VALID=1
        for j in $input; do
          if [ "$j" -gt "$i" ]; then
            echo "Index: '$j' out of range!"
            INPUT_VALID=0
          fi
        done

        if [ "$INPUT_VALID" -eq 1 ]; then
          # Input valid, time to pull!
          for j in $input; do
            ((j--)) # Decrement itterator to match array index
            date=$(date -d @"$(expr ${lastModified[$j]} / 1000)" '+%Y%m%d%H%M%S')
            download "$WEBUI_ADDRESS" "${fileids[j]}" "$OUTPUT" "($date)"
            if [ $? -eq 0 ]; then
              echo "$f: Success"
            else
              echo "$n($date): Failed"
            fi
          done
          break
        fi

      # Input is invalid
      else
        echo
        echo "Invalid input"
      fi
    done

  # Fetch document assigned to name
elif [ ! -z "$uuid" ]; then
    uuid=$(echo "$uuid" | grep -o '[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*')
    download "$WEBUI_ADDRESS" "$uuid" "$OUTPUT" ""
    if [ $? -eq 0 ]; then
      echo "$f: Success"
    else
      echo "$n($date): Failed"
    fi

  # Document not found
  else
    echo "Unable to find document for '$n'"
  fi
done

if [ "$REMOTE" ]; then
  ssh -S remarkable-web-ui -O exit root@10.0.0.43
  echo "repull: Closed conenction to the reMarkable web interface"
fi
