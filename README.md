# Scripts

A set of bash scripts primarily aimed to increase productivity for Linux and OSX enthusiasts that own a reMarkable tablet.

The repository provides a broad range of scripts, ranging from simple patchers meant to fix obnoxious little flaws, all the way to push and pull scripts that can transfer documents from- and to the reMarkable from the bash command line.

For more information, please [refer to the repo wiki](https://github.com/reHackable/scripts/wiki).

## Host
Host scripts are meant to be executed on the host device and will frequently require a connection the device either locally via USB, or wirelessly via SSH.

- [rezone.sh](https://github.com/reHackable/scripts/wiki/rezone.sh) - Change/Update the timezone on the reMarkable
- [repush.sh](https://github.com/reHackable/scripts/wiki/repush.sh) - Transfer documents to the remarkable from the bash command line
- [repull.sh](https://github.com/reHackable/scripts/wiki/repull.sh) - Download documents and directories from the reMarkable
- [retext.sh](https://github.com/reHackable/scripts/wiki/retext.sh) - Revert EPUBs to their initial state
- [reclean.sh](https://github.com/reHackable/scripts/wiki/reclean.sh) - Remove unwanted junk on your reMarkable
- [resnap.sh](https://github.com/reHackable/scripts/wiki/resnap.sh) - Take a snapshot of the current display on the reMarkable
- [webui_invincibility.sh](https://github.com/reHackable/scripts/wiki/webui_invincibility.sh) - Prevent the WebUI from disabling at boot

## Client
All scripts that fall under this category are client-sided scripts. In other words, these scripts
are executed on your reMarkable locally.

## Common
All scripts that fall under this category can be executed on both host as well as client. Some scripts
provided by this category may require to run on both device simultaneously.
