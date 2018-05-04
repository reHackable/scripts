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
SSH_ADDRESS="10.11.99.1"
WEBUI_ADDRESS="10.11.99.1:80"

# Remote
PORT=9000 # Deault port to which the webui is tunneled to

function usage {
  echo "Usage: repush.sh [-o output] [-d] [-r ip] [-p port] doc1 [doc2 ...]"
  echo
  echo "Options:"
  echo -e "-o\t\t\tOutput directory to which the provided files will be uploaded to"
  echo -e "-d\t\t\tDelete file after successful push"
  echo -e "-r\t\t\tPush remotely via ssh tunneling"
  echo -e "-p\t\t\tIf -r has been given, this option defines port to which the webui will be tunneled (default 9000)"
}

# Grep remote fs (grep on reMarkable)

# $1 - flags
# $2 - regex
# $3 - File(s)

# $RET - Match(es)
function rmtgrep {
  RET="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "grep -$1 '$2' $3")"
}

# Recursively Search File(s)

# $1 - UUID of parent
# $2 - Path
# $3 - Current Itteration

# $FOUND - List of matched UUIDs
function find {
  OLD_IFS=$IFS
  IFS='/' _PATH=(${2#/}) # Sort path into array
  IFS=$OLD_IFS

  # Nested greps are nightmare to debug, trust me...

  REGEX_NOT_DELETED='"deleted": false'
  REGEX_BY_VISIBLE_NAME="\\\"visibleName\": \\\"${_PATH[$3]}\\\""
  REGEX_BY_PARENT="\\\"parent\\\": \\\"$1\\\""                     # Otherwise, it must be of Collection Type ( Directory )
  REGEX_BY_TYPE='"type": "CollectionType"'

  # Regex order has been optimized
  FILTER=( "$REGEX_BY_VISIBLE_NAME" "$REGEX_BY_PARENT" "$REGEX_BY_TYPE" "$REGEX_NOT_DELETED" )
  RET="/home/root/.local/share/remarkable/xochitl/*.metadata" # Overwritten by rmtgrep
  for regex in "${FILTER[@]}"; do
    rmtgrep "l" "$regex" "$(echo "$RET" | tr '\n' ' ')"
    if [ -z "$RET" ]; then
      break
    fi
  done

  matches=( $(echo "$RET" | grep -o '[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*') )
  for match in "${matches[@]}"; do
    if [ "$(expr $3 + 1)" -eq "${#_PATH[@]}" ]; then # End of path
      FOUND+=($match);
    else
      matches=()

      find "$match" "$2" "$(expr $3 + 1)"            # Expand tree
    fi
  done
}

# Evaluate Options/Parameters
while getopts ":hdr:p:o:" opt; do
  case "$opt" in
    r) # Push Remotely
      SSH_ADDRESS="$OPTARG"
      REMOTE=1
      ;;

    p) # Tunneling Port defined
      PORT="$OPTARG"
      ;;

    o) # Output
      OUTPUT="$OPTARG"
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

# Check for minimum argument count
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

if [ "$REMOTE" ]; then
  if nc -z localhost "$PORT" > /dev/null; then
    echo "repull: Port $PORT is already used by a different process!"
    exit -1
  fi

  # Open SSH tunnel for the WebUI
  ssh -M -S remarkable-ssh -q -f -L "$PORT":"$WEBUI_ADDRESS" root@"$SSH_ADDRESS" -N;

  if ! nc -z localhost "$PORT" > /dev/null; then
    echo "repull: Failed to establish connection with the device!"
    exit -1
  fi

  WEBUI_ADDRESS="localhost:$PORT"
  echo "repull: Established remote connection to the reMarkable web interface"
else
  ssh -M -S remarkable-ssh -q -f root@"$SSH_ADDRESS" -N
fi

echo "Successfully established connection, please do not lock your device until the script has completed!"

s=0

