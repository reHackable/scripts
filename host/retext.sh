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

# Description   : Host sided reMarkable tablet script that sets epub text settings back to default

# Dependencies  : ssh, nc

# Notations     : As a result of the scalability that epub documents provide,
#                the document is set back to page one

#                When epubs are set back to their initial state, their cache files are deleted.
#                due to this, the epub may take some time to load on first open

# Current version (MAJOR.MINOR)
VERSION="1.0"

SSH_ADDRESS="10.11.99.1"

# Initial state of .content files
INIT_CONTENT='{
    "extraMetadata": {
    },
    "fileType": "epub",
    "fontName": "",
    "lastOpenedPage": 0,
    "lineHeight": -1,
    "margins": 100,
    "pageCount": 1,
    "textScale": 1,
    "transform": {
        "m11": 1,
        "m12": 0,
        "m13": 0,
        "m21": 0,
        "m22": 1,
        "m23": 0,
        "m31": 0,
        "m32": 0,
        "m33": 1
    }
}'

function usage {
  echo "Usage: repull.sh [-h] [-r ssh_address] path_to_epub1 [path_to_epub2 ...]"
  echo ""
  echo "Options:"
  echo -e "-v\t\tDisplay version and exit"
  echo -e "-h\t\tDisplay usage and exit"
  echo -e "-r\t\tAccess device remotely"
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
  REGEX_BY_PARENT="\\\"parent\\\": \\\"$1\\\""

  if [ "$(expr $3 + 1)" -eq "${#_PATH[@]}" ]; then   # Last entry must be of Document Type ( Document/File )
    REGEX_BY_TYPE='"type": "DocumentType"'
  else                                               # Otherwise, it must be of Collection Type ( Directory )
    REGEX_BY_TYPE='"type": "CollectionType"'
  fi

  # Regex order has been optimized
  FILTER=( "$REGEX_BY_VISIBLE_NAME" "$REGEX_BY_PARENT" "$REGEX_BY_TYPE" "$REGEX_NOT_DELETED" )
  RET="/home/root/.local/share/remarkable/xochitl/*.metadata" # Overwritten by rmtgrep
  for regex in "${FILTER[@]}"; do
    rmtgrep "l" "$regex" "$(echo $RET | tr '\n' ' ')"
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

# --- Script starts here --- #

# Check Args
if [ -z "$1" ]; then
  echo "No documents provided"
  echo
  usage
  exit -1
elif [[ "$1" == "-v" ]]; then
  echo "retext version: $VERSION"
  exit -1
elif [[ "$1" == "-h" ]]; then
  usage
elif [[ "$1" == "-r" ]]; then
  if [ ! -z "$3" ]; then
    SSH_ADDRESS=$2
    shift 2
  else
    echo "Missing arguments!"
    echo
    usage
    exit
  fi
fi

# Check connection to device
echo "Attempting to establish connection with the device..."
ssh -q root@"$SSH_ADDRESS" exit

if [ "$?" -ne 0 ]; then
  echo "Failed to establish connection!"
  exit -1
fi

echo "Successfully established connection, please do not lock your device until the script has completed!"

# Generate list of epub uuids
for path in "$@"; do
  FOUND=()
  FOUND_EPUBS=()
  find "" "$path" 0

  if [ -z "$FOUND" ]; then
    echo "Unable to find document for '$path'"
    exit -1
  else
    for uuid in "${FOUND[@]}"; do
      # Check if file is epub
      if [ "$(ssh root@"$SSH_ADDRESS" "if [ -f /home/root/.local/share/remarkable/xochitl/$uuid.epub ]; then echo 1; fi")" ]; then
        FOUND_EPUBS+=("$uuid")
      fi
    done

    # Document not epub
    if [ ! "$FOUND_EPUBS" ]; then
      echo "Document '$path' is not a epub"
      exit -1
    elif [ "${#FOUND_EPUBS[@]}" -gt 1 ]; then
      echo
      echo "$path matches multiple documents!"
      while true; do
        echo
        for (( i=0; i<${#FOUND_EPUBS[@]}; i++ )); do
          echo -e "$(expr $i + 1). ${FOUND_EPUBS[$i]} - Last modified: $(date -d @"$(expr "$(ssh root@"$SSH_ADDRESS" "grep '\"lastModified\": \".*\"' /home/root/.local/share/remarkable/xochitl/$uuid.metadata" | grep -oP '[0-9]*')" / 1000)" '+%Y-%m-%d %H:%M:%S')"
        done

        echo
        read -r -p "Select one or more documents to be downloaded [ie. 1, 1 2 3 or 1-3]: " input

        # Input is a range
        if [[ "$input" =~ ^([1-9][0-9]*)\ *\-\ *([1-9][0-9]*)\ *$ ]]; then
          start=${BASH_REMATCH[1]}
          end=${BASH_REMATCH[2]}
          if [ "$start" -gt $i ] || [ "$end" -gt $i ] || [ "$start" -gt "$end" ]; then
            echo
            echo "Invalid order or index out of range"
            continue
          fi

          for (( i=$start-1; i<$end; i++ )); do
            RESET_EPUBS+=("${FOUND_EPUBS[i]}")
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
            for j in $input; do
              ((j--)) # Decrement itterator to match array index
              RESET_EPUBS+=("${FOUND_EPUBS[j]}")
            done
            break
          fi
        fi
      done
    else
      RESET_EPUBS+=("$FOUND_EPUBS")
    fi
  fi
done

echo "Resetting epub(s)..."

for uuid in "${RESET_EPUBS[@]}"; do
  if [ "$(ssh root@"$SSH_ADDRESS" "if [ -f /home/root/.local/share/remarkable/xochitl/$uuid.content ]; then echo 1; fi")" ]; then
    ssh root@"$SSH_ADDRESS" "rm -rf /home/root/.local/share/remarkable/xochitl/$uuid.cache; echo '$INIT_CONTENT' > /home/root/.local/share/remarkable/xochitl/$uuid.content" # Delete cache and override .content with initial values
  else
    echo "Failed to find content file for '$uuid'"
  fi
done

echo "Applying changes..."
ssh root@"$SSH_ADDRESS" "systemctl restart xochitl"

echo "Done"
