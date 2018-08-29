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

# Description   : Host sided script that gets rid of junk such as deleted document metadata
#                 aswell as documents with no metadata assigned

# Dependencies  : ssh, nc

# Notations     : This script may conflict with the cloud as it ignores the original purpose of the "deleted" attribute
#                 in metadata files. Upon conflict, the device will re-download the deleted document from the cloud as soon
#                 as connection can be established. That is, unless the file wasn't uploaded to the cloud in first place.

#                 To make it clear, this script is mainly intended for users that rarely use wifi on their device or users that
#                 frequently manually remove or add entries to the filesystem

SSH_ADDRESS="10.11.99.1"

function usage {
  echo "Usage: reclean.sh [-h | ssh address]"
  echo
  echo "Options:"
  echo -e "-h\t\t\tDisplay script usage"
  echo -e "ip\t\t\tSSH address of the device (default set to 10.11.99.1)"
}

# Check Arguments
if [ "$#" -gt 1 ] || [[ "$1" == "-h" ]]; then
  usage
  exit -1
elif [ "$#" -eq 1 ]; then
  SSH_ADDRESS="$1"
fi

echo "Attempting to establish connection with the device..."
ssh -q root@"$SSH_ADDRESS" exit

if [ "$?" -ne 0 ]; then
  echo "Failed to establish connection!"
  exit -1
fi

echo "Successfully established connection, please do not lock your device until the script has completed!"

read -rp "Search for metadata from deleted documents [y/N]: " input

# Deleted attribute set to "true"
if [[ "$input" =~ [yY] ]]; then
  echo
  echo "Note: Documents previously pushed to the cloud will be re-downloaded as soon as connection is established"
  echo
  echo "Searching for deleted files..."
  uuid=($(ssh root@"$SSH_ADDRESS" "grep -ol '\"deleted\": true' ~/.local/share/remarkable/xochitl/*metadata"))

  if [ "$uuid" ]; then
    echo
    echo "The following deleted documents have been found: "
    echo

    for f in "${uuid[@]}"; do
      echo "    $f"
    done

    echo

    proceed=""

    while [[ ! "$proceed" =~ [YyNn] ]]; do
      read -rp "Proceed: [y/n]: " proceed

      if [[ "$proceed" =~ [Yy] ]]; then
        echo "Deleting files..."
        ssh root@"$SSH_ADDRESS" "rm -R $(echo "${uuid[@]}" | sed -E "s/([a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*).[^ ]*/\1\*/g")"
      fi
    done
  else
    echo
    echo "No deleted documents found, nothing to clean here..."
    echo
  fi
fi

read -rp "Search for files and directories without metadata [y/N]: " input

# Files or directories with missing metadata
if [[ "$input" =~ [yY] ]]; then
  echo "Searching for junk..."
  assigned=($(ssh root@"$SSH_ADDRESS" "find ~/.local/share/remarkable/xochitl/ -name *.metadata" | grep -o '[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*'))
  unassigned=($(ssh root@"$SSH_ADDRESS" "find ~/.local/share/remarkable/xochitl/ ! -name *.metadata" | grep -o '[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*\-[a-z0-9]*' | uniq))

  # Compare uuid of metadata files with uuid of all files not ending with .metadata
  # This way the file with missing a missing metadata file will stand out
  uuid=($(echo "${assigned[@]}" "${unassigned[@]}" | tr ' ' '\n' | sort | uniq -u))
  uuid=(${uuid[@]/#/"~/.local/share/remarkable/xochitl/"})
  uuid=(${uuid[@]/%/"*"})

  if [ "$uuid" ]; then
    echo
    echo "The following documents have been found: "
    echo

    for f in "${uuid[@]}"; do
      echo "    $f"
    done

    echo

    proceed=""

    while [[ ! "$proceed" =~ [YyNn] ]]; do
      read -rp "Proceed: [y/n]: " proceed
      if [[ "$proceed" =~ [Yy] ]]; then
        echo "Deleting files..."
        ssh root@"$SSH_ADDRESS" "rm -R $(echo "${uuid[@]}")"
      fi
    done
  else
    echo
    echo "No deleted documents found, nothing to clean here..."
    echo
  fi
fi