if [ "$OUTPUT" ]; then
  find '' "$OUTPUT" '0'

  if [ "${#FOUND[@]}" -gt 1 ]; then
    REGEX='"lastModified": "[^"]*"'
    FOUND=( "${FOUND[@]/#//home/root/.local/share/remarkable/xochitl/}" )
    GREP="grep -o '$REGEX' ${FOUND[@]/%/.metadata}"
    match="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "$GREP")"

    # Sort metadata by date
    metadata=($(echo "$match" | sed "s/ //g" | sort -rn -t'"' -k4))

    # Create synchronized arrays consisting of file metadata
    uuid=($(echo "${metadata[@]}" | grep -o '[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*')) # UUIDs sorted by date
    lastModified=($(echo "${metadata[@]}" | grep -o '"lastModified":"[0-9]*"' | grep -o '[0-9]*'))    # Date and time of last modification

    echo
    echo "$OUTPUT matches multiple directories!"
    while true; do
      echo

      # Display file id's from most recently modified to oldest
      for (( i=0; i<${#uuid[@]}; i++ )); do
        echo -e "$(expr $i + 1). ${uuid[$i]} - Last modified $(date -d @$(expr ${lastModified[$i]} / 1000) '+%Y-%m-%d %H:%M:%S')"
      done

      read -rp "Select your target directory: " INPUT

      if [ "$INPUT" -gt 0 ] && [ "$INPUT" -lt $(expr i + 1) ]; then
        OUTPUT_UUID="${uuid[(($i-1))]}"
        break
      fi

      echo "Invalid input"
    done

  elif [ "${#FOUND[@]}" -eq 0 ]; then
    echo "Unable to find output directory: $OUTPUT"
    exit

  else
    OUTPUT_UUID="$FOUND"
  fi

  echo
  echo "==================================================================================================================================="
  echo "Shipping documents to output directory. It is highly recommended to refrain from using your device until this script has completed!"
  echo "==================================================================================================================================="
  echo

  RFKILL="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "/usr/sbin/rfkill list 0 | grep 'blocked: yes'")"
  if [ -z "$RFKILL" ]; then
    echo "Temporarily disabling Wi-Fi to prevent conflicts with the cloud"
    ssh -S remarkable-ssh root@"$SSH_ADDRESS" "/usr/sbin/rfkill block 0"
    echo
  fi

  for f in "$@"; do
    TMP="/tmp/repush"
    rm -rf "$TMP"
    mkdir -p "$TMP"
    basename="$(basename "$f")"
    tmpfname=_tmp_repush_"${basename%.*}"_tmp_repush_."${basename##*.}"
    tmpf="$TMP/$tmpfname"
    cp "$f" "$tmpf"

    if [ -f "$tmpf" ]; then
      echo "Shipping '$f'"

      stat=""
      attempt=""
      while [[ ! "$stat" && "$attempt" != "n" ]]; do
        if curl --connect-timeout 2 --silent --output /dev/null --form file=@"\"$tmpf\"" http://"$WEBUI_ADDRESS"/upload; then
          stat=1

          echo "Accessing metadata for '$(basename "$f")'"
          while [ -z "$metadata" ]; do
            metadata="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "grep -l '\"visibleName\": \"$tmpfname\"' ~/.local/share/remarkable/xochitl/*.metadata")"
          done

          ssh -S remarkable-ssh root@"$SSH_ADDRESS" "sed -i 's/\"parent\": \"[^\"]*\"/\"parent\": \"$OUTPUT_UUID\"/' $metadata && sed -i 's/\"visibleName\": \"[^\"]*\"/\"visibleName\": \"$basename\"/' $metadata"
          ((success++))
          echo "$f: Success"
          echo
        else
          stat=""
          echo "$f: Failed"
          read -r -p "Failed to push file! Retry? [Y/n]: " attempt
        fi
      done

    else
      echo "Failed to prepare '$f' for shipping"
    fi

  done

  echo "Applying changes..."
  ssh -S remarkable-ssh root@"$SSH_ADDRESS" "systemctl restart xochitl;"

  if [ -z "$RFKILL" ]; then
    echo "Re-enabling Wi-Fi in 5 seconds..."
    echo
    ssh -S remarkable-ssh root@"$SSH_ADDRESS" "sleep 5; /usr/sbin/rfkill unblock 0"
  fi

else
  echo
  echo "========================"
  echo "Initiating file transfer"
  echo "========================"
  echo
  for f in "$@"; do
    stat=""
    attempt=""
    while [[ ! "$stat" && "$attempt" != "n" ]]; do
      echo "Pushing '$f'..."
      if curl --connect-timeout 2 --silent --output /dev/null --form file=@"\"$f\"" http://"$WEBUI_ADDRESS"/upload; then
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

        echo
      else
        stat=""
        echo "$f: Failed"
        read -r -p "Failed to push file! Retry? [Y/n]: " attempt
      fi
    done
  done
fi

ssh -S remarkable-ssh -O exit root@"$SSH_ADDRESS"
echo "Successfully transferred $success out of $# documents"
