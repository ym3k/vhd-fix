vhd-fix
=======

convert to/from Xen VHD

  Convert from Microsoft VHD to read xen vhd-util (fix CHS geometry).
  Convert from Xen blktap2 batmap-added VHD to Microsoft VHD format.
 
Requre:
  perl 5.6 or later.

Usage:
  vhd-fix.pl VHDFILE
  
  the original file is overwriten with this script, 
  for save host's disk space.
