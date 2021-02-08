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

ssh_cmd() {
    ssh root@$ADDRESS $SSH_OPT "$@"
}

rm_version="$(ssh_cmd cat /sys/devices/soc0/machine)"

case "$rm_version" in
    "reMarkable 1.0")
        pixel_format="gray16le"
        video_filters=""
        width=1408
        height=1872
        dump_framebuffer_cmd='cat /dev/fb0'
        ;;
    "reMarkable 2.0")
        pixel_format="gray8"
        video_filters="-vf transpose=2"
        width=1872
        height=1404
        # see https://github.com/rien/reStream/issues/28
        dump_framebuffer_cmd=$(cat << "EOF"
pid=$(pidof xochitl);
offset=$(grep "/dev/fb0" /proc/$pid/maps | awk -F '-' '{print substr($2, 0, 8)}');
dd if=/proc/$pid/mem bs=1 count=2628288 skip=$((0x$offset + 8)) 2>/dev/null
EOF
)
        ;;
    *)
        echo "Unsupported reMarkable version: $rm_version."
        exit 1
        ;;
esac

grab_framebuffer() {
    ssh_cmd "$dump_framebuffer_cmd"
}

grab_framebuffer | ffmpeg \
       -loglevel panic \
       -vcodec rawvideo \
       -f rawvideo \
       -pixel_format "$pixel_format" \
       -s "$width","$height" \
       -i - \
       -vframes 1 \
       -f image2 \
       $video_filters \
       -vcodec mjpeg $OUTPUT

if [ ! -f "$OUTPUT" ]; then
  echo "resnap: Error: Failed to capture screenshot"
  exit 1
fi
