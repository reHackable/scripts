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
# Author        : Evan Widloski <evan@evanw.org>, Patrick Pedersen <ctx.xda@gmail.com>
#
# Description   : Host sided script for screenshotting the current reMarkable display
#
# Dependencies  : FFmpeg, ssh
#
# Thanks to https://github.com/canselcik/libremarkable/wiki/Framebuffer-Overview

# Current version (MAJOR.MINOR)
VERSION="1.0"

# Usage
function usage {
  echo "Usage: resnap.sh [-h | --help] [-v | --version] [-r ssh_address] [output_jpg]"
  echo
  echo "Arguments:"
  echo -e "output_jpg\tFile to save screenshot to (default resnap.jpg)"
  echo -e "-v --version\tDisplay version and exit"
  echo -e "-i\t\tpath to ssh pubkey"
  echo -e "-r\t\tAddress of reMarkable (default 10.11.99.1)"
  echo -e "-h --help\tDisplay usage and exit"
  echo
}

# default ssh address
ADDRESS=10.11.99.1

# default output file
OUTPUT=resnap.jpg

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
      echo "resnap: Error: Unsupported flag $1" >&2
      usage
      exit 1
      ;;
    *) # preserve positional arguments
      OUTPUT=$1
      shift
      ;;
  esac
done

# check if ffmpeg installed
hash ffmpeg > /dev/null
if [ $? -eq 1 ]
then
    echo "resnap: Error: Command 'ffmpeg' not found. FFmpeg not installed"
    exit 1
fi

# Check if output file already exists
if [ -f $OUTPUT ]; then
  extension=$([[ "$OUTPUT" = *.* ]] && echo ".${OUTPUT##*.}" || echo '')
  filename="${OUTPUT%.*}"
  index="$(ls "$filename"*"$extension" | grep -P "$filename(-[0-9]*)?$extension" | wc -l)";
  OUTPUT="$filename-$index$extension"
fi

# grab framebuffer from reMarkable
ssh root@$ADDRESS $SSH_OPT "cat /dev/fb0" | \
  ffmpeg -vcodec rawvideo \
       -loglevel panic \
       -f rawvideo \
       -pix_fmt gray16le \
       -s 1408,1872 \
       -i - \
       -vframes 1 \
       -f image2 \
       -vcodec mjpeg $OUTPUT

if [ ! -f "$OUTPUT" ]; then
  echo "resnap: Error: Failed to capture screenshot"
  exit 1
fi
