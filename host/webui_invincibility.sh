#!/usr/bin/env bash

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Author        : Patrick Pedersen <ctx.xda@gmail.com>
#                 Part of the reHackable organization <https://github.com/reHackable>

# Description   : Pulls and patches the xochitl binary to prevent the WebUI from disabling on boot.

#                 NOTE: DO NOT ATTEMPT TO USE THIS SCRIPT ON A XOCHITL BINARY OTHER THAN FOR
#                       SOFTWARE VERSION 1.7.2.3!
#
#                       You can find patches for older xochitl versions here:
#                        - 1.7.0.1: https://gist.github.com/CTXz/4adc40b96465ee64542d14581dae18a4
#                        - 1.7.1.3: https://github.com/reHackable/scripts/blob/ac71d094b4212df1680124688ec001f212ab2bd6/host/webui_invincibility.sh

#                 NOTE: This script patches the xochitl binary to prevent the device from disabling
#                       the Web UI. Unfortuantely, this patch also blocks the WebUI settings switch
#                       after it has been turned on. The only way to disable the Web UI again is to
#                       change "WebInterfaceEnabled" to "false" in "/.config/remarkable/xochitl.conf"
#                       and then restart the device (or the xochitl service)

# Dependencies  : ssh, bspatch

# Technical description:

#                 The following script patches a function in the xochitl binary located at offset 0x001bde90,
#                 which from my limited understanding sets the WebUI state, as well as the WebUI settings switch
#                 and the WebInterfaceEnabled property in /.config/remarkable/xochitl.conf. The function
#                 seems to take a single boolean parameter which dictates the state of the WebUI.  For the
#                 sake of convenience, lets define this function as setWebUI(bool state). The pseudo code for
#                 setWebUI can be simplified to something close to this:

#                 function setWebUI(bool state)
#                 {
#                   if (getWebInterfaceEnabledProperty() == state) // <- Patcher alters this condition
#                   {
#                     return ...
#                   }
#
#                   setWebInterfaceEnabledProperty(state);
#                   .
#                   .
#                   .
#                   if (getWebInterfaceEnabledProperty() == false)
#                   {
#                     HttpListener.close(); // Disables WebUI
#                   }
#                   else
#                   {
#                     if (!HttpListener.isListening())
#                     {
#                       HttpListener.listen(); // Enables WebUI
#                     }
#                   }
#                   setSettingsSwitch(state);
#                 }
#
#                 return ...
#               }

#               Please note that this pseudocode in no way must represent the actual code, and may likely
#               even be wrong given my limited experience in ARM assembly. Nontheless, the only
#               relevant part to this patch is the guard condition at the start of the function,
#               (getWebInterfaceEnabledProperty() == state), which checks whether the web interface
#               has already been set to the targeted state by comparing it to the value of the
#               WebInterfaceEnabled property in /.config/remarkable/xochitl.conf. On every device boot
#               setWebUI is executed with state = false. By rewriting the the condition from
#               (getWebInterfaceEnabledProperty() == state) to (getWebInterfaceEnabledProperty() == true),
#               then setWebUI will prematurely exit the function if getWebInterfaceEnabledProperty() has
#               been set to true, and thus never gets to turn the WebUI off again.

# Current version (MAJOR.MINOR)
VERSION="1.4"

XOCHITL_MD5="3c0010a7b5cad46e94925c07bb4fd492"
XOCHITL_PATCHED_MD5="6e92e0fe4e5e600fd8be04f316fd0e01"
SSH_ADDRESS="10.11.99.1"

function usage {
  echo "Usage: webui_invincibility.sh [-v] [-h] [-u backup] [-r ip]"
  echo
  echo "Options:"
  echo -e "-v\t\t\tDisplay version and exit"
  echo -e "-h\t\t\tDisplay usage and exit"
  echo -e "-u\t\t\tUndo patches"
  echo -e "-r\t\t\tPatch remotely via ssh tunneling"
}

