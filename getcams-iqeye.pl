#!/usr/bin/perl
$VERS="082916";
=begin comment
  getcams-iqeye.pl -- camera image fetch and processing script for iqeye cameras
  Based on getcamsmiqeyeanimations6.pl which was crontab driven
    (e.g. ...  hpwren ~hpwren/bin/getcams-iqeye.pl hpwren-iqeye7=login:201110\@   N  7 C "Cal Fire Ramona AAB, http://hpwren.ucsd.edu a2")
  
  Now camera control dictated by cam_params file, format of which is:
  #NAME:PROGRAM:TYPE:STARTUP_DELAY:"LABEL":RUN_ONE_MINUTE:CAPTURES/MINUTE
  #  hpwren-iqeye7:getcams-iqeye.pl:c:0:"Cal Fire Ramona AAB, http\://hpwren.ucsd.edu c1":1:1
      |             |               | |  |                                                | |Captures/minute
      |             |               | |  |                                                |0=>Run_forever/1=>Run_one_minute then exit
      |             |               | |  |Label                                           |Run_once used for debugging
      |             |               | |Startup delay seconds
      |             |               |Type (c=color m=infrared)
      |             |fetch script 
      |camera name (also IP host basename)

  Above parameters read in by run_cameras (parent script) and passed to this program as command line args:
    (e.g. getcams-iqeye.pl $CAMERA $TYPE $STARTUP_DELAY $LABEL $RUN_ONE_MINUTE $Camera_fetches_Per_Minute)

  Current version of code 
     1) fetches camera image 
     2) reformats image to multiple formats and diffs
     3) updates c1:/Data/archive and c1:/usr/LocalWeb/Boiler/Cameras/L (which is now in a zfs file system, /usr/LocalWeb => /Data/incoming )
     4) supports ongoing captures and adjustable captures per minute ($CPM) via cam_params with credentials from cam_access 
     5) logs to /path/to/logfiles/getcams-xxx-$CAMERA.log (start, fetchs, fails, exit)

=end comment
=cut

use File::Basename;
use Log::Log4perl;

# Passed in from run_cameras export
$DBG = 0; 
$DBG = "$ENV{DBG}" ;
$PATH = "$ENV{PATH}" ;
$HOME = "$ENV{HOME}" ;
$HPATH="$HOME/bin";
$LOGS = "$HPATH/logfiles";

$|++;  # Flush IO buffer at every print

# xxx Debug: Setting IPTEST to cam IP allows for camera testing without interfering with its production web data (if used with "testcam" label)
if ($ARGV[0] == "testcam"){$IPTEST = "172.16.249.20";} 

unless(-e $HPATH or mkdir $HPATH) { die "Unable to create $HPATH\n"; }
unless(-e $LOGS or mkdir $LOGS) { die "Unable to create $LOGS\n"; }

$TVS = "$HPATH/tvpattern-small.jpg";
$PW = "$HPATH/cam_access";  
$DIR="/Data/archive";
$BOILER= "/usr/LocalWeb/Boiler";
$L= "$BOILER/Cameras/L";   # Now in a zfs file system, /usr/LocalWeb => /Data/incoming, no longer using ramdisk
			   # Keep backward compatible path for legacy hpwren web page links to continue to work

