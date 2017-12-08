# Scripts
A set of bash scripts that may enhance your reMarkable experience

Scripts are split into a total of 3 categories:

## Host
All scripts that fall under this category are host-sided scripts. In other words, these scripts
are executed on your PC, not your reMarkable. Host scripts will however in most cases require
connection to your reMarkable, either trough USB or Wireless.

### rezone.sh
reZone is a small script that can set the timezone on your reMarkable according to the host, or specified timezone.
This is done trough SSH by replacing the environmental `TZ` variable in `/etc/profile`.

#### Usage:
```
Usage: rezone.sh [SSH | -h | -help | --help]

Arguments:
SSH                     Devices SSH address (default 10.11.99.1)
-h -help --help         Displays script usage (this)
```

## Client
All scripts that fall under this category are client-sided scripts. In other words, these scripts
are executed on your reMarkable either locally, or trough an SSH connection.

## Common
All scripts that fall under this category can be executed on both host as well as client. Some scripts
provided by this category may require to run on both device simultaneously.
