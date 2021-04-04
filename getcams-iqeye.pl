#!/usr/bin/perl
# getcams-iqeye.pl

$VERS="04022021";

=begin comment
  getcams-iqeye.pl -- camera image fetch and processing script for iqeye cameras
  Based on getcamsiqeyeanimations6.pl which was crontab driven
    (e.g. ...  hpwren ~hpwren/bin/getcams-iqeye.pl hpwren-iqeye7=login:201110\@   N  7 C "Cal Fire Ramona AAB, http://hpwren.ucsd.edu a2")
  
  Now camera control dictated by cam_params file, format of which is:
  #CAMNAME:DRIVER:TYPE:STARTUP_DELAY:"LABEL":RUN_ONCE:CAPTURES/MINUTE:URL (optional)
  #  hpwren-iqeye7:getcams-iqeye.pl:c:0:"Cal Fire Ramona AAB, http\://hpwren.ucsd.edu c1":1:1:URL (optional)
      |             |               | |  |                                                | |  | Optional custom URL, or DEFAULT
      |             |               | |  |                                                | |Captures/minute
      |             |               | |  |                                                |0=>Run_forever/1=>Run_once then exit
      |             |               | |  |Label                                           |Run_once used for debugging
      |             |               | |Startup delay seconds
      |             |               |Type (c=color m=infrared)
      |             |fetch script 
      |camera name (also IP host basename)

  Above parameters read in by run_cameras (parent script) and passed to this program as command line args:
    (e.g. getcams-iqeye.pl $CAMERA $TYPE $STARTUP_DELAY $LABEL $RUN_ONCE $Camera_fetches_Per_Minute)

  Current version of code 
     1) fetches camera image 
     2) reformats image to multiple formats and diffs
     3) updates destination target => /Data/archive/incoming/cameras (local file system or remote via s3cmd)
     4) supports ongoing captures and adjustable captures per minute ($CPM) via cam_params with credentials from cam_access 
     5) logs to /var/local/hpwren/log/getcams-xxx-$CAMERA.log (start, fetchs, fails, exit)

  Test in isolation using 
  sudo -u hpwren ./getcams-iqeye.pl hpwren-iqeye7 c 0 "Cal Fire Ramona AAB, http://hpwren.ucsd.edu c0" 0 1 DEFAULT

=end comment
=cut

#Variables now set in and accessed from external files config_runcam_vars and config_getcams_vars

use File::Basename;
#use Log::Log4perl;
use File::Copy qw(copy);
use Cwd;
use Proc::Reliable;


# If RHOME and RPATH are preset, we are running in a container with adjusted paths ...
$RHOME = "$ENV{RHOME}" ;
$RPATH = "$ENV{RPATH}" ;
unless ( length $RHOME ) { $RHOME = "/home/hpwren"; }
unless ( length $RPATH ) { $RPATH = "$RHOME/bin/getcams"; }

# Read in getcams variables in file $RPATH/config_getcams_vars  to set common variables
$cfile   =   "$RPATH/config_getcams_vars";
open CONFIG, "$cfile" or die "couldn't open $cfile\n";
my $config = join "", <CONFIG>;
close CONFIG;
eval $config;
die "Couldn't eval your config: $@\n" if $@;

my $cmd;
my $FH;
my $timeout =  45;

# sub SystemTimer routine moved to end of code


# Passed in from run_cameras export ... 
$DBG = 0; 
if(defined $ENV{DBG}) { $DBG = "$ENV{DBG}" ; }
$POSIX = 1;
if(defined $ENV{POSIX}) { $POSIX = "$ENV{POSIX}" ; }
$S3 = 0; 
if(defined $ENV{S3}) { $S3 = "$ENV{S3}" ; }
$S3CMD = "$ENV{S3CMD}" ;
$S3CFG = "$ENV{S3CFG}" ;
$S3ARGS = "$ENV{S3ARGS}" ;
#Above inherited from runcams ...

### Uncomment below for local s3cmd debugging ...
#$DBG = 1;
#$POSIX = 1;
#$S3 = 1;
#$S3CMD="/usr/bin/s3cmd";
#$S3CFG="$RHOME/.s3cfg-xfer";
#$S3ARGS="-c $S3CFG --no-check-md5 ";



$|++;  # Flush IO buffer at every print

unless(-e $RPATH or mkdir -p $RPATH ) { die "Unable to create $RPATH\n"; }
unless(-e $LOGS or mkdir -p $LOGS ) { die "Unable to create $LOGS\n"; }
chdir("$RPATH") or die "cannot change: $!\n";

