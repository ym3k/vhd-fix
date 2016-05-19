vhd-fix
=======

Convert Microsoft VHD to readable on XenServer 6.0.2 vhd-util.
(with fix CHS geometry)

Requrement:
  perl 5.6 or later.

Usage:
  vhd-fix.pl VHDFILE
  
  Original files will be overwriten by this script  
  for saving disk space.
  Back-up the original file by yourself, if you want.
