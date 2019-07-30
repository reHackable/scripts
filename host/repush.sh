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

# Description   : Host sided script that can push one or more files to the reMarkable
#                 using the Web client and SSH

# Dependencies  : cURL, ssh, nc

# Usage         : https://github.com/reHackable/scripts/wiki/repush.sh

# Current version (MAJOR.MINOR)
VERSION="3.0"

# Local
SSH_ADDRESS="10.11.99.1"
WEBUI_ADDRESS="10.11.99.1:80"

# Remote
PORT=9000 # Deault port to which the webui is tunneled to

shopt -s nullglob # Needed when globbing empty directories

function usage {
  echo "Usage: repush.sh [-v] [-h] [-o output] [-d] [-r ip] [-p port] doc1 [doc2 ...]"
  echo
  echo "Options:"
  echo -e "-v\t\t\tDisplay version and exit"
  echo -e "-h\t\t\tDisplay usage and exit"
  echo -e "-o\t\t\tOutput directory to which the provided files will be uploaded to"
  echo -e "-d\t\t\tDelete file after successful push"
  echo -e "-r\t\t\tPush remotely via ssh tunneling"
  echo -e "-p\t\t\tIf -r has been given, this option defines the port to which the webui will be tunneled (default 9000)"
}

## Placeholders ##
# To understand why we make placeholders, please see: https://github.com/reHackable/scripts/commit/67b15a3dc448a954813f420fa050c9be56ac8550

# Create a blank placeholder PDF
# Based on: https://github.com/mathiasbynens/small/blob/master/pdf.pdf

# $1 - Output directory
function create_placeholder_pdf {
  echo "%PDF-1." > "$1"
  echo "1 0 obj<</Pages 2 0 R>>endobj" >> "$1"
  echo "2 0 obj<</Kids[3 0 R]/Count 1>>endobj" >> "$1"
  echo "3 0 obj<</Parent 2 0 R>>endobj" >> "$1"
  echo -n "trailer <</Root 1 0 R>>" >> "$1"
}

# Create a blank placeholder EPUB
# This could certainly be made smaller but I'm a bit too lazy to
# understand the EPUB file format. PR's are welcome ;)

