#!/usr/bin/perl
# getcams-axis.pl

$VERS="11282018";
=begin comment
  getcams-axis.pl -- camera image fetch and processing script for axis cameras
  
  Now camera control dictated by cam_params file, format of which is:
  #NAME:PROGRAM:TYPE:STARTUP_DELAY:"LABEL":RUN_ONE_MINUTE_ONLY:CAPTURES/MINUTE
  #  hpwren-mobo7:getcams-mobo.pl:c:0:"Cal Fire Ramona AAB, http\://hpwren.ucsd.edu c1":1:1
      |             |               | |  |                                                | |Captures/minute
      |             |               | |  |                                                |0=>Run_forever/1=>Run_one_minute then exit
      |             |               | |  |Label                                           |Run_once used for debugging
      |             |               | |Startup delay seconds
      |             |               |Type (c=color m=infrared)
      |             |fetch script 
      |camera name (also IP host basename)

  Above parameters read in by run_cameras (parent script) and passed to this program as command line args:
    (e.g. getcams-mobo.pl $CAMERA $TYPE $STARTUP_DELAY $LABEL $RUN_ONE_MINUTE_ONLY $Camera_fetches_Per_Minute)

  Current version of code 
     1) fetches camera image 
     2) reformats image to multiple formats and diffs
     3) updates destination target => /Data/archive/incoming/cameras
     4) supports ongoing captures and adjustable captures per minute ($CPM) via cam_params with credentials from cam_access 
     5) logs to /var/local/hpwren/log/getcams-xxx-$CAMERA.log (start, fetchs, fails, exit)

=end comment
=cut

use File::Basename;
use Log::Log4perl;
use File::Copy qw(copy);
use Cwd;


# Program Paths
$CONVERT="/usr/bin/convert";
$CURL="/usr/bin/curl";
$MKDIR="/usr/bin/mkdir";
$PNMARITH="/usr/bin/pnmarith";
$PNMSCALE="/usr/bin/pnmscale";
$PPMLABEL="/usr/bin/ppmlabel";


$HOME="/home/hpwren";

# Passed in from run_cameras export
$DBG = 0; 
$DBG = "$ENV{DBG}" ;
$PATH = "$ENV{PATH}" ;
$HPATH="$HOME/bin/getcams";
$LOGS = "/var/local/hpwren/log";

chdir("/home/hpwren/bin/getcams") or die "cannot change: $!\n";

$|++;  # Flush IO buffer at every print

unless(-e $HPATH or mkdir -p $HPATH) { die "Unable to create $HPATH\n"; }
unless(-e $LOGS or mkdir -p $LOGS) { die "Unable to create $LOGS\n"; }

$TVS = "$HPATH/tvpattern-small.jpg";
$PW = "$HPATH/cam_access";  
$ADIR="/Data/archive";                   # Archival image location
$TDIR="/Data-local/scratch";             # Temp/local faster location for interim processing
$CDIR= "$ADIR/incoming/cameras";         # Current image location (for web page collage)

