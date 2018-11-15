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

# Author        : Patrick Pedersen <ctx.xda@gmail.com>,
#                 Part of the reHackable organization <https://github.com/reHackable>

# Description   : A host sided script that can download one or more documents or directories
#                 from the reMarkable via SSH and the Web client.

# Dependencies  : wget, ssh, nc, date, grep

# Default Values
WEBUI_ADDRESS="10.11.99.1:80"
SSH_ADDRESS="10.11.99.1"
PORT=9000                     # Deault port to which the webui is tunneled to

function usage {
  echo "Usage: repull.sh [-d] [-o out] [-r ip] [-p port] path [path ...]"
  echo
  echo "Options:"
  echo -e "-o\t\t\tOutput file or directory"
  echo -e "-d\t\t\tRecursively pull directories"
  echo -e "-r\t\t\tPull remotely via ssh tunneling"
  echo -e "-p\t\t\tIf -r has been given, this option defines port to which the webui will be tunneled (default 9000)"
}

# Grep remote fs (grep on reMarkable)

# $1 - flags
# $2 - regex
# $3 - File(s)

# $RET_MATCH - Match(es)
function rmtgrep {
  RET_MATCH="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "grep -$1 '$2' $3")"
}

# Downloads document trough the webui

# $1 - WebUI address (10.11.99.1)
# $2 - File UUID
# $3 - Output path
function download {

  wget_out="$(wget --content-disposition http://"$1"/download/"$2"/placeholder 2>&1 >/dev/null)"

  if [ "$?" -ne 0 ]; then
    echo "repull: Download failed"
    ssh -S remarkable-ssh -O exit root@"$SSH_ADDRESS"
    exit -1
  fi

  file_name="$(echo "$wget_out" | grep --color -oP '(?<=Saving to\: ‘).*(?=’)')"

  if [ -d "$3" ]; then
    new_file_name=${file_name#"'"}
    new_file_name=${new_file_name%"'"}

    suffix=1
    safe_file_name="$new_file_name"
    while [[ -f "$safe_file_name" || -d "$safe_file_name" ]]; do
      safe_file_name="$new_file_name ($suffix)"
      ((suffix++))
    done

    mv "$file_name" "$3/$safe_file_name"
  else
    mv "$file_name" "$3"
  fi

}

# Recursively download a directory

# $1 - WebUI address (10.11.99.1)
# $2 - Base dir name
# $3 - Directory UUID
# $4 - Output directory

# $? - 1: Success | 0: Directory Empty
function download_dir {

  rmtgrep "lF" "\"parent\": \"$3\"" "/home/root/.local/share/remarkable/xochitl/*.metadata"
  child_metadata="$RET_MATCH"

  if [ -z "$child_metadata" ]; then
    return 0
  fi

  child_directories=()

  for metadata_path in $child_metadata; do

    metadata="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "cat $metadata_path")"

    if echo "$metadata" | grep -qF '"deleted": true'; then
      continue
    fi

    if echo "$metadata" | grep -qF '"type": "DocumentType"'; then
      visible_name="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "cat $metadata_path" | grep -oP "(?<=\"visibleName\"\: \").*(?=\"\$)")"
      echo "repull: Pulling '$2/$visible_name'"

      uuid="$(basename "$metadata_path" .metadata)"
      download "$1" "$uuid" "$4"
    else
      child_directories+=("$metadata_path")
    fi
  done

  for metadata in "${child_directories[@]}"; do

    visible_name="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "cat $metadata_path" | grep -oP "(?<=\"visibleName\"\: \").*(?=\"\$)")"
    safe_visible_name="$visible_name"

    suffix=1

    while [[ -d "$4/$safe_visible_name" || -f "$4/$safe_visible_name" ]]; do
      safe_visible_name="$visible_name ($suffix)"
      ((suffix++))
    done

    mkdir "$4/$safe_visible_name"
    if [ $? -ne 0 ]; then
      echo "repull: Failed to create directory: $4/$safe_visible_name"
      ssh -S remarkable-ssh -O exit root@"$SSH_ADDRESS"
      exit -1
    fi

    download_dir "$1" "$2/$safe_visible_name" "$(basename "$metadata_path" .metadata)" "$4/$safe_visible_name"

    if [ $? -eq 0 ]; then
      rm -rf "$4/$safe_visible_name"
    fi

  done

  return 1

}

# Recursively Search Document(s)

# $1 - UUID of parent
# $2 - Path
# $3 - Current Itteration

# $RET_FOUND - List of matched UUIDs
function find_document {
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

    if [[ "$(expr $3 + 1)" -eq "${#_PATH[@]}" ]]; then
      if echo "$metadata" | grep -qF '"type": "DocumentType"'; then
        RET_FOUND+=("$(basename "$metadata_path" .metadata)")
      fi
    else
      if echo "$metadata" | grep -qF '"type": "CollectionType"'; then
        find_document "$(basename "$metadata_path" .metadata)" "$2" "$(expr $3 + 1)"
      fi
    fi

  done
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

OUTPUT="."

# Evaluate Options/Parameters
while getopts ":hdo:r:p:" opt; do
  case "$opt" in

    h) # Usage help
      usage
      exit 1
      ;;

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

    d) # Download directory
      path_is_directory=true
      ;;

    ?) # Unkown Option
      echo "repull: Invalid option or missing arguments: -$OPTARG"
      usage
      exit -1
      ;;

  esac
