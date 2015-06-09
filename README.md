vhd-fix
=======

convert to/from XenServer VHD

  Convert from Microsoft VHD to read XenServer 6.0.2 vhd-util (fix CHS geometry).
  Convert from XenServer blktap2 batmap-added VHD to Microsoft VHD format.
 
Requre:
  perl 5.6 or later.

Usage:
  vhd-fix.pl VHDFILE
  
  the original file is overwriten by this script, 
  for save host's disk space.
