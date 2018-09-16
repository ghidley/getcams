#!/usr/bin/perl
# getcams-mobo.pl

$VERS="09092018";
=begin comment
  getcams-mobo.pl -- camera image fetch and processing script for Mobotix cameras
  Based on getcamsiqeyeanimations6.pl which was crontab driven
    (e.g. ...  hpwren ~hpwren/bin/getcams-iqeye.pl hpwren-iqeye7=login:201110\@   N  7 C "Cal Fire Ramona AAB, http://hpwren.ucsd.edu a2")
  
  Now camera control dictated by cam_params file, format of which is:
  #NAME:PROGRAM:TYPE:STARTUP_DELAY:"LABEL":RUN_ONE_MINUTE_ONLY:CAPTURES/MINUTE
  #  hpwren-iqeye7:getcams-iqeye.pl:c:0:"Cal Fire Ramona AAB, http\://hpwren.ucsd.edu c1":1:1
      |             |               | |  |                                                | |Captures/minute
      |             |               | |  |                                                |0=>Run_forever/1=>Run_one_minute then exit
      |             |               | |  |Label                                           |Run_once used for debugging
      |             |               | |Startup delay seconds
      |             |               |Type (c=color m=infrared)
      |             |fetch script 
      |camera name (also IP host basename)

  Above parameters read in by run_cameras (parent script) and passed to this program as command line args:
    (e.g. getcams-iqeye.pl $CAMERA $TYPE $STARTUP_DELAY $LABEL $RUN_ONE_MINUTE_ONLY $Camera_fetches_Per_Minute)

  Current version of code 
     1) fetches camera image 
     2) reformats image to multiple formats and diffs
     3) updates destination target => /Data/archive/incoming/cameras
     4) supports ongoing captures and adjustable captures per minute ($CPM) via cam_params with credentials from cam_access 
     5) logs to /var/local/hpwren/log/getcams-xxx-$CAMERA.log (start, fetchs, fails, exit)

Addition: uses curl instead of fetch, uses offset of 24 for ppmlablel
=end comment
=cut

use File::Basename;
use Log::Log4perl;

# Passed in from run_cameras export
$DBG = 0; 
$DBG = "$ENV{DBG}" ;
$PATH = "$ENV{PATH}" ;
$HOME = "$ENV{HOME}" ;
$HPATH="$HOME/bin/getcams";
$LOGS = "/var/local/hpwren/log";

$|++;  # Flush IO buffer at every print

unless(-e $HPATH or mkdir $HPATH) { die "Unable to create $HPATH\n"; }
unless(-e $LOGS or mkdir $LOGS) { die "Unable to create $LOGS\n"; }

$TVS = "$HPATH/tvpattern-small.jpg";
$PW = "$HPATH/cam_access";  
$DIR="/Data/archive";
$DEST= "$DIR/incoming/cameras/tmp"; 