done
shift $((OPTIND-1))

# Check for minimum argument count
if [ -z "$1" ];  then

  if [ -n "$path_is_directory" ]; then
    echo "repull: No directory provided"
  else
    echo "repull: No document provided"
  fi

  usage
  exit -1
fi

if [[ -n "$OUTPUT" && $# -gt 1 ]] && [ ! -d "$OUTPUT" ]; then
  echo "repull: Output path '$OUTPUT' is not a directory"
  exit -1
fi

# Establish remote connection
if [ "$REMOTE" ]; then
  if nc -z localhost "$PORT" > /dev/null; then
    echo "repull: Port $PORT is already used by a different process!"
    exit -1
  fi

  ssh -o ConnectTimeout=5 -M -S remarkable-ssh -q -f -L "$PORT":"$WEBUI_ADDRESS" root@"$SSH_ADDRESS" -N;
  WEBUI_ADDRESS="localhost:$PORT"
else
  ssh -o ConnectTimeout=1 -M -S remarkable-ssh -q -f root@"$SSH_ADDRESS" -N
fi

if [ "$?" -ne 0 ]; then
  echo "repull: Failed to establish connection with the device!"
  exit -1
fi

# Find and pull documents
for path in "$@"; do

  if [ -n "$path_is_directory" ]; then
    find_directory "" "$path" 0
  else
    find_document "" "$path" 0
  fi

  # Entry not found
  if [ "${#RET_FOUND[@]}" -eq 0 ]; then

    if [ -n "$path_is_directory" ]; then
      echo "repull: Unable to find directory: $path"
    else
      echo "repull: Unable to find document: $path"
    fi

    ssh -S remarkable-ssh -O exit root@"$SSH_ADDRESS"
    exit -1

  # Multiple entries match
  elif [ "${#RET_FOUND[@]}" -gt 1 ]; then
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

    if [ -n "$path_is_directory" ]; then
      echo "'$path' matches multiple directories!"
    else
      echo "'$path' matches multiple files!"
    fi

    while true; do
      echo

      # Display file id's from most recently modified to oldest
      for (( i=0; i<${#uuid[@]}; i++ )); do
        echo -e "$(expr $i + 1). ${uuid[$i]} - Last modified $(date -d @$(expr ${lastModified[$i]} / 1000) '+%Y-%m-%d %H:%M:%S')"
      done

      echo
      read -rp "Select your target directory: " INPUT
      echo

      if [[ "$INPUT" -gt 0  && "$INPUT" -lt $(expr $i + 1) ]]; then
        OUTPUT_UUID="${uuid[(($INPUT-1))]}"
        break
      fi

      echo "Invalid input"
    done

  # Entry found
  else
    OUTPUT_UUID="$RET_FOUND"
  fi

  # Pull directory
  if [ -n "$path_is_directory" ]; then

    if [ -d $OUTPUT ]; then
      local_dir="$OUTPUT/$(basename "$path")"
    else
      local_dir="$OUTPUT"
    fi

    mkdir "$local_dir"

    if [ $? -ne 0 ]; then
      echo "repull: Failed to create local directory: $local_dir"
      exit -1
    fi

    download_dir "$WEBUI_ADDRESS" "$(echo /${path%/} | tr -s '/')" "$OUTPUT_UUID" "$local_dir"

    if [ "$?" -eq 0 ]; then
      echo "repull: Refused to download $path, directory empty!"
    fi

  # Pull Document
  else
    echo "repull: Pulling '$path'"
    download "$WEBUI_ADDRESS" "$OUTPUT_UUID" "$OUTPUT"
  fi

done

ssh -S remarkable-ssh -O exit root@"$SSH_ADDRESS"