#Check if we have enough ARGS
die "Insufficient args, got $#ARGV, need 5\n" if ( $#ARGV != 5 ) ;

$CAMERA=$ARGV[0]; 
$TYPE=$ARGV[1];    #c or n
$STARTUP_DELAY=$ARGV[2];
if($STARTUP_DELAY ne "0"){sleep($STARTUP_DELAY);} 
$LABEL=$ARGV[3];
if($LABEL eq ""){$LABEL="-";}
$LABEL =~ s/"//g; #Remove embedded quotes from label

#New added args ...
$RUN_ONE_MINUTE=$ARGV[4]; #This is the run_once flag from cam_params
$CPM=$ARGV[5];

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
if ($DBG) { print "\n  $dtstamp: $filename: [$$] Running $progname  0=$ARGV[0] 1=$ARGV[1] 2=$ARGV[2] \n\t3=$ARGV[3] 4=$ARGV[4] 5=$ARGV[5]\n" }
print $FH "$dtstamp: $ID Running v$VERS $progname  0=$ARGV[0] 1=$ARGV[1] 2=$ARGV[2] 3=$ARGV[3] 4=$ARGV[4] 5=$ARGV[5]\n";

#Fetch credentials from access file "cam_access"
# Format:
#    NAME:LOGIN:PASSWORD
<<<<<<< HEAD
=======
#    hpwren-iqeye7:login:201110
#    testcam-iqueye:login:201110
>>>>>>> a8f7ade101dc33fe0f64e3f77fe0547454580a14
# Note, if cam_access changes, run_cameras will restart this script

open FILE, '<', $PW or die "File $PW not found - $!\n";
while (<FILE>) {
	chomp;
	my @elements = split /:/, $_;
	next unless $elements[0] eq $CAMERA;
	$LOGIN = $elements[1];
	$PWD = $elements[2];
}
close FILE;

$WAIT_TIME = 60/$CPM;	#Time to wait between camera fetches

#$WAIT_TIME = 10; # Override calculated wait time for debugging
	
if ($LOGIN eq '') { die "$CAMERA credentials not found \n"; }

if ($DBG) {
	print "  \tRUN_ONE_MINUTE = $RUN_ONE_MINUTE, ";
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
	system("mkdir -p $DIR/$CAMERA/small/$dstamp/$APTAG 2> /dev/null");
	system("mkdir -p $DIR/$CAMERA/large/$dstamp/$APTAG 2> /dev/null");
} #End UpdateTimeStamp

if ($IPTEST) {
	$HOST= $IPTEST;
} else {
	$HOST= $CAMERA;
}

# Start outer while loop ... do just one cycle (if RUN_ONE_MINUTE is true) otherwise run continously
while ( 'true' ) {
	$ITERATIONS=1;
	while ($ITERATIONS <= $CPM) {# Start inner while loop, repeat CPM times
		UpdateTimeStamp();
		if ($DBG) {
			print "  capture $ITERATIONS of $CPM times\n";
			print "  system(\"curl -u $LOGIN:$PWD -o $DIR/$CAMERA/temp.jpg 'http://$HOST/now.jpg?jq=75&ds=1' 2> /dev/null\"); \n";
		}
		print $FH "$dtstamp: $ID system(\"curl -u $LOGIN:$PWD -o $DIR/$CAMERA/temp.jpg 'http://$HOST/now.jpg?jq=75&ds=1' 2> /dev/null\");\n";
		#$R=system("curl -o $DIR/$CAMERA/temp.jpg 'http://$LOGIN:$PWD:\@$HOST/now.jpg?jq=75&ds=1' 2> /dev/null");
		$R=system("curl -u $LOGIN:$PWD -o $DIR/$CAMERA/temp.jpg 'http://$HOST/now.jpg?jq=75&ds=1' 2> /dev/null");
		if($R == 0){
			if ($DBG) { print "  Fetch succeeded, R = $R, dtstamp = $dtstamp, LABEL = $LABEL\n"; }
			if ($DBG) { print "  system(\"cp $DIR/$CAMERA/temp.ppm $DIR/$CAMERA/temp-old.ppm\")\n"; }
			system("cp $DIR/$CAMERA/temp.ppm $DIR/$CAMERA/temp-old.ppm");
			rename("$DIR/$CAMERA/temp175.ppm","$DIR/$CAMERA/temp175-old.ppm");
			if ($DBG) { print "  system(\"convert $DIR/$CAMERA/temp.jpg $DIR/$CAMERA/temp2.ppm 2> /dev/null)\"\n"; }
			system("convert $DIR/$CAMERA/temp.jpg $DIR/$CAMERA/temp2.ppm 2> /dev/null");
			$LABELS="$dtstamp $LABEL";
			if ($DBG) { print "  system(ppmlabel -x 0 -y 20 -color orange -background transparent -size 20 -text \n\t\"$LABELS\" $DIR/$CAMERA/temp2.ppm > $DIR/$CAMERA/temp.ppm 2> /dev/null);\n"; }
			system("ppmlabel -x 0 -y 20 -color orange -background transparent -size 20 -text \"$LABELS\" $DIR/$CAMERA/temp2.ppm > $DIR/$CAMERA/temp.ppm 2> /dev/null");
			if ( -s "$DIR/$CAMERA/temp.ppm" ) {  # File exists and is not empty
				system("convert $DIR/$CAMERA/temp.ppm $DIR/$CAMERA/temp.jpg");
				system("pnmscale -xsize=640 -ysize=480 $DIR/$CAMERA/temp.ppm > $DIR/$CAMERA/temp640.ppm");
				system("pnmscale -xsize=175 -ysize=131 $DIR/$CAMERA/temp640.ppm > $DIR/$CAMERA/temp175.ppm");

				system("pnmarith -diff $DIR/$CAMERA/temp.ppm $DIR/$CAMERA/temp-old.ppm > $DIR/$CAMERA/tempdiff.ppm");
				system("pnmarith -diff $DIR/$CAMERA/temp175.ppm $DIR/$CAMERA/temp175-old.ppm > $DIR/$CAMERA/tempdiff175.ppm");
				system("cp $DIR/$CAMERA/temp.jpg $DIR/$CAMERA/tempx.jpg");
				system("convert -quality 70 $DIR/$CAMERA/temp175.ppm $DIR/$CAMERA/temp175.jpg");
				system("convert -quality 70 $DIR/$CAMERA/temp640.ppm $DIR/$CAMERA/temp640.jpg");
				system("convert -quality 70 $DIR/$CAMERA/tempdiff.ppm $DIR/$CAMERA/tempdiff.jpg"); 
				system("convert -quality 70 $DIR/$CAMERA/tempdiff175.ppm $DIR/$CAMERA/tempdiff175.jpg"); 
				rename("$DIR/$CAMERA/tempx.jpg","$DIR/$CAMERA/$CAMERA.jpg");
				rename("$DIR/$CAMERA/temp175.jpg","$DIR/$CAMERA/$CAMERA-175.jpg");
				rename("$DIR/$CAMERA/temp640.jpg","$DIR/$CAMERA/$CAMERA-640.jpg");
				system("cp $DIR/$CAMERA/$CAMERA-640.jpg $DIR/$CAMERA/small/$dstamp/$APTAG/$time.jpg");
				rename("$DIR/$CAMERA/tempdiff.jpg","$DIR/$CAMERA/$CAMERA-diff.jpg");
				rename("$DIR/$CAMERA/tempdiff175.jpg","$DIR/$CAMERA/$CAMERA-diff175.jpg");
				system("chmod 644 $DIR/$CAMERA/*.jpg");
				rename("$DIR/$CAMERA/temp.jpg","$DIR/$CAMERA/large/$dstamp/$APTAG/$time.jpg");
				# Copy latest images to BOILER area
				system("cp $DIR/$CAMERA/$CAMERA-175.jpg $DIR/$CAMERA/$CAMERA-640.jpg $DIR/$CAMERA/$CAMERA-diff.jpg   $DIR/$CAMERA/$CAMERA-diff175.jpg $DIR/$CAMERA/$CAMERA.jpg $L");
			} else {
				if ($DBG) { print "  No $DIR/$CAMERA/temp.ppm file\n"; }
			} 
		} else {  
			# No image available ... $R != 0
			if ($DBG) { print "  Fetch failed, R = $R\n"; }
			print $FH "$dtstamp: $ID Fetch failed, R = $R\n";
			system("cp $TVS $DIR/$CAMERA/$CAMERA-175.jpg");
		}
		if ($DBG) { print "  Sleeping $WAIT_TIME seconds ...\n"; }
		sleep($WAIT_TIME);
		last if ($ITERATIONS == $CPM ); 
		$ITERATIONS++;
	} # End inner while loop ... Runs $CPM times
	last if ($RUN_ONE_MINUTE || $DBG);  #Run for 1 cycle (1 or more fetches over a 1 minute period) then exit
} # End outer while loop

if ($DBG) { printf "  $progname [$$] exiting at $dtstamp\n" }
print $FH "$dtstamp: $ID Finished $progname\n";
close $FH;
