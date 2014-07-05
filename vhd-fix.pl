#!/usr/bin/env perl

use strict;
use warnings;

#use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

my $sf = $ARGV[0] ;

my $sfsize = -s $sf ;
open SVHD, "+<", $sf or die "cant open $sf" ;
binmode SVHD;

sub setChksum {
  my ($data, $offset, $length) = @_ ;
  my $newChckSum = 0;

  my @stream = unpack "C*", $data;

  # チェックサムを0でクリアする
  for (my $i=$offset ; $i< $offset + $length; $i++) {
    $stream[$i] = 0 ;
  }

  foreach my $i (@stream) {
    $newChckSum += $i ;
  }

  my @newChckSum = unpack "C" . $length , pack "N", ~$newChckSum ;

  # チェックサムをセットする
  for (my $i=0 ; $i< $length; $i++) {
    $stream[$offset + $i] =  $newChckSum[$i] ;
  }

  return pack "C*", @stream;
}

sub readChksum {
  my ($data, $offset, $length) = @_ ;
  my $newChckSum = 0;

  my @stream = unpack "C*", $data;

  my ($chckSum) = unpack("N", substr($data, $offset, $length)) ;
  printf "chcksum(orignal)    = %x\n", $chckSum ;
  
  # チェックサムを0でクリアする
  for (my $i=$offset ; $i< $offset + $length; $i++) {
    $stream[$i] = 0 ;
  }

  foreach my $i (@stream) {
    printf "%x ", $i unless $i == 0;
    $newChckSum += $i ;
  }

  my @newChckSum = unpack "C" . $length , pack "N", ~$newChckSum ;
  #printf "chcksum(new)        = %x\n", ~$newChckSum ;
  printf "chcksum(new)        = " ;
  foreach my $i (@newChckSum) {
    printf "%02x", $i;
  }
  printf "\n" ;
  
}

sub setCHS {
  my ($hdheader) = @_ ;
  my ($cyl,$head,$sector) ;
  my ($disksize, $cylTimesHeads) ;

  my @newGeom ;
  my @stream = unpack "C*", $hdheader;

  my ($currentSizeUpper, $currentSizeLower) 
     = unpack "NN", substr($hdheader, 48, 8) ;
  $disksize = ($currentSizeUpper << 32) + $currentSizeLower ;
  printf "CurrnentDiskSize    = %d \n", $disksize;

  #セクタサイズは512Byte固定
  my $totalSectors = $disksize / 512 ;

  if ($totalSectors > 65535 * 16 * 255) {
    $totalSectors = 65535 * 16 * 255 ;
  }

  ### Microsoft VHD Format Appendixのコード ここから ###
  if ($totalSectors >= 65535 * 16 * 63) {
    $sector = 255;
    $head = 16 ;
    $cylTimesHeads = $totalSectors / $sector;
  } else {
    $sector = 17;
    $cylTimesHeads = $totalSectors / $sector;

    $head = ($cylTimesHeads + 1023) / 1024 ;

    if ( $head < 4 ){
      $head = 4;
    }
    if ($cylTimesHeads >= ( $head * 1024 ) || $head > 16 ){
      $sector = 31 ;
      $head = 16 ;
      $cylTimesHeads = $totalSectors / $sector ;
    }
    if ($cylTimesHeads >= ( $head * 1024 )) {
      $sector = 63 ;
      $head = 16 ;
      $cylTimesHeads = $totalSectors / $sector ;
    }
  }
  $cyl = $cylTimesHeads / $head ;
  ### ここまで ###

  printf "geometry(new)       = Cyl:%d, Head:%d, Sector:%d\n", $cyl,$head,$sector ;

  @newGeom = (unpack("CC", pack("n", $cyl)), $head, $sector);

  # DiskGeometoryをセットする
  for (my $i=0 ; $i< 4 ; $i++) {
    $stream[56 + $i] =  $newGeom[$i] ;
  }
  
  ### Creator Applicationを修正
  my @creatorApp = unpack "CCCC", "ym3k" ;
  for (my $i=0 ; $i< 4 ; $i++) {
    $stream[28 + $i] =  $creatorApp[$i] ;
  }
  
  return pack "C*", @stream;
}

sub guessBATinc {
  my ($BATref) = @_ ;
  #BATの最初の20個のうち、0xffffffff以外を取り出し、昇順にソート
  my @sample = sort {$a<=>$b} grep { $_ != 0xffffffff } map { $BATref->[$_] } 0..19;
  #ソートしたサンプルの差分の最小値をブロックサイズとみなす
  my ($minBATinc) = sort {$a<=>$b} map { $sample[$_+1] - $sample[$_] } 0 .. $#sample-1 ;
  return $minBATinc;
}

##### new file size ####
my $ofsize = 0;

##### HardDisk Footer (at first) ###########
my $hdheader ;

$ofsize += read SVHD, $hdheader, 512;

##### backup original header ###
#open OHEAD, ">", "./oldHeader" or die ;
#print OHEAD $hdheader ;
#close OHEAD ;

my ($hdcookie) = unpack("A8", $hdheader);

my ($chckSum) = unpack("N", substr($hdheader, 64, 4)) ;
printf "VHD Footer\n-------------\n" ;
printf "chcksum(orignal)    = %x\n", $chckSum ;

my ($cyl,$head,$sector) = unpack("nCC", substr($hdheader, 56, 4));
printf "geometry(orignal)   = Cyl:%d, Head:%d, Sector:%d\n", $cyl,$head,$sector ;

my $newheader = setCHS($hdheader);

$newheader = setChksum($newheader, 64, 4);
my ($hdncookie) = unpack("A8", $newheader);

###### dynamic disk header #####
my ($disktype) = unpack("N", substr($hdheader, 60, 4)) ;