unless(-e $ADIR or mkdir -p $ADIR ) { die "Unable to create $ADIR\n"; }
unless(-e $CDIR or mkdir -p $CDIR ) { die "Unable to create $CDIR\n"; }
unless(-e $TDIR or mkdir -p $TDIR ) { die "Unable to create $TDIR\n"; }

#Check if we have enough ARGS
die "Insufficient args, got $#ARGV, need 6\n" if ( $#ARGV != 6 ) ;

$CAMERA=$ARGV[0]; 
$HOST=$CAMERA;
$TYPE=$ARGV[1];    #c or n

$STARTUP_DELAY=$ARGV[2];
$LABEL=$ARGV[3];
if($LABEL eq ""){$LABEL="-";}
$LABEL =~ s/"//g; #Remove embedded quotes from label
$RUN_ONCE=$ARGV[4]; #This is the run_once flag from cam_params
$CPM=$ARGV[5];
# Added 6th arg to support custom curl addressing (e.g. for MPO and some SMER???)
$URL=$ARGV[6];

if ( $URL eq "DEFAULT" ) {
    $HTTP="http://$HOST/now.jpg?jq=75&ds=1";
} else {
    $HTTP=$URL;
}

$period = int(60/$CPM);       ##Time to wait between camera fetches

$time=time();
($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdat)=localtime($time);
$year=$year+1900;
$mon++;
$dstamp=sprintf"%.4d%.2d%.2d",$year,$mon,$mday;
$dtstamp=sprintf"%.2d%.2d%.2d.%.2d%.2d%.2d",$year,$mon,$mday,$hour,$min,$sec;

# Initialize Logger
$progname=$0;
$progbname = basename($0, ".pl");
$logfile = "$LOGS/$CAMERA.log";
if (! -e $logfile ) { 
    open OFH, ">$logfile" or die "Can't create $logfile"; 
    close(OFH);
}
open(my $FH, '>>', $logfile) or die "Could not open file '$logfile' $!";

my $filename = basename($0, ".pl");
$ID="$fileName\[$$\]:"; 
if ($DBG) { print "\n\t$dtstamp: $filename: [$$] Running $progname  0=$ARGV[0] 1=$ARGV[1] 2=$ARGV[2] \n\t3=$ARGV[3] 4=$ARGV[4] 5=$ARGV[5] 6=$ARGV[6]\n" ; }
print $FH "$dtstamp: $ID Running v$VERS $progname  0=$ARGV[0] 1=$ARGV[1] 2=$ARGV[2] 3=$ARGV[3] 4=$ARGV[4] 5=$ARGV[5] 6=$ARGV[6]\n";

unless ( $POSIX || $S3 ) {
    if ($DBG) { print "\n\t$dtstamp: $filename: [$$] neither S3 nor POSIX is set, you must set one in run_cameras, exiting\n\t3=$ARGV[3] 4=$ARGV[4] 5=$ARGV[5] 6=$ARGV[6]\n" ; }
    die "Neither S3 nor POSIX is set, exiting";
}
if ( $S3 ) {
    unless(-e $S3CFG ) { die "Missing S3 Config file $S3CFG in $RHOME\n"; }
}

#Fetch credentials from access file "cam_access"
# Format:
#    NAME:LOGIN:PASSWORD
#    hpwren-iqeye7:login:123456
#    testcam-iqueye:login:123456
#    bm-e-mobo:login:200610:   (and NOT bm-e-mobo-c or bm-e-mobo-m !)
# Note, if cam_access changes, run_cameras will restart this script

open FILE, '<', $PW or die "File $PW not found - $!\n";
while (<FILE>) {
    chomp;
    my @elements = split /:/, $_;
    next unless $elements[0] eq $HOST;   # Cameras listed by computer basenames in  "cam_access"
    $FOUND= "1";
    $LOGIN = $elements[1];
    $PWD = $elements[2];
}
close FILE;

$CREDS=" -u $LOGIN:$PWD ";

if ( $FOUND ne "1" ) {
    if ($DBG) { print "\n\t$dtstamp: $filename: [$$] credentials not found, exiting\n\t3=$ARGV[3] 4=$ARGV[4] 5=$ARGV[5] 6=$ARGV[6]\n" ; }
    die "credentials not found for $CAMERA, exiting";
}

if ($LOGIN eq '') {
    if ($DBG) { print "\n\t$dtstamp: $filename: [$$] login/password fields are empty, assuming none needed\n\t3=$ARGV[3] 4=$ARGV[4] 5=$ARGV[5] 6=$ARGV[6]\n" ; }
    $CREDS='';
}

if ($DBG) {
    print "\tRUN_ONCE = $RUN_ONCE, ";
    print "CPM = $CPM, ";
    print "WAIT_TIME = $period, ";
    print "LOGIN = $LOGIN, ";
    print "URL = $URL, ";
    print "PWD = $PWD\n";
}

sub UpdateTimeStamp {
    $time=time();
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdat)=localtime($time);
    $year=$year+1900;
    $mon++;
    $dstamp=sprintf"%.4d%.2d%.2d",$year,$mon,$mday;
    $dtstamp=sprintf"%.2d%.2d%.2d.%.2d%.2d%.2d",$year,$mon,$mday,$hour,$min,$sec;
    $APTAG="Q1"; 
    if($hour >= 3){$APTAG="Q2";}
    if($hour >= 6){$APTAG="Q3";}
    if($hour >= 9){$APTAG="Q4";}
    if($hour >= 12){$APTAG="Q5";}
    if($hour >= 15){$APTAG="Q6";}
    if($hour >= 18){$APTAG="Q7";}
    if($hour >= 21){$APTAG="Q8";}
    $oldtime=$time-86400;
    ($oldsec,$oldmin,$oldhour,$oldmday,$oldmon,$oldyear,$oldwday,$oldyday,$oldisdat)=localtime($oldtime);
    $oldyear=$oldyear+1900;
    $oldmon++;
    $olddstamp=sprintf"%.4d%.2d%.2d",$oldyear,$oldmon,$oldmday;
    if($POSIX){
        if ( ! -d "$ADIR/$CAMERA/large/$dstamp/$APTAG" ) {  
            if ($DBG) { print "\t$MKDIR -p $ADIR/$CAMERA/large/$dstamp/$APTAG 2> /dev/null\n" ; }
            system("$MKDIR -p $ADIR/$CAMERA/large/$dstamp/$APTAG 2> /dev/null");
        }
    }
} #End UpdateTimeStamp