function patch_xochitl {
echo "$(cat <<- 'EOF'
00000000: 4253 4449 4646 3430 3c00 0000 0000 0000  BSDIFF40<.......
00000010: 3c00 0000 0000 0000 7ceb 4100 0000 0000  <.......|.A.....
00000020: 425a 6839 3141 5926 5359 9276 c321 0000  BZh91AY&SY.v.!..
00000030: 0654 d1c0 2001 0020 0000 0440 0000 0400  .T.. .. ...@....
00000040: 0800 8020 0021 a321 9083 2620 a200 91ae  ... .!.!..& ....
00000050: 73c5 dc91 4e14 2424 9db0 c840 425a 6839  s...N.$$...@BZh9
00000060: 3141 5926 5359 6fbf 07ca 001b 0ec0 06d0  1AY&SYo.........
00000070: 0001 0001 0000 0c20 0050 6001 4a8d 34f4  ....... .P`.J.4.
00000080: a829 672a 80b3 1521 06f0 a128 5bf1 7724  .)g*...!...([.w$
00000090: 5385 0906 fbf0 7ca0 425a 6839 1772 4538  S.....|.BZh9.rE8
000000a0: 5090 0000 0000                           P.....                             ....
EOF
)" | xxd -r > "/tmp/webui_invincibility.patch"

  if [ ! -f "/tmp/webui_invincibility.patch" ]; then
    echo "webui_invincibility: Failed to create patchfile!"
    return 1
  fi

  bspatch "$1" "$2" "/tmp/webui_invincibility.patch"
  rm "/tmp/webui_invincibility.patch"

  md5=($(md5sum "$2"))

  if [[ ! -f "$2" || $? != '0' || "$md5" != "$XOCHITL_PATCHED_MD5" ]]; then
    echo "webui_invincibility: Failed to patch the xochitl binary"
    return 2
  fi

  return 0
}

if [ ! ssh -v >/dev/null 2>&1 ]; then
  echo "webui_invincibility: SSH not installed"
  exit 1
fi

if [ ! bspatch >/dev/null 2>&1 ]; then
  echo "webui_invincibility: bspatch not installed"
  exit 1
fi

# Evaluate Options/Parameters
while getopts ":vhdu:r:" opt; do
  case "$opt" in
    h) # Usage help
      usage
      exit 1
      ;;

    v) # Version
      echo "webui_invincibility version: $VERSION"
      exit 1
      ;;

    u)
      xochitl_backup="$OPTARG"
      UNDO=1
      ;;

    r) # Push Remotely
      SSH_ADDRESS="$OPTARG"
      REMOTE=1
      ;;

    ?) # Unknown Option
      echo "webui_invincibility: Invalid option or missing arguments: -$OPTARG"
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))

if [ "$UNDO" ]; then
  if [ ! -f "$xochitl_backup" ]; then
    echo "webui_invincibility: No such file: $xochitl_backup"
  fi

  backup_md5=($(md5sum "$xochitl_backup"))

  if [[ "$backup_md5" != "$XOCHITL_MD5" ]]; then
    echo "webui_invincibility: Backup xochitl binary is incorrect or corrupted"
    echo "webui_invincibility: You can obtain a xochitl backup for OS ver 1.7.2.3 here: https://drive.google.com/open?id=1nGpQt6Plugkwf9U-Gh7TI_aXmmeVfr_M"
    exit 1
  fi
fi

# Establish remote connection
if [ "$REMOTE" ]; then
  ssh -q root@"$SSH_ADDRESS" exit

  if [ "$?" -ne 0 ]; then
    echo "webui_invincibility: Failed to establish connection!"
    exit -1
  fi
fi

if [ -z "$UNDO" ]; then
  echo
  echo "=========================================================================="
  echo "                              DISCLAIMER 1                                "
  echo ""
  echo 'THIS SCRIPT PATCHES THE XOCHITL BINARY TO BLOCK THE DEVICE FROM DISABLING '
  echo 'THE WEB UI. UNFORTUANTELY, THIS PATCH ALSO FREEZES THE WEBUI SWITCH IN THE'
  echo 'DEVICE SETTINGS ONCE THE WEBUI HAS BEEN TURNED ON. THE ONLY WAY TO DISABLE'
  echo 'THE WEBUI AGAIN IS TO CHANGE "WebInterfaceEnabled" TO "false" IN'
  echo '"/.config/remarkable/xochitl.conf" AND THEN RESTART THE DEVICE (OR THE XO-'
  echo 'CHITL SERVICE)'
  echo "=========================================================================="
fi

echo
echo "=========================================================================="
echo "                              DISCLAIMER 2                                "
echo ""
echo "THIS SCRIPT WILL OVERRIDE THE XOCHITL BINARY. PLEASE ENSURE THE DEVICE IS "
echo "UNLOCKED AND REMAINS CONNECTED UNTIL THE SCRIPT HAS COMPLETED! ONLY PRO-  "
echo "CEED IF THE DEVICE IS UNLOCKED AND PROPERLY CONNECTED!"
echo "=========================================================================="
echo

read -p "HIT ENTER TO PROCEED "

if [ "$UNDO" ]; then
  ssh root@"$SSH_ADDRESS" "systemctl stop xochitl"
  scp "$xochitl_backup" root@"$SSH_ADDRESS":"/usr/bin/xochitl"
  if [[ $? != 0 ]]; then
    echo "webui_invincibility: Failed to push xochitl backup!"
    exit 1
  fi

  md5=($(ssh root@"$SSH_ADDRESS" "md5sum /usr/bin/xochitl"))

  if [[ "$md5" != "$XOCHITL_MD5" ]]; then
    echo "webui_invincibility: MD5 check failed, please try again!"
    exit 1
  fi

  ssh root@"$SSH_ADDRESS" "systemctl restart xochitl"
  echo "webui_invincibility: Patches Successfully undone!"
  exit 0
fi

scp root@"$SSH_ADDRESS":"/usr/bin/xochitl" "./xochitl_BACKUP"

if [[ $? != 0 ||  ! -f ./xochitl_BACKUP ]]; then
  echo "webui_invincibility: Failed to copy xochitl from the device"
  exit 1
fi


md5=($(md5sum "./xochitl_BACKUP"))

if [[ "$md5" != "$XOCHITL_MD5" ]]; then
  echo "webui_invincibility: The device is running a incompatible xochtil version or xochitl has already been patched!"
  rm "./xochitl_BACKUP"
  exit 1
fi

echo "webui_invincibility: Backup created at './xochitl_BACKUP'. DO NOT LOSE THIS BACKUP! YOU WILL NEED IT IF YOU WISH TO UNDO THE PATCHES AGAIN!"

echo "webui_invincibility: Patching xochitl..."
patch_xochitl "./xochitl_BACKUP" "/tmp/xochitl_patched"

if [[ "$?" != 0 ]]; then
  echo "webui_invincibility: No changes have been made"
  exit 1
fi

echo "webui_invincibility: xochitl patched!"
echo "webui_invincibility: Applying patches... DO NOT DISCONNECT OR LOCK YOUR DEVICE!"

ssh root@"$SSH_ADDRESS" "systemctl stop xochitl"
scp "/tmp/xochitl_patched" root@"$SSH_ADDRESS":"/usr/bin/xochitl"
rm "/tmp/xochitl_patched"

if [[ $? != 0 ]]; then
  echo "webui_invincibility: Failed to apply xochitl patches! Please try again!"
  exit 1
fi

md5=($(ssh root@"$SSH_ADDRESS" "md5sum /usr/bin/xochitl"))

if [[ "$md5" != "$XOCHITL_PATCHED_MD5" ]]; then
  echo "webui_invincibility: The transfered xochitl binary appears to be corrupted! Please undo the patches (run the patch with -u) and try again!"
  exit 1
fi

ssh root@"$SSH_ADDRESS" "systemctl restart xochitl"
echo "webui_invincibility: Successfully patched xochitl!"