# $1 - Output directory
function create_placeholder_epub {

echo "$(cat <<- 'EOF'
00000000: 504b 0304 1400 1608 0000 a173 b74e 6f61  PK.........s.Noa
00000010: ab2c 1400 0000 1400 0000 0800 0000 6d69  .,............mi
00000020: 6d65 7479 7065 6170 706c 6963 6174 696f  metypeapplicatio
00000030: 6e2f 6570 7562 2b7a 6970 504b 0304 1400  n/epub+zipPK....
00000040: 1608 0800 8a73 b74e fdea 87dc 0f01 0000  .....s.N........
00000050: e501 0000 0700 0000 746f 632e 6e63 788d  ........toc.ncx.
00000060: 91bf 6e83 400c 87f7 3cc5 e916 da01 8e7f  ..n.@...<.......
00000070: 4993 e820 43e7 561d da07 3077 0e41 055f  I.. C.V...0w.A._
00000080: 444c a07d fa42 9456 0c8d 94cd b6be df67  DL.}.B.V.......g
00000090: c9d6 bba1 a9c5 19db 53e5 28f3 a220 f404  ........S.(.. ..
000000a0: 9271 b6a2 32f3 3ade fb6b 6f97 2f34 9941  .q..2.:..ko./4.A
000000b0: 8c24 9d32 7960 3e6e 95ea fb3e b050 9dbe  .$.2y`>n...>.P..
000000c0: 02d7 96ea 3bd9 ac57 2a0e c3a5 1a51 25ff  ....;..W*....Q%.
000000d0: 9472 9af9 919c d2db 1a46 ab44 92f9 4208  .r.......F.D..B.
000000e0: 7d40 b053 3196 0d32 08e3 8891 3893 4914  }@.S1..2....8.I.
000000f0: efd3 cdc6 f86b c4d8 4ff7 69e2 43f1 14fa  .....k..O.i.C...
00000100: e3d0 c00a 7099 da42 0a82 0633 69b9 d876  ....p..B...3i..v
00000110: 9595 ea5f 5334 c72c 1ef9 7003 3450 5745  ..._S4.,..p.4PWE
00000120: 8be2 2109 e2f1 088f f35c 8984 2db0 6b6f  ..!......\..-.ko
00000130: 64c3 39cc 8ea1 7e83 129f 5d47 7c4f a281  d.9...~...]G|O..
00000140: 61e2 5fbb a6c0 eb0a ad7e 6fa3 ad33 ef15  a._......~o..3..
00000150: d778 f530 0e9c 7fd0 27b9 9eb4 ba74 177e  .x.0....'....t.~
00000160: 8e69 82f3 0b1c 4793 9e9e 912f 7e00 504b  .i....G..../~.PK
00000170: 0304 1400 1608 0800 8f73 b74e d530 8a3e  .........s.N.0.>
00000180: 4c02 0000 2005 0000 0b00 0000 636f 6e74  L... .......cont
00000190: 656e 742e 6f70 669d 54d1 6e9b 3014 7def  ent.opf.T.n.0.}.
000001a0: 5758 bc64 5365 6c48 ba36 88d0 1fd8 9ed6  WX.dSelH.6......
000001b0: 4993 a6a9 32f6 85b8 019b 8169 d2bf df0d  I...2......i....
000001c0: a640 b44c 9326 f9c1 36e7 9e73 ef3d d7a4  .@.L.&..6..s.=..
000001d0: 8fa7 ba22 afd0 76da 9add 2a0a f98a 8091  ..."..v...*.....
000001e0: 5669 53ee 56bd 2be8 c3ea 31bb 491b 210f  ViS.V.+...1.I.!.
000001f0: a204 8268 d3ed 82bd 734d c2d8 f178 0cb5  ...h....sM...x..
00000200: 6a8a d0b6 258b 39bf 67b6 2902 d21b fdab  j...%.9.g.).....
00000210: 07aa 1518 a70b 0ded 2ee8 7bad 9eb5 0a26  ..........{....&
00000220: a920 0e79 90dd 1092 d6e0 8412 4e78 ee44  . .y........Nx.D
00000230: 8a4a e72d 4c1a e339 3cd8 57ad 4afb 26aa  .J.-L..9<.W.J.&.
00000240: d080 3bab 6dd9 7b68 30c6 2a39 8535 7d5b  ..;.m.{h0.*9.5}[
00000250: 0d69 29c9 a082 1a53 e958 1446 6cc6 3a68  .i)....S.X.Fl.:h
00000260: ebee 6ac0 f065 4262 4dff aad8 034f 9dbe  ..j..eBbM....O..
00000270: 001e d7ef b088 7dff f2f9 abdc 432d a836  ......}.....C-.6
00000280: 9d13 46c2 503d d6af 6452 0953 f6d8 de0c  ..F.P=..dR.S....
00000290: 4cca 96e7 0921 5b10 ceb6 04d5 92d6 56d8  L....![.......V.
000002a0: 1ed1 bb20 fb66 0ec6 1e7d d008 1963 cead  ... .f...}...c..
000002b0: 2146 d488 1c3b 9838 5d03 4ad7 4d40 a435  !F...;.8].J.M@.5
000002c0: 0e3b 822e f068 4bf9 1d8d d74f 519c c43c  .;...hK....OQ..<
000002d0: 89e3 f07e 13c7 770f b79c 279c 076c cec1  ...~..w...'..l..
000002e0: 6957 c185 a4bf f953 d0a2 cb0b 117f 5e30  iW.....S......^0
000002f0: a167 90f1 8847 7458 4f83 142e af39 500f  .g...GtXO....9P.
00000300: 90b9 7ca4 6a75 de5f b620 3f34 4136 5647  ..|.ju._. ?4A6VG
00000310: 3eac c318 c7f7 23f9 7176 a09b 2787 426e  >.....#.qv..'.Bn
00000320: ed21 94b6 fee9 fb34 73cd 02f3 ac12 ad16  .!.....4s.......
00000330: e37a 16eb cebe 81bf 0cb2 7514 179b ed56  .z........u....V
00000340: d207 8098 6e8a cd9a 8afc 9e53 bc94 e293  ....n......S....
00000350: 80bb 8dca 079d 99f2 aacc 9279 ccf4 bfc9  ...........y....
00000360: d3e9 25f8 1725 8c2e d0ea 5157 3ba8 c9be  ..%..%....QW;...
00000370: 8562 74e2 59d7 385b e14b 5306 43b1 a35d  .bt.Y.8[.KS.C..]
00000380: 3528 2da8 7b6b 30a1 01c1 5e1a 2827 db16  5(-.{k0...^.('..
00000390: 2cda 2838 857b 5757 9e40 abf8 325c 344d  ,.(8.{WW.@..2\4M
000003a0: a5a5 70f8 d0d9 e98c bbc5 0772 8dc9 5919  ..p........r..Y.
000003b0: 1a79 f234 c3e6 af34 54b9 1c11 3313 16bd  .y.4...4T...3...
000003c0: a833 ed1a 6d80 20a1 275a 68a1 12f2 fbcc  .3..m. .'Zh.....
000003d0: 31d3 3178 c00f db12 7df5 3b36 6e53 36fe  1.1x....}.;6nS6.
000003e0: efb2 df50 4b03 0414 0016 0808 00b1 72b7  ...PK.........r.
000003f0: 4e70 0037 77f9 0000 00a2 0100 000a 0000  Np.7w...........
00000400: 0069 6e64 6578 2e68 746d 6c8d 9031 72c3  .index.html..1r.
00000410: 2010 45eb e814 0c8d 2a89 78d2 440e e022   .E.....*.x.D.."
00000420: 5748 6a0f 426b 8911 0619 d696 74fb 8015  WHj.Bk......t...
00000430: 675c a6db bfbc bf9f 5d7e 58ce 96dc 2044  g\......]~X... D
00000440: e39d 2877 f56b 49c0 69df 19d7 8bf2 8aa7  ..(w.kI.i.......
00000450: eabd 3cc8 820f 98b0 84ba 28e8 8038 ed19  ..<.......(..8..
00000460: 9be7 b99e df6a 1f7a b66b 9a86 2d99 a1c4  .....j.z.k..-...
00000470: aae4 a4e0 68c6 f77f 4a16 84f0 0154 978b  ....h...J....T..
00000480: 54a2 410b f2db 8dce cf8e b34d 6e4f 6740  T.A........MnOg@
00000490: 4572 4805 97ab b909 fae9 1d82 c3ea 6b9d  ErH...........k.
000004a0: 8012 bd29 4111 1664 39f4 83e8 4185 0828  ...)A..d9...A..(
000004b0: ee1f a6ec 1e66 8d1b c910 e024 68c4 d542  .....f.....$h..B
000004c0: 1c00 b0d6 3152 12c0 3e37 29c1 34f9 7760  ....1R..>7).4.w`
000004d0: 06d2 8067 fba4 7a38 6ef8 fffd ecb1 2c6f  ...g..z8n.....,o
000004e0: 7db7 126d 554c b7d3 ca9a 3640 3ac7 0b9f  }..mUL....6@:...
000004f0: 1ecd d67a 3d1e a9e4 6c92 4572 6643 1279  ...z=...l.ErfC.y
00000500: 3559 fc00 504b 0304 1400 1608 0800 b172  5Y..PK.........r
00000510: b74e 909f 0674 9a00 0000 f400 0000 1600  .N...t..........
00000520: 0000 4d45 5441 2d49 4e46 2f63 6f6e 7461  ..META-INF/conta
00000530: 696e 6572 2e78 6d6c 558e c10e c220 1044  iner.xmlU.... .D
00000540: ef7e 05d9 ab69 d12b 81f6 5b56 ba55 22b0  .~...i.+..[V.U".
00000550: 04a8 d1bf 176b 6cea 7167 67e6 8d1e 9fc1  .....kl.qgg.....
00000560: 8b07 e5e2 381a 38f7 2718 8783 b61c 2bba  ....8.8.'.....+.
00000570: 48f9 ff25 9a39 1603 4b8e 8ab1 b8a2 2206  H..%.9..K.....".
00000580: 2aaa 5ac5 89e2 c476 0914 ab5a 6d6a 2b81  *.Z....v...Zmj+.
00000590: e120 84d0 99b9 cece 5359 cfbd 22e6 c5fb  . ......SY.."...
000005a0: 2e61 bd19 f8a4 5a47 cf69 0611 6872 d8d5  .a....ZG.i..hr..
000005b0: 5722 0398 9277 166b 5b23 992e a9b4 80bd  W"...w.k[#......
000005c0: e395 8e0d 07f2 57ba a2e4 8ea5 e536 e4eb  ......W......6..
000005d0: 7903 504b 0304 1400 0008 0800 aa73 b74e  y.PK.........s.N
000005e0: a6cc abcf 2b00 0000 3000 0000 1e00 0000  ....+...0.......
000005f0: 4d45 5441 2d49 4e46 2f63 616c 6962 7265  META-INF/calibre
00000600: 5f62 6f6f 6b6d 6172 6b73 2e74 7874 4b4e  _bookmarks.txtKN
00000610: ccc9 4c2a 4a8d 4f2e 2d2a 4acd 2b89 2f48  ..L*J.O.-*J.+./H
00000620: 4c4f 8d4f cacf cfce 4d2c cad6 aa51 acb1  LO.O....M,...Q..
00000630: afd1 3280 d17a 065c 0050 4b01 0214 0314  ..2..z.\.PK.....
00000640: 0016 0800 00a1 73b7 4e6f 61ab 2c14 0000  ......s.Noa.,...
00000650: 0014 0000 0008 0000 0000 0000 0000 0000  ................
00000660: 00b4 8100 0000 006d 696d 6574 7970 6550  .......mimetypeP
00000670: 4b01 0214 0314 0016 0808 008a 73b7 4efd  K...........s.N.
00000680: ea87 dc0f 0100 00e5 0100 0007 0000 0000  ................
00000690: 0000 0000 0000 00b4 813a 0000 0074 6f63  .........:...toc
000006a0: 2e6e 6378 504b 0102 1403 1400 1608 0800  .ncxPK..........
000006b0: 8f73 b74e d530 8a3e 4c02 0000 2005 0000  .s.N.0.>L... ...
000006c0: 0b00 0000 0000 0000 0000 0000 b481 6e01  ..............n.
000006d0: 0000 636f 6e74 656e 742e 6f70 6650 4b01  ..content.opfPK.
000006e0: 0214 0314 0016 0808 00b1 72b7 4e70 0037  ..........r.Np.7
000006f0: 77f9 0000 00a2 0100 000a 0000 0000 0000  w...............
00000700: 0000 0000 00b4 81e3 0300 0069 6e64 6578  ...........index
00000710: 2e68 746d 6c50 4b01 0214 0314 0016 0808  .htmlPK.........
00000720: 00b1 72b7 4e90 9f06 749a 0000 00f4 0000  ..r.N...t.......
00000730: 0016 0000 0000 0000 0000 0000 00b4 8104  ................
00000740: 0500 004d 4554 412d 494e 462f 636f 6e74  ...META-INF/cont
00000750: 6169 6e65 722e 786d 6c50 4b01 0214 0314  ainer.xmlPK.....
00000760: 0000 0808 00aa 73b7 4ea6 ccab cf2b 0000  ......s.N....+..
00000770: 0030 0000 001e 0000 0000 0000 0000 0000  .0..............
00000780: 0080 01d2 0500 004d 4554 412d 494e 462f  .......META-INF/
00000790: 6361 6c69 6272 655f 626f 6f6b 6d61 726b  calibre_bookmark
000007a0: 732e 7478 7450 4b05 0600 0000 0006 0006  s.txtPK.........
000007b0: 006c 0100 0039 0600 0000 00              .l...9.....
EOF
)" | xxd -r > "$1"

}