system("$MKDIR -p $TDIR/$CAMERA 2> /dev/null");

 
## Sleep until next minute boundary - NOT NEEDED OR DESIRED
#$mytime=time();
#($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdat)=localtime($mytime);
#$min_sdelay = 60 - $sec;
#if($min_sdelay ne "0") {sleep($min_sdelay);}

# Now add any startup delay
if($STARTUP_DELAY ne "0") {sleep($STARTUP_DELAY);}

## Counters for sleeping between fetches -- adjust for processing delay times)
my $i = 0;
my $start_time = time();

## Start outer while loop ... do just one cycle (if RUN_ONCE is true) otherwise run continuously
while ( 'true' ) {
    $ITERATIONS=1;
    while ($ITERATIONS <= $CPM) {# Start inner while loop, repeat CPM times
        UpdateTimeStamp();
        if ($DBG) {
            print "\tcapture $ITERATIONS of $CPM \n";
            print "\tsystem(\"$CURL $COPTS $CREDS -o $TDIR/$CAMERA/temp.jpg $HTTP \"); \n";
        }
        $cmd = "$CURL $COPTS $CREDS -o $TDIR/$CAMERA/temp.jpg $HTTP ";
        $R = SystemTimer( $cmd ); # Using SystemTimer() with alarm code to interupt potential hangs

        if($R == 0){
            if ($DBG) { print "\tFetch succeeded, R = $R, dtstamp = $dtstamp, LABEL = $LABEL\n"; }
            if ( -s "$TDIR/$CAMERA/temp.ppm" ) {  # File exists and is not empty
                if ($DBG) { print "\tsystem(\"mv -f $TDIR/$CAMERA/temp.ppm $TDIR/$CAMERA/temp-old.ppm\")\n"; }
                system("mv -f $TDIR/$CAMERA/temp.ppm $TDIR/$CAMERA/temp-old.ppm");
                rename("$TDIR/$CAMERA/temp175.ppm","$TDIR/$CAMERA/temp175-old.ppm");
            }
            if ($DBG) { print "\tsystem(\"$CONVERT $TDIR/$CAMERA/temp.jpg $TDIR/$CAMERA/temp2.ppm 2> /dev/null)\"\n"; }
            if ($DBG) { print "\tsystem($PPMLABEL -x 0 -y 24 -color yellow -background transparent -size 20 -text \n\t\"$dtstamp $LABEL\" $TDIR/$CAMERA/temp2.ppm > $TDIR/$CAMERA/temp.ppm 2> /dev/null);\n"; }
            system("(
                $CONVERT $TDIR/$CAMERA/temp.jpg $TDIR/$CAMERA/temp2.ppm 2> /dev/null &&      #these commands continue only if preceeding succeeded
                $PPMLABEL -x 0 -y 24 -color yellow -background transparent -size 20 -text \"$dtstamp $LABEL\" $TDIR/$CAMERA/temp2.ppm > $TDIR/$CAMERA/temp.ppm 2> /dev/null &&
                $PNMSCALE -xsize=640 -ysize=480 $TDIR/$CAMERA/temp.ppm > $TDIR/$CAMERA/temp640.ppm &&
                $PNMSCALE -xsize=175 -ysize=131 $TDIR/$CAMERA/temp640.ppm > $TDIR/$CAMERA/temp175.ppm;
            )");

            if ( -e "$TDIR/$CAMERA/temp-old.ppm" ) {  # File exists and is not empty 
                system("(
                    $PNMARITH -diff $TDIR/$CAMERA/temp.ppm $TDIR/$CAMERA/temp-old.ppm > $TDIR/$CAMERA/tempdiff.ppm &&    # these commands continue only if preceeding succeeded
                    $PNMARITH -diff $TDIR/$CAMERA/temp175.ppm $TDIR/$CAMERA/temp175-old.ppm > $TDIR/$CAMERA/tempdiff175.ppm && 
                    $CONVERT -quality 70 $TDIR/$CAMERA/tempdiff.ppm $TDIR/$CAMERA/$CAMERA-diff.jpg && 
                    $CONVERT -quality 70 $TDIR/$CAMERA/tempdiff175.ppm $TDIR/$CAMERA/$CAMERA-diff175.jpg; 
                )");
                if ($POSIX){
                    copy "$TDIR/$CAMERA/$CAMERA-diff.jpg", "$CDIR/$CAMERA-diff.jpg" or
                        print $FH "$dtstamp: $ID copy $TDIR/$CAMERA/$CAMERA-diff.jpg $CDIR/$CAMERA-diff.jpg failed\n";  
                    copy "$TDIR/$CAMERA/$CAMERA-diff175.jpg", "$CDIR/$CAMERA-diff175.jpg" or
                        print $FH "$dtstamp: $ID copy $TDIR/$CAMERA/$CAMERA-diff175.jpg $CDIR/$CAMERA-diff-175.jpg failed\n";  
                }

                if ($S3){
                    #system("$S3CMD $S3ARGS put $TDIR/$CAMERA/$CAMERA-diff.jpg  $TDIR/$CAMERA/$CAMERA-diff175.jpg s3://latest/");
                    $cmd="$S3CMD $S3ARGS put $TDIR/$CAMERA/$CAMERA-diff.jpg  $TDIR/$CAMERA/$CAMERA-diff175.jpg s3://latest/";
                    SystemTimer( $cmd );
                }
            }
            #Serial system commands below continue only if preceeding succeeded
            system("(
                $CONVERT -quality 70 $TDIR/$CAMERA/temp175.ppm $TDIR/$CAMERA/$CAMERA-175.jpg &&      
                $CONVERT -quality 70 $TDIR/$CAMERA/temp640.ppm $TDIR/$CAMERA/$CAMERA-640.jpg &&
                $CONVERT $TDIR/$CAMERA/temp.ppm $TDIR/$CAMERA/temp2.jpg; 
            )");
            copy  "$TDIR/$CAMERA/temp2.jpg", "$TDIR/$CAMERA/$CAMERA.jpg" or  
                print $FH "$dtstamp: $ID copy $TDIR/$CAMERA/temp2.jpg $TDIR/$CAMERA/$CAMERA.jpg failed\n";  
            if ($POSIX){
                copy "$TDIR/$CAMERA/$CAMERA-175.jpg", "$CDIR/$CAMERA-175.jpg" or 
                        print $FH "$dtstamp: $ID copy $TDIR/$CAMERA/$CAMERA-175.jpg $CDIR/$CAMERA-175.jpg failed\n";  
                copy "$TDIR/$CAMERA/$CAMERA-640.jpg", "$CDIR/$CAMERA-640.jpg" or 
                        print $FH "$dtstamp: $ID copy $TDIR/$CAMERA/$CAMERA-640.jpg $CDIR/$CAMERA-640.jpg failed\n";  
                copy  "$TDIR/$CAMERA/$CAMERA.jpg", "$ADIR/$CAMERA/large/$dstamp/$APTAG/$time.jpg" or 
                    print $FH "$dtstamp: $ID copy $TDIR/$CAMERA/$CAMERA.jpg $ADIR/$CAMERA/large/$dstamp/$APTAG/$time.jpg failed\n"; 
                system("$CONVERT $TDIR/$CAMERA/$CAMERA.jpg $RPATH/hpwren8-400.png -gravity southeast -geometry +70+0 -composite $CDIR/$CAMERA.jpg");
            }
            if ($S3){
                if ($DBG) { print "\tsystem(\"$S3CMD $S3ARGS put $TDIR/$CAMERA/$CAMERA-175.jpg $TDIR/$CAMERA/$CAMERA-640.jpg s3://latest/\");  \n\t"; }
                $cmd="$S3CMD $S3ARGS put $TDIR/$CAMERA/$CAMERA-175.jpg $TDIR/$CAMERA/$CAMERA-640.jpg s3://latest/";
                SystemTimer( $cmd );
                if ($DBG) { print "\tsystem(\"$S3CMD $S3ARGS put $TDIR/$CAMERA/$CAMERA.jpg s3://archive/$CAMERA/large/$dstamp/$APTAG/$time.jpg\");  \n\t"; }
                $cmd="$S3CMD $S3ARGS put $TDIR/$CAMERA/$CAMERA.jpg s3://archive/$CAMERA/large/$dstamp/$APTAG/$time.jpg";
                SystemTimer( $cmd );
                # Replicate above archive copy lines to s3://recent
                if ($DBG) { print "\tsystem(\"$S3CMD $S3ARGS put $TDIR/$CAMERA/$CAMERA.jpg s3://recent/$CAMERA/large/$dstamp/$APTAG/$time.jpg\");  \n\t"; }
                $cmd="$S3CMD $S3ARGS put $TDIR/$CAMERA/$CAMERA.jpg s3://recent/$CAMERA/large/$dstamp/$APTAG/$time.jpg";
                SystemTimer( $cmd );
                system("$CONVERT $TDIR/$CAMERA/$CAMERA.jpg $RPATH/hpwren8-400.png -gravity southeast -geometry +70+0 -composite $TDIR/$CAMERA/$CAMERA.jpg");

                $cmd="$S3CMD $S3ARGS put $TDIR/$CAMERA/$CAMERA.jpg s3://latest/";
                SystemTimer( $cmd );

            }
        
        } else {  # No image available ... $R != 0
                if ($DBG) { print "\tFetch failed, R = $R\n"; }
                print $FH "$dtstamp: $ID Fetch failed, R = $R\n";
                if ($POSIX){
                    if ($DBG) { print "\tcopy $TVS, $CDIR/$CAMERA-175.jpg; \n\t"; }
                    copy  "$TVS", "$CDIR/$CAMERA-175.jpg" or 
                        print $FH "$dtstamp: $ID copy $TVS $CDIR/$CAMERA-175.jpg failed\n"; 
                }
                if ($S3){
                    $cmd="$S3CMD $S3ARGS put $TVS s3://latest/$CAMERA-175.jpg";
                    SystemTimer( $cmd );
                }
        }
        ### Might need to reduce WAIT_TIME below by 1 second
        $WAIT_TIME= ($start_time + $period * ++$i) - time() ; ##
        if ($WAIT_TIME > 0 ){
            if ($DBG) { print "\tSleeping $WAIT_TIME seconds ...\n"; }
            sleep($WAIT_TIME);
        }
        last if ($ITERATIONS == $CPM ); 
        $ITERATIONS++;
    } # End inner while loop ... Runs $CPM times
    last if ($RUN_ONCE || $DBG);  #Run for 1 cycle (1 or more fetches over a 1 minute period) then exit
} # End outer while loop

if ($DBG) { printf "\t$progname [$$] exiting at $dtstamp\n" }
print $FH "$dtstamp: $ID Finished $progname\n";
close $FH;

# SystemTimer routine used to prevent hanging system calls by using an internal timeout mechanism
sub SystemTimer {
    my ( $command ) = @_;
    print $FH "$dtstamp: $ID Executing system(\"$command\");\n";
    my $proc = Proc::Reliable->new ();
    $proc->maxtime ($timeout);
    ($stdout, $stderr, $rstatus, $msg) = $proc->run($command);
    if ($rstatus) {
      print $FH "$dtstamp: $ID Timeout! Status is $rstatus, stdout is $stdout, stderr is $stderr, cmd is $command\n";
    }
    return $rstatus ;
} #End SystemTimer
