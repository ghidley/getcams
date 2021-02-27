# Makefile for initial install on new system of getcams
# Run as user hpwren
# Place getcams.service in confirmed location
# Once debugged, add and commit
#
# Version 041419
#
## Set filesystem type for testing
## Once tested, set/update default in run_cameras

#
ALLFILES=cam_access cam_access_format cam_params getcams-axis.pl getcams-iqeye.pl getcams-mobo.pl getcams.service lockfiles Log4perl.conf logfiles Makefile Readme README.md run_cameras tvpattern.jpg tvpattern-small.jpg updateanimations hpwren8-400.png Makefile .s3cfg-xfer 
RUNFILES=getcams-axis.pl getcams-iqeye.pl getcams-mobo.pl tvpattern-small.jpg run_cameras hpwren8-400.png Makefile cleanlogs config_getcams_vars config_runcam_vars
ARCHDIR=/Data/archive
CDIR=$(ARCHDIR)/incoming/cameras
DATADIR=/Data
INCOMING=$(ARCHDIR)/incoming/cameras/tmp
RUNDIR=~hpwren/bin/getcams
CONTROLFILES=cam_access_format cam_params cam_access
LOCALDIR=/Data-local/scratch
SYSLOCAL=/var/local/hpwren
LOCKDIR=$(SYSLOCAL)/lock
LOGDIR=$(SYSLOCAL)/log

#ALLDIRS=$(CDIR) $(DATADIR) $(ARCHDIR) $(INCOMING) $(LOCALDIR) $(LOCKDIR) $(LOGDIR) $(RUNDIR) $(SYSLOCAL) 
ALLDIRS=$(CDIR) $(ARCHDIR) $(INCOMING) $(LOCALDIR) $(LOCKDIR) $(LOGDIR) $(RUNDIR) $(SYSLOCAL) 

install:	
	mkdir -p $(ALLDIRS)
	-chown hpwren:hpwren $(ALLDIRS)
	chmod g+w $(ALLDIRS)
	#Following chmod may fail if on a ceph mounted file system
	-chmod g+s $(ALLDIRS)
	cp $(RUNFILES) $(RUNDIR)
	-chown hpwren:hpwren $(RUNDIR)/*

test: testd
testd:
	sudo -b -u hpwren ~hpwren/bin/getcams/run_cameras -I -D 

start: testp
testp:
	sudo -b -u hpwren ~hpwren/bin/getcams/run_cameras -I 

restart:
	sudo -b -u hpwren ~hpwren/bin/getcams/run_cameras -R 

stop:
	sudo -b -u hpwren ~hpwren/bin/getcams/run_cameras -X 

Start:
	sudo  systemctl start getcams.service
 
status: Status
Status:
	systemctl status getcams.service
 
Restart:
	sudo  systemctl restart getcams.service

Stop:
	sudo  systemctl stop getcams.service

all: install $(CONTROLFILES)
	cp $(CONTROLFILES) $(RUNDIR)
	-chown hpwren:hpwren $(RUNDIR)/*

root:
	sudo mkdir -p $(ARCHDIR)
	sudo chown hpwren:hpwren $(ARCHDIR)
	sudo chmod g+w $(ARCHDIR)
	#Following chmod may fail if on a ceph mounted file system
	sudo chmod g+s $(ARCHDIR)
	sudo cp getcams.service /usr/lib/systemd/system
	sudo systemctl daemon-reload

enable: getcams.service 
	sudo  systemctl enable getcams.service

disable: getcams.service 
	sudo  systemctl disable getcams.service

cameras:	# Trigger running run_cameras to adjust active camera list
	sudo -u hpwren cp $(CONTROLFILES) $(RUNDIR)

sync: #sync with c0 camacq1 git master --- run on c5 or other (non c0) remote
	scp  getcams.service config_getcams_vars config_runcam_vars cleanlogs  getcams*.pl run_cameras Makefile c0:getcams/c5