#Check if we have enough ARGS
die "Insufficient args, got $#ARGV, need 6\n" if ( $#ARGV != 6 ) ;

$CAMERA=$ARGV[0]; 
$HOST=$CAMERA;
$TYPE=$ARGV[1];    #c or n

### Axis change
#$CAMERA="$CAMERA-$TYPE";
###

$STARTUP_DELAY=$ARGV[2];
if($STARTUP_DELAY ne "0"){sleep($STARTUP_DELAY);} 
$LABEL=$ARGV[3];
if($LABEL eq ""){$LABEL="-";}
$LABEL =~ s/"//g; #Remove embedded quotes from label
$RUN_ONE_MINUTE=$ARGV[4]; #This is the run_once flag from cam_params
$CPM=$ARGV[5];
# Added 6th arg to support custom curl addressing (e.g. for MPO and some SMER???)
$URL=$ARGV[6];

if ( $URL eq "DEFAULT" ) {
    ### Axis change
    $HTTP="http://$HOST/axis-cgi/jpg/image.cgi?overlayimage=0";
    $HTTP2="http://$HOST/axis-cgi/com/ptz.cgi?query=position";    #For coordinate fetch
    $CREDS2=" -u camproxy:TBD ";                                   #For coordinate fetch 
    #$CREDS2=" -u root:mnp32145 ";                                   #For coordinate fetch 
    ###
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

#Fetch credentials from access file "cam_access"
# Format:
#    NAME:LOGIN:PASSWORD
#    hpwren-mobo7:login:201110
#    testcam-iqueye:login:201110
# Note, if cam_access changes, run_cameras will restart this script

open FILE, '<', $PW or die "File $PW not found - $!\n";
while (<FILE>) {
    chomp;
    my @elements = split /:/, $_;
    next unless $elements[0] eq $HOST;
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
    print "\tRUN_ONE_MINUTE = $RUN_ONE_MINUTE, ";
    print "CPM = $CPM, ";
    print "WAIT_TIME = $period, ";
    print "LOGIN = $LOGIN, ";
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
    if ( ! -d "$ADIR/$CAMERA/large/$dstamp/$APTAG" ) {  
        if ($DBG) { print "\t$MKDIR -p $ADIR/$CAMERA/large/$dstamp/$APTAG 2> /dev/null\n" ; }
        system("$MKDIR -p $ADIR/$CAMERA/large/$dstamp/$APTAG 2> /dev/null");
        #system("$MKDIR -p $ADIR/$CAMERA/small/$dstamp/$APTAG 2> /dev/null");  
    }
} #End UpdateTimeStamp

system("$MKDIR -p $TDIR/$CAMERA 2> /dev/null");

my $i = 0;
my $start_time = time();

# Start outer while loop ... do just one cycle (if RUN_ONE_MINUTE is true) otherwise run continuously
while ( 'true' ) {
    $ITERATIONS=1;
    while ($ITERATIONS <= $CPM) {# Start inner while loop, repeat CPM times
        UpdateTimeStamp();
        if ($DBG) {
            print "\tcapture $ITERATIONS of $CPM \n";
            print "\tsystem(\"$CURL -s $CREDS -o $TDIR/$CAMERA/temp.jpg $HTTP 2> /dev/null\"); \n";
        }
        print $FH "$dtstamp: $ID system(\"$CURL -s $CREDS -o $TDIR/$CAMERA/temp.jpg $HTTP 2> /dev/null\");\n";
        $R=system("$CURL -s $CREDS -o $TDIR/$CAMERA/temp.jpg $HTTP 2> /dev/null");
        if($R == 0){
            #Enable only after checking for valid login, password and URL to invoke
            #system("$CURL -s $CREDS2 -o $CDIR/$CAMERA/temp.position $HTTP2 2> /dev/null");
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
                    $CONVERT -quality 70 $TDIR/$CAMERA/tempdiff.ppm $CDIR/$CAMERA-diff.jpg && 
                    $CONVERT -quality 70 $TDIR/$CAMERA/tempdiff175.ppm $CDIR/$CAMERA-diff175.jpg; 
                )");
            }
            system("(
                $CONVERT -quality 70 $TDIR/$CAMERA/temp175.ppm $CDIR/$CAMERA-175.jpg &&      #These commands continue only is preceeding succeeded
                $CONVERT -quality 70 $TDIR/$CAMERA/temp640.ppm $CDIR/$CAMERA-640.jpg &&
                $CONVERT $TDIR/$CAMERA/temp.ppm $TDIR/$CAMERA/temp2.jpg; 
            )");
            copy  "$TDIR/$CAMERA/temp2.jpg", "$TDIR/$CAMERA/$CAMERA.jpg" or  
                print $FH "$dtstamp: $ID copy $TDIR/$CAMERA/temp.jpg $TDIR/$CAMERA/$CAMERA.jpg failed\n";  
            copy  "$TDIR/$CAMERA/$CAMERA.jpg", "$ADIR/$CAMERA/large/$dstamp/$APTAG/$time.jpg" or 
                print $FH "$dtstamp: $ID copy $TDIR/$CAMERA/$CAMERA.jpg $ADIR/$CAMERA/large/$dstamp/$APTAG/$time.jpg failed\n"; 
            system("$CONVERT $TDIR/$CAMERA/$CAMERA.jpg $HPATH/hpwren8-400.png -gravity southeast -geometry +70+0 -composite $CDIR/$CAMERA.jpg");
        } else {  
# No image available ... $R != 0
            if ($DBG) { print "\tFetch failed, R = $R\n"; }
            print $FH "$dtstamp: $ID Fetch failed, R = $R\n";
            if ($DBG) { print "\tsystem(\"cp -f $TVS $CDIR/$CAMERA-175.jpg\");  \n\t"; }
            copy  "$TVS", "$CDIR/$CAMERA-175.jpg" or 
                print $FH "$dtstamp: $ID copy $TVS $CDIR/$CAMERA-175.jpg failed\n"; 
        }
        $WAIT_TIME= ($start_time + $period * ++$i) - time() ; ##
        if ($DBG) { print "\tSleeping $WAIT_TIME seconds ...\n"; }
        sleep($WAIT_TIME);
        last if ($ITERATIONS == $CPM ); 
        $ITERATIONS++;
    } # End inner while loop ... Runs $CPM times
    last if ($RUN_ONE_MINUTE || $DBG);  #Run for 1 cycle (1 or more fetches over a 1 minute period) then exit
} # End outer while loop

if ($DBG) { printf "\t$progname [$$] exiting at $dtstamp\n" }
print $FH "$dtstamp: $ID Finished $progname\n";
close $FH;

