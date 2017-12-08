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

# Description   : Host sided script that can change the timezone on your reMarkable
#                 according to the host or a specified timezone.

# Dependencies  : ssh, nc

# Notations     : I started reading a book about the regex language (Mastering Regular Expressions by Jeffrey E.F. Friedl).
#                 How did I manage to come this far in life without regular expressions!!!

# Usage
function usage {
  echo "Usage: rezone.sh [SSH | -h | -help | --help]"
  echo
  echo "Arguments:"
  echo -e "SSH\t\t\tDevices SSH address (default 10.11.99.1)"
  echo -e "-h -help --help\t\tDisplays script usage (this)"
  echo
}

# Can be overwritten by $1
SSH_ADDR=10.11.99.1

# Disable case sensivity on regex
shopt -s nocasematch

# Check for -h / --help
if [[ $1 =~ --help|-h(elp)? ]]; then
  usage
  exit 1
fi

# Check if too many parameters have been provided
if [[ $# > 1 ]]; then
  echo "Too many arguments provided"
  echo
  usage
  exit -1
fi

# Check and assign optional SSH argument
if [ ! -z $1 ]; then
  if [ -z $(echo $1 | grep -oP '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$') ]; then
    echo "Invalid SSH address provided"
    exit -1
  fi

  SSH_ADDR=$1
fi

LOCAL_TZ=$(date +%Z)

echo
echo '= reZone ='
echo '----------'
echo 'See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones for possible timezones'
read -p "Set timezone to ($LOCAL_TZ): " TZ
echo

# Check input
if [ -z $TZ ]; then

  # Use host TZ
  if [[ $LOCAL_TZ != "" ]]; then
    TZ=$LOCAL_TZ

  # No input or host TZ specified
  else
    echo "Timezone undefined!"
    exit -1
  fi
fi


echo "Selected $TZ"
echo "Attempting to establish connection with $SSH_ADDR"

# Run
while [[ $input != 'n' ]]; do

  # Check connection to device
  if nc -z -w 1 $SSH_ADDR 22 > /dev/null; then

    # Replace TZ assignment with new timezone in /etc/profile line 9
    if [[ $(ssh root@$SSH_ADDR -C "sed -E -i 's/(TZ=)(\"[^\"]*\")/\1\"$TZ\"/' /etc/profile; cat /etc/profile | grep -o 'TZ=\"$TZ\"'") == "" ]]; then
      echo "Failed to permanently set timezone to $TZ"
      echo "On your reMarkable, please inspect line 9 in /etc/profile and manually change the timezone from there"
    else
      echo "Successfuly updated timezone to $TZ"
    fi

    exit 1

  # Connection failed
  else
    read -p "Failed establish connection with $SSH_ADDR. Retry? [Y/n]: " input
  fi
done