if ($disktype == 3 or $disktype == 4) {
  printf "\nVHD Dynamic Disk Header\n-------------\n" ;
  
  my $dyheader ;
  seek(SVHD, 512, 0);
  $ofsize += read SVHD, $dyheader, 1024;
  
  my ($tableOffsetU, $tableOffsetL)
    = unpack("NN", substr($dyheader, 16, 8)) ;
  my $tableOffset = ($tableOffsetU << 32 ) + $tableOffsetL ;
  
  my ($maxTableEnt, $blockSize) = unpack("NN", substr($dyheader, 28, 8)) ;
  
  ## BATの最初に戻る
  seek(SVHD, $tableOffset, 0);
  ##### BAT(block allocation table) ####
  my $BAT;
  $ofsize += read SVHD, $BAT, $maxTableEnt * 4;
  #open OBAT, ">", "./oldBAT" or die ;
  #print OBAT $BAT ;
  #close OBAT ;
  
  ##### delete tdbatmap( tap disk batmap ?) #####
  ##### for Xen blktap2 
  my ($tdbatmap);
  read SVHD, $tdbatmap, 512;
  my ($tdcookie) = unpack("A8", substr($tdbatmap, 0, 8)) ;
  if ($tdcookie eq "tdbatmap" ) {
    my ($tdSect) = unpack("N", substr($tdbatmap, 16, 4)) ;
    $tdSect++;
    printf "tdbatmapsize(sectors) is: %d\n" , $tdSect;
    
    ### 新しいbitmapを作成 (all 1)
    my $bitmapBits = $blockSize / 512 ;
    my $bitmapSize = $bitmapBits / 8  ; # byteに変換しておく
    my $newBitmap = (~pack "b" . $bitmapBits ) ;
        
    ### データの始まり
    my $datastartNew = ( $tableOffset + ($maxTableEnt * 4 ) ) / 512 ;
    my $datastartOrg = $datastartNew + $tdSect ;
    
    ##### tdbatmap + pad 分 前に寄せたBATを作成
    ##### padは 7 * (BAT % 0x1053 )

    my ($newBAT) ;
    my @BAT = unpack "N*", $BAT;
    
    #BATの最初の20個のうち、0xffffffff以外をサンプリングし昇順にソート
    my @sample = sort {$a<=>$b} grep { $_ != 0xffffffff } map { $BAT[$_] } 0..19;
    #ソートしたサンプルの差分の最小値をブロックサイズとみなす
    my ($orgBATinc) = sort {$a<=>$b} map { $sample[$_+1] - $sample[$_] } 0 .. $#sample-1 ;
    
    my $newBATinc = ($blockSize + $bitmapSize) / 512 ;
    
    my $diffBATpad = $orgBATinc - $newBATinc ; #maybe always '7'
    
    for (0..$#BAT) {
       unless ($BAT[$_] == 0xffffffff) {
         $BAT[$_] = ($BAT[$_] - $datastartOrg) / $orgBATinc * $newBATinc + $datastartNew  ;
       }
    }
    $newBAT = pack "N*", @BAT;
    
    #open NBAT, ">", "./newBAT" or die ;
    #print NBAT $newBAT ;
    #close NBAT ;
    
    ### BAT を更新
    seek(SVHD, $tableOffset, 0); 
    print SVHD $newBAT;
    
    my ($cursor, $Blk, $bsize,);
    my $pads = 0;
    my $proceeds = 0;
    my $oldproceeds = 0;
    
    while (1) {
      ### 次のブロックの位置を記憶
      $cursor = tell(SVHD); 
      printf "cursor:%x", $cursor ;
    
      ### tdbatmap + pad分、先に移動 ###
      ### padは1ブロックにつき7セクタ(7*512バイト)増えていく。
      ### bitmapは新しく作り直したもの(all 1)に書き換えて、
      ### カーソルを進める。

      seek(SVHD, ($tdSect * 512) + $pads + $bitmapSize , 1);
      printf " block:%x -", tell(SVHD) - $bitmapSize;
      $ofsize += $bitmapSize ;
      $bsize = read SVHD, $Blk, $blockSize;
      $ofsize += $bsize ;
      printf " %x", tell(SVHD) ;
      last if $bsize < $blockSize;
      seek(SVHD, $cursor, 0);
      ## 書き出す
      #seek(SVHD, $bitmapSize + $bsize, 1) ;
      print SVHD $newBitmap ; print SVHD $Blk ;
      $pads += ($diffBATpad * 512);
      
      $proceeds = int($ofsize / $sfsize * 100 ) ;
      printf " pads:%x  %d%%", $pads, $proceeds ;
      if ($oldproceeds == $proceeds ) {
        printf "\r" ;
      }else{
        printf "\n" ;
        $oldproceeds = $proceeds ;
      }
    }
    
    # 新しいVHDファイルのサイズに縮める
    truncate(SVHD, $ofsize) ;
    printf " done.                        \n" ;
    printf "\noriginal file size: %d\t%x\n", $sfsize, $sfsize;
    printf "new file size:      %d\t%x\n", $ofsize, $ofsize;
  }
}



############# write header ############
seek(SVHD, 0, 0);
print SVHD $newheader ;
seek(SVHD, -512, 2);
print SVHD $newheader ;


##### HardDisk Footer check (at last) ###########
my $hdnfooter ;
seek(SVHD, -512, 2);
read SVHD, $hdnfooter, 512;
my ($hdnfootercookie) = unpack("A8", $hdnfooter);

printf "$hdncookie, $hdnfootercookie\n" ;

#open NHEAD, ">", "./newHeader" or die ;
#print NHEAD $newheader ;
#close NHEAD ;

########### end of write header #######
close SVHD;