#Check if we have enough ARGS
die "Insufficient args, got $#ARGV, need 5\n" if ( $#ARGV != 6 ) ;

$CAMERA=$ARGV[0]; 
$TYPE=$ARGV[1];    #c or m
$HOST=$CAMERA; # Camname without -c/m
$CAMERA="$CAMERA-$TYPE";
$STARTUP_DELAY=$ARGV[2];
if($STARTUP_DELAY ne "0"){sleep($STARTUP_DELAY);} 
$LABEL=$ARGV[3];
if($LABEL eq ""){$LABEL="-";}
$LABEL =~ s/"//g; #Remove embedded quotes from label

#New added args ...
$RUN_ONE_MINUTE=$ARGV[4]; #This is the run_once flag from cam_params
$CPM=$ARGV[5];
#
# Added 6th arg to support custom curl addressing (e.g. for MPO and some SMER???)
$URL=$ARGV[6];

if ( $URL eq "DEFAULT" ) {
    $HTTP="http://$HOST/cgi-bin/image.jpg?imgprof=Full-$TYPE";
} else {
    $HTTP=$URL;
}

$time=time();
($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdat)=localtime($time);
$year=$year+1900;
$mon++;
$dstamp=sprintf"%.4d%.2d%.2d",$year,$mon,$mday;
$dtstamp=sprintf"%.2d%.2d%.2d.%.2d%.2d%.2d",$year,$mon,$mday,$hour,$min,$sec;

# Initialize Logger
$progname=$0;
$progbname = basename($0, ".pl");
$logfile = "$LOGS/$progbname-$CAMERA.log";
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
#    hpwren-iqeye7:login:201110
#    testcam-iqueye:login:201110
# Note, if cam_access changes, run_cameras will restart this script

open FILE, '<', $PW or die "File $PW not found - $!\n";
while (<FILE>) {
	chomp;
	my @elements = split /:/, $_;
	next unless $elements[0] eq $HOST;
	$LOGIN = $elements[1];
	$PWD = $elements[2];
}
close FILE;
#$ADJUST = 12; #Offset for image processing time
$WAIT_TIME = 60/$CPM;	#Time to wait between camera fetches
#if ( $WAIT_TIME > $ADJUST ) { $WAIT_TIME = 60/$CPM - $ADJUST ; }

#$WAIT_TIME = 10; # Override calculated wait time for debugging xxx
	
#if ($LOGIN eq '') { die "$CAMERA credentials not found \n"; }
$CREDS=" -u $LOGIN:$PWD ";
if ($LOGIN eq '') {
    if ($DBG) { print "\n\t$dtstamp: $filename: [$$] credentials not found, assuming none needed\n\t3=$ARGV[3] 4=$ARGV[4] 5=$ARGV[5] 6=$ARGV[6]\n" ; }
    print $FH "$dtstamp: $ID credentials not found, assuming none needed\n";
    $CREDS='';
}

if ($DBG) {
	print "\tRUN_ONE_MINUTE = $RUN_ONE_MINUTE, ";
	print "CPM = $CPM, ";
	print "WAIT_TIME = $WAIT_TIME, ";
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
	system("mkdir -p $DIR/$CAMERA/small/$dstamp/$APTAG 2> /dev/null");  #No longer needed
	system("mkdir -p $DIR/$CAMERA/large/$dstamp/$APTAG 2> /dev/null");
} #End UpdateTimeStamp


# Start outer while loop ... do just one cycle (if RUN_ONE_MINUTE is true) otherwise run continously
while ( 'true' ) {
	$ITERATIONS=1;
	while ($ITERATIONS <= $CPM) {# Start inner while loop, repeat CPM times
		UpdateTimeStamp();
		if ($DBG) {
			print "\tcapture $ITERATIONS of $CPM \n";
			print "\tsystem(\"curl -s $CREDS -o $DIR/$CAMERA/temp.jpg $HTTP 2> /dev/null\"); \n";
		}
		print $FH "$dtstamp: $ID system(\"curl -s $CREDS -o $DIR/$CAMERA/temp.jpg $HTTP 2> /dev/null\");\n";
		$R=system("curl -s $CREDS -o $DIR/$CAMERA/temp.jpg $HTTP 2> /dev/null");
		if($R == 0){
			if ($DBG) { print "\tFetch succeeded, R = $R, dtstamp = $dtstamp, LABEL = $LABEL\n"; }
                        if ( -s "$DIR/$CAMERA/temp.ppm" ) {  # File exists and is not empty
                            if ($DBG) { print "\tsystem(\"cp $DIR/$CAMERA/temp.ppm $DIR/$CAMERA/temp-old.ppm\")\n"; }
                            system("cp $DIR/$CAMERA/temp.ppm $DIR/$CAMERA/temp-old.ppm");
                            rename("$DIR/$CAMERA/temp175.ppm","$DIR/$CAMERA/temp175-old.ppm");
                        }
			if ($DBG) { print "\tsystem(\"convert $DIR/$CAMERA/temp.jpg $DIR/$CAMERA/temp2.ppm 2> /dev/null)\"\n"; }
			system("convert $DIR/$CAMERA/temp.jpg $DIR/$CAMERA/temp2.ppm 2> /dev/null");
			$LABELS="$dtstamp $LABEL";
			if ($DBG) { print "\tsystem(ppmlabel -x 0 -y 24 -color orange -background transparent -size 20 -text \n\t\"$LABELS\" $DIR/$CAMERA/temp2.ppm > $DIR/$CAMERA/temp.ppm 2> /dev/null);\n"; }
			system("ppmlabel -x 0 -y 24 -color orange -background transparent -size 20 -text \"$LABELS\" $DIR/$CAMERA/temp2.ppm > $DIR/$CAMERA/temp.ppm 2> /dev/null");
			if ( -e "$DIR/$CAMERA/temp.ppm" ) {  # File exists 
				system("convert $DIR/$CAMERA/temp.ppm $DIR/$CAMERA/temp.jpg");
				system("pnmscale -xsize=640 -ysize=480 $DIR/$CAMERA/temp.ppm > $DIR/$CAMERA/temp640.ppm");
				system("pnmscale -xsize=175 -ysize=131 $DIR/$CAMERA/temp640.ppm > $DIR/$CAMERA/temp175.ppm");
                                if ( -e "$DIR/$CAMERA/temp-old.ppm" ) {  # File exists 
                                    system("pnmarith -diff $DIR/$CAMERA/temp.ppm $DIR/$CAMERA/temp-old.ppm > $DIR/$CAMERA/tempdiff.ppm");
                                    system("pnmarith -diff $DIR/$CAMERA/temp175.ppm $DIR/$CAMERA/temp175-old.ppm > $DIR/$CAMERA/tempdiff175.ppm");
                                    system("convert -quality 70 $DIR/$CAMERA/tempdiff.ppm $DIR/$CAMERA/tempdiff.jpg"); 
                                    system("convert -quality 70 $DIR/$CAMERA/tempdiff175.ppm $DIR/$CAMERA/tempdiff175.jpg"); 
                                    rename("$DIR/$CAMERA/tempdiff.jpg","$DIR/$CAMERA/$CAMERA-diff.jpg");
                                    rename("$DIR/$CAMERA/tempdiff175.jpg","$DIR/$CAMERA/$CAMERA-diff175.jpg");
                                    system("cp $DIR/$CAMERA/$CAMERA-diff.jpg   $DIR/$CAMERA/$CAMERA-diff175.jpg $DEST");
                                }
				system("convert -quality 70 $DIR/$CAMERA/temp175.ppm $DIR/$CAMERA/temp175.jpg");
				system("convert -quality 70 $DIR/$CAMERA/temp640.ppm $DIR/$CAMERA/temp640.jpg");
				system("cp $DIR/$CAMERA/temp.jpg $DIR/$CAMERA/tempx.jpg");
				rename("$DIR/$CAMERA/tempx.jpg","$DIR/$CAMERA/$CAMERA.jpg");
				rename("$DIR/$CAMERA/temp175.jpg","$DIR/$CAMERA/$CAMERA-175.jpg");
				rename("$DIR/$CAMERA/temp640.jpg","$DIR/$CAMERA/$CAMERA-640.jpg");
				system("cp $DIR/$CAMERA/$CAMERA-640.jpg $DIR/$CAMERA/small/$dstamp/$APTAG/$time.jpg");
				system("chmod 644 $DIR/$CAMERA/*.jpg");
				rename("$DIR/$CAMERA/temp.jpg","$DIR/$CAMERA/large/$dstamp/$APTAG/$time.jpg");
				# Copy latest images to destination
                                system("convert $DIR/$CAMERA/$CAMERA.jpg $HPATH/hpwren8-400.png -gravity southeast -geometry +70+0 -composite $DEST/$CAMERA.jpg");
				system("cp $DIR/$CAMERA/$CAMERA-175.jpg $DIR/$CAMERA/$CAMERA-640.jpg $DEST");
				# If targetting c1 or c2, the call to updateanimations might need to go here
			} else {
				if ($DBG) { print "\tNo $DIR/$CAMERA/temp.ppm file\n"; }
			} 
		} else {  
			# No image available ... $R != 0
			if ($DBG) { print "\tFetch failed, R = $R\n"; }
			print $FH "$dtstamp: $ID Fetch failed, R = $R\n";
			if ($DBG) { print "\tsystem(\"cp $TVS $DIR/$CAMERA/$CAMERA-175.jpg\");  \n\t"; }
			system("cp $TVS $DIR/$CAMERA/$CAMERA-175.jpg");
			system("cp $TVS $DEST/$CAMERA-175.jpg");
		}
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
