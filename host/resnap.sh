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
# Author        : Evan Widloski <evan@evanw.org>,
#
# Description   : Host sided script for screenshotting the current reMarkable display
#
# Dependencies  : pv, ssh, convert (imagemagick)
#
# Thanks to https://github.com/canselcik/libremarkable/wiki/Framebuffer-Overview


# Current version (MAJOR.MINOR)
VERSION="1.0"

# Usage
function usage {
  echo "Usage: resnap.sh [-h | --help] [-v | --version] [-r ssh_address] [output_file]"
  echo
  echo "Arguments:"
  echo -e "output_file\tFile to save screenshot (default resnap.png)"
  echo -e "-v --version\tDisplay version and exit"
  echo -e "-i\tpath to ssh pubkey"
  echo -e "-r\t\tAddress of reMarkable (default 10.11.99.1)"
  echo -e "-h --help\tDisplay usage and exit"
  echo
}

# default ssh address
ADDRESS=10.11.99.1
# default output file
OUTPUT=resnap.png

PARAMS=""
while (( "$#" )); do
  case "$1" in
    -r)
      ADDRESS=$2
      shift 2
      ;;
    -i)
        SSH_OPT="-i $2"
        shift 2
        ;;
    -h|--help)
        shift 1
        usage
        exit 1
        ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      usage
      exit 1
      ;;
    *) # preserve positional arguments
      OUTPUT=$1
      shift
      ;;
  esac
done

# check if imagemagick installed
hash convert > /dev/null
if [ $? -eq 1 ]
then
    echo "Error: Command 'convert' not found.  imagemagick not installed"
    exit 1
fi

# grab framebuffer from reMarkable
ssh root@$ADDRESS $SSH_OPT "cat /dev/fb0" | pv -W -s 10800000 | \
    convert -depth 16 -size 1408x1872+0 gray:- png:/tmp/resnap.png

# convert generates 3 images for some reason, copy the first to the destination
if [ -f /tmp/resnap-0.png ]
then
    cp /tmp/resnap-0.png "$OUTPUT"
    rm /tmp/resnap-*.png
fi