# Grep remote fs (grep on reMarkable)

# $1 - flags
# $2 - regex
# $3 - File(s)

# $RET_MATCH - Match(es)
function rmtgrep {
  escaped_regex="${2//\"/\\\"}"
  RET_MATCH="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "grep -$1 \"$escaped_regex\" $3")"
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

    if [[ "$(($3 + 1))" -eq "${#_PATH[@]}" ]]; then
      RET_FOUND+=("$(basename "$metadata_path" .metadata)")
    else
      find_directory "$(basename "$metadata_path" .metadata)" "$2" "$(( $3 + 1 ))"
    fi

  done
}

# Obtain the UUID for a file located in the root directory

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


# Check file validity

# $1 - File to check

# $? - 1: file valid | 0: file invalid
function check_file {
  file_cmd_output="$(file -F '|' "$1")"

  if echo "$file_cmd_output" | grep -q "| directory"; then
    local is_directory="true"
  fi

  if [ ! -e "$1" ]; then
    echo "repush: No such file or directory: $1"
    return 0
  elif [ -z $is_directory ] && ! echo "$file_cmd_output" | grep -q "| PDF" && ! echo "$file_cmd_output" | grep -q "| EPUB"; then
    echo "repush: Unsupported file format: $1"
    echo "repush: Only PDFs and EPUBs are supported"
    return 0
  elif [ -z $is_directory ] && ! echo "$1" | grep -qP "\.pdf$" && ! echo "$1" | grep -qP "\.epub$" ; then
    echo "repush: File extension invalid or missing: $1"
    return 0
  elif echo "$1" | grep -q '"'; then
    echo "repush: Filename must not contain double quotes: $1"
    return 0
  fi

  return 1
};

