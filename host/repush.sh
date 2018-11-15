#!/usr/bin/env bash

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
#                 using the Web client and SSH

# Dependencies  : cURL, ssh, nc

# Usage         : https://github.com/reHackable/scripts/wiki/repush.sh

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
  echo -e "-p\t\t\tIf -r has been given, this option defines the port to which the webui will be tunneled (default 9000)"
}

# Grep remote fs (grep on reMarkable)

# $1 - flags
# $2 - regex
# $3 - File(s)

# $RET_MATCH - Match(es)
function rmtgrep {
  RET_MATCH="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "grep -$1 '$2' $3")"
}

# Recursively Search for a Directory

# $1 - UUID of parent
# $2 - Path
# $3 - Current Itteration

# $RET_FOUND - List of matched UUIDs
function find_directory {
  OLD_IFS=$IFS
  IFS='/' _PATH=(${2#/}) # Sort path into array
  IFS=$OLD_IFS

  RET_FOUND=()

  rmtgrep "lF" "\"visibleName\": \"${_PATH[$3]}\"" "/home/root/.local/share/remarkable/xochitl/*.metadata"
  matches_by_name="$RET_MATCH"

  for metadata_path in $matches_by_name; do

    metadata="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "cat $metadata_path")"

    if ! echo "$metadata" | grep -qF "\"parent\": \"$1\""; then
      continue
    fi

    if echo "$metadata" | grep -qF '"deleted": true'; then
      continue
    fi

    if ! echo "$metadata" | grep -qF '"type": "CollectionType"'; then
      continue
    fi

    if [[ "$(expr $3 + 1)" -eq "${#_PATH[@]}" ]]; then
      RET_FOUND+=("$(basename "$metadata_path" .metadata)")
    else
      find_directory "$(basename "$metadata_path" .metadata)" "$2" "$(expr $3 + 1)"
    fi

  done
}

# Obtain the UUID for a file localted in the root directory

# $1 - Visible Name

# $RET_UUID - Returned UUID(s)
function uuid_of_root_file {
  RET_UUID=""

  rmtgrep "lF" "\"visibleName\": \"$1\"" "~/.local/share/remarkable/xochitl/*.metadata"
  matches_by_name="$RET_MATCH"

  if [ -z "$matches_by_name" ]; then
    return
  fi

  for metadata_path in $matches_by_name; do

    metadata="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "cat $metadata_path")"

    if echo "$metadata" | grep -qF '"parent": ""' && echo "$metadata" | grep -qF '"deleted": false'; then
      RET_UUID="$(basename "$metadata_path" .metadata)"
      break
    fi
  done
}

# Push documents to the device

# $1 - Path to document (Must be EPUB or PDF)

# $RET_UUID - The fs UUID of the document
# $? - 1: transfer succeeded | 0: transfer failed
function push {

  file_cmd_output="$(file -F '|' "$1")"

  if [ ! -z "$(echo "$file_cmd_output" | grep -o "| PDF")" ]; then
    extension="pdf"
  else
    extension="epub"
  fi

  # Create placeholder
  placeholder="/tmp/repush/$(basename "$1")"
  touch "$placeholder"

  while true; do
    if curl --connect-timeout 2 --silent --output /dev/null --form file=@"\"$placeholder\"" http://"$WEBUI_ADDRESS"/upload; then

      # Wait for metadata to be generated
      while true; do
        uuid_of_root_file "$(basename "$1")"
        if [ ! -z "$RET_UUID" ]; then
          break
        fi
      done;

      # Wait for placeholder to be transferred
      while true; do
        if ssh -S remarkable-ssh root@"$SSH_ADDRESS" stat "/home/root/.local/share/remarkable/xochitl/$RET_UUID.$extension" \> /dev/null 2\>\&1; then
          break
        fi
      done;

      # Replace placeholder with document
      retry=""
      while true; do
        scp "$1" root@"$SSH_ADDRESS":"/home/root/.local/share/remarkable/xochitl/$RET_UUID.$extension"

        if [ $? -ne 0 ]; then
          read -r -p "Failed to replace placeholder! Retry? [Y/n]: " retry
          if [[ $retry == "n" || $retry == "N" ]]; then
            return 0
          fi
        else
          break
        fi
      done

      # Delete thumbnails (TODO: Replace thumbnail with pre-rendered thumbnail)
      ssh -S remarkable-ssh root@"$SSH_ADDRESS" "rm -f /home/root/.local/share/remarkable/xochitl/$RET_UUID.thumbnails/*"

      return 1

    else
      retry=""
      echo "$1: Failed"
      read -r -p "Failed to push file! Retry? [Y/n]: " retry

      if [[ $retry == "n" || $retry == "N" ]]; then
        return 0
      fi
    fi
  done
}

# Evaluate Options/Parameters
while getopts ":hdr:p:o:" opt; do
  case "$opt" in
    h) # Usage help
      usage
      exit 1
      ;;

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

# Check file validity
for f in "$@"; do
  file_cmd_output="$(file -F '|' "$f")"
  if [ ! -f "$f" ]; then
    echo "No such file: $f"
    exit -1
  elif [[ -z "$(echo "$file_cmd_output" | grep -o "| PDF")" && -z "$(echo "$file_cmd_output" | grep -o "| EPUB")" ]]; then
    echo "Unsupported file format: $f"
    echo "Only PDFs and EPUBs are supported"
    exit -1
  elif [[ -z "$(echo "$f" | grep -oP "\.pdf$")" && -z "$(echo "$f" | grep -oP "\.epub$")" ]]; then
    echo "File extension invalid or missing: $f"
    exit -1
  fi
done

# Establish remote connection
if [ "$REMOTE" ]; then
  if nc -z localhost "$PORT" > /dev/null; then
    echo "repush: Port $PORT is already used by a different process!"
    exit -1
  fi

  ssh -o ConnectTimeout=5 -M -S remarkable-ssh -q -f -L "$PORT":"$WEBUI_ADDRESS" root@"$SSH_ADDRESS" -N;
  WEBUI_ADDRESS="localhost:$PORT"
else
  ssh -o ConnectTimeout=1 -M -S remarkable-ssh -q -f root@"$SSH_ADDRESS" -N
fi

if [ "$?" -ne 0 ]; then
  echo "repush: Failed to establish connection with the device!"
  exit -1
fi

# Check if file with same name already exists in the root directory
for f in "$@"; do
  uuid_of_root_file "$(basename "$f")"

  if [ ! -z $RET_UUID ]; then
    echo "repush: Cannot push '$f': File already exists in root directory"
    ssh -S remarkable-ssh -O exit root@"$SSH_ADDRESS"
    rm -rf /tmp/repush
    exit -1
  fi
done

# Create directory in /tmp/repush for placeholders
rm -rf "/tmp/repush"
mkdir -p "/tmp/repush"

# Find output directory
OUTPUT_UUID=""
if [ "$OUTPUT" ]; then
  find_directory '' "$OUTPUT" '0'

  # Multiple directories match
  if [ "${#RET_FOUND[@]}" -gt 1 ]; then
    REGEX='"lastModified": "[^"]*"'
    RET_FOUND=( "${RET_FOUND[@]/#//home/root/.local/share/remarkable/xochitl/}" )
    GREP="grep -o '$REGEX' ${RET_FOUND[@]/%/.metadata}"
    match="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "$GREP")" # Returns string that includes Metadata Path + Modification date

    # Sort metadata by date
    metadata=($(echo "$match" | sed "s/ //g" | sort -rn -t'"' -k4))

    # Create synchronized arrays consisting of file metadata
    uuid=($(echo "${metadata[@]}" | grep -o '[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*')) # UUIDs sorted by date
    lastModified=($(echo "${metadata[@]}" | grep -o '"lastModified":"[0-9]*"' | grep -o '[0-9]*'))    # Date and time of last modification

    echo
    echo "'$OUTPUT' matches multiple directories!"
    while true; do
      echo

      # Display file id's from most recently modified to oldest
      for (( i=0; i<${#uuid[@]}; i++ )); do
        echo -e "$(expr $i + 1). ${uuid[$i]} - Last modified $(date -d @$(expr ${lastModified[$i]} / 1000) '+%Y-%m-%d %H:%M:%S')"
      done

      read -rp "Select your target directory: " INPUT
      echo

      if [[ "$INPUT" -gt 0  && "$INPUT" -lt $(expr $i + 1) ]]; then
        OUTPUT_UUID="${uuid[(($INPUT-1))]}"
        break
      fi

      echo "Invalid input"
    done

  # Directory not found
  elif [ "${#RET_FOUND[@]}" -eq 0 ]; then
    echo "Unable to find output directory: $OUTPUT"
    rm -rf /tmp/repush
    ssh -S remarkable-ssh -O exit root@"$SSH_ADDRESS"
    exit -1

  # Directory found
  else
    OUTPUT_UUID="$RET_FOUND"
  fi

  # Disable wifi to prevent conflicts with cloud
  RFKILL="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "/usr/sbin/rfkill list 0 | grep 'blocked: yes'")"
  if [ -z "$RFKILL" ]; then
    echo "Temporarily disabling Wi-Fi to prevent conflicts with the cloud"
    ssh -S remarkable-ssh root@"$SSH_ADDRESS" "/usr/sbin/rfkill block 0"
    echo
  fi
fi

# Push documents
success=0
for f in "$@"; do
  push "$f"

  if [ $? == 1 ]; then
    if [ "$OUTPUT" ]; then
      # Move file to output directory
      ssh -S remarkable-ssh root@"$SSH_ADDRESS" "sed -i 's/\"parent\": \"[^\"]*\"/\"parent\": \"$OUTPUT_UUID\"/' /home/root/.local/share/remarkable/xochitl/$RET_UUID.metadata"
    fi

    # Dete flag (-d) provided
    if [ "$DELETE_ON_PUSH" ]; then
      rm "$f"
      if [ $? -ne 0 ]; then
        echo "Failed to remove $f"
      fi
    fi
    ((success++))
  else
    echo "$f: Failed"
  fi
done

# Restart xochitl to apply changes to metadata
if [ "$OUTPUT" ]; then
  echo "Applying changes..."
  ssh -S remarkable-ssh root@"$SSH_ADDRESS" "systemctl restart xochitl;"

  if [ -z "$RFKILL" ]; then
    echo "Re-enabling Wi-Fi in 5 seconds..."
    echo
    ssh -S remarkable-ssh root@"$SSH_ADDRESS" "sleep 5; /usr/sbin/rfkill unblock 0"
  fi
fi

rm -rf /tmp/repush
ssh -S remarkable-ssh -O exit root@"$SSH_ADDRESS"
echo "Successfully transferred $success out of $# documents"