# Push files to the device

# $1 - Path to document (Must be EPUB or PDF)
# $2 - UUID of parent directory (empty for root)

# $RET_UUID - The fs UUID of the document
# $? - 1: transfer succeeded | 0: transfer failed
function push {

  ((TOTAL++))
  file_cmd_output="$(file -F '|' "$1")"

  # If file is directory, set extension to PDF for placeholder file
  if echo "$file_cmd_output" | grep -q "| \(PDF\|directory\)"; then
    extension="pdf"
  else
    extension="epub"
  fi

  # If file is directory, set directory to true, so we can distinguish between PDFs and directories
  if echo "$file_cmd_output" | grep -q "| directory"; then
    directory="true"
    DIR_IN_ARG="true"
  else
    directory=""
  fi

  # Create placeholder
  placeholder="/tmp/repush/$(basename "$1")"
  if [ "$directory" ]; then
    placeholder="/tmp/repush/$(basename "$1").pdf"
  fi

  if [[ $extension == "pdf" ]]; then
    create_placeholder_pdf "$placeholder"
  else
    create_placeholder_epub "$placeholder"
  fi


  while true; do
    if curl --connect-timeout 2 --silent --output /dev/null --form file=@"\"$placeholder\"" http://"$WEBUI_ADDRESS"/upload; then

      # Wait for metadata to be generated
      while true; do
        if [ -z "$directory" ]; then
          uuid_of_root_file "$(basename "$1")"
        else
          uuid_of_root_file "$(basename "$1").pdf"
        fi
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


      if [ -z "$directory" ]; then
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
      fi

      # Delete thumbnails (TODO: Replace thumbnail with pre-rendered thumbnail)
      ssh -S remarkable-ssh root@"$SSH_ADDRESS" "rm -f /home/root/.local/share/remarkable/xochitl/$RET_UUID.thumbnails/*"


      # Directory handling
      if [ "$directory" ]; then
        echo repush: Creating directory $(basename $1).

        # Change metadata (type, visibleName, parent)
        ssh -S remarkable-ssh root@"$SSH_ADDRESS" "sed -i 's/\"type\": \"DocumentType\"/\"type\": \"CollectionType\"/;\
        s/\"visibleName\": \"[^\"]*\"/\"visibleName\": \"$(basename $1)\"/;\
        s/\"parent\": \"\"/\"parent\": \"$2\"/' /home/root/.local/share/remarkable/xochitl/$RET_UUID.metadata"

        # Delete files not needed for directories
        ssh -S remarkable-ssh root@"$SSH_ADDRESS" "rm -r /home/root/.local/share/remarkable/xochitl/$RET_UUID{,.cache,.highlights,.pagedata,.pdf,.textconversion,.content}"

        # re-populate *.content
        ssh -S remarkable-ssh root@"$SSH_ADDRESS" "echo "{}" > /home/root/.local/share/remarkable/xochitl/$RET_UUID.content"

        local uuid="$RET_UUID" # local to avoid being overwritten by recursive calls

        # Only set ROOT_UUID once
        if [ -z "$ROOT_UUID" ]; then
          ROOT_UUID="$RET_UUID"
        fi

        # Call push for files inside this directory
        for item in "$1"/*; do
          check_file "$item"
          if [ "$?" -eq 1 ]; then
            push "$item" "$uuid"
          else
            # Skipping instead of aborting, because we already could have pushed files
            echo repush: Skipping "$item".
          fi
        done
      else # file is no directory
        # Change parent UUID to $2
        ssh -S remarkable-ssh root@"$SSH_ADDRESS" "sed -i 's/\"parent\": \"[^\"]*\"/\"parent\": \"$2\"/' /home/root/.local/share/remarkable/xochitl/$RET_UUID.metadata"
      fi

      ((SUCCESS++))
      return 1

    else # curl failed
      retry=""
      echo "repush: $1: Failed"
      read -r -p "Failed to push file! Retry? [Y/n]: " retry

      if [[ $retry == "n" || $retry == "N" ]]; then
        return 0
      fi
    fi
  done
}

# Evaluate Options/Parameters
while getopts ":vhdr:p:o:" opt; do
  case "$opt" in
    h) # Usage help
      usage
      exit 1
      ;;

    v) # Version
      echo "repush version: $VERSION"
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
      echo "repush: Invalid option or missing arguments: -$OPTARG"
      usage
      exit -1
      ;;
  esac
done
shift $((OPTIND-1))

# Check for minimum argument count
if [ -z "$1" ];  then
  echo "repush: No files provided"
  usage
  exit -1
fi

for f in "$@"; do
  check_file $f
  if [ "$?" -eq 0 ]; then
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
  SSH_RET="$?"

  WEBUI_ADDRESS="localhost:$PORT"
else
  ssh -o ConnectTimeout=1 -M -S remarkable-ssh -q -f root@"$SSH_ADDRESS" -N
  SSH_RET="$?"
fi

if [ "$SSH_RET" -ne 0 ]; then
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

  # Directory not found
  if [ "${#RET_FOUND[@]}" -eq 0 ]; then
    echo "repush: Unable to find output directory: $OUTPUT"
    rm -rf /tmp/repush
    ssh -S remarkable-ssh -O exit root@"$SSH_ADDRESS"
    exit -1

  # Multiple directories match
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
    echo "'$OUTPUT' matches multiple directories!"
    while true; do
      echo

      # Display file id's from most recently modified to oldest
      for (( i=0; i<${#uuid[@]}; i++ )); do
        echo -e "$(( i + 1 )). ${uuid[$i]} - Last modified $(date -d @$(( ${lastModified[$i]} / 1000 )) '+%Y-%m-%d %H:%M:%S')"
      done

      echo
      read -rp "Select your target directory: " INPUT
      echo

      if [[ "$INPUT" -gt 0  && "$INPUT" -lt $(( i + 1 )) ]]; then
        OUTPUT_UUID="${uuid[(($INPUT-1))]}"
        break
      fi

      echo "Invalid input"
    done

  # Directory found
  else
    OUTPUT_UUID="$RET_FOUND"
  fi

  # Disable wifi to prevent conflicts with cloud
  if [ -z "$REMOTE" ]; then
    RFKILL="$(ssh -S remarkable-ssh root@"$SSH_ADDRESS" "/usr/sbin/rfkill list 0 | grep 'blocked: yes'")"
    if [ -z "$RFKILL" ]; then
      ssh -S remarkable-ssh root@"$SSH_ADDRESS" "/usr/sbin/rfkill block 0"
    fi
  fi
fi

# Push files
TOTAL=0 # num of files (excluding files rejected by check_file)
SUCCESS=0 # num of successful pushed files
for f in "$@"; do
  ROOT_UUID=""
  push "$f"

  if [ $? == 1 ]; then
    if [ "$OUTPUT" ]; then
      # Move file to output directory
      ssh -S remarkable-ssh root@"$SSH_ADDRESS" "sed -i 's/\"parent\": \"[^\"]*\"/\"parent\": \"$OUTPUT_UUID\"/' /home/root/.local/share/remarkable/xochitl/$ROOT_UUID.metadata"
    fi

    # Delete flag (-d) provided
    if [ "$DELETE_ON_PUSH" ]; then
      rm "$f"
      if [ $? -ne 0 ]; then
        echo "repush: Failed to remove $f"
      fi
    fi
  else
    echo "repush: $f: Failed"
  fi
done

# Restart xochitl to apply changes to metadata
if [[ "$OUTPUT" || "$DIR_IN_ARG" ]]; then
  if [[ -z "$REMOTE" && -z "$RFKILL" ]]; then
    ssh -S remarkable-ssh root@"$SSH_ADDRESS" "/usr/sbin/rfkill unblock 0"
  fi

  echo "repush: Applying changes..."
  ssh -S remarkable-ssh root@"$SSH_ADDRESS" "systemctl restart xochitl;"
fi

rm -rf /tmp/repush
ssh -S remarkable-ssh -O exit root@"$SSH_ADDRESS"
echo "repush: Successfully transferred $SUCCESS out of $TOTAL files"
