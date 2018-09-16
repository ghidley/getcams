# Makefile for initial install on new system of getcams
# Run as user hpwren
# Place getcams.service in confirmed location
# Once debugged, add and commit
#
DESTDIR=~hpwren/bin/getcams
LOCALDIR=/Data-local/tmp
ALLFILES=cam_access cam_access_format cam_params getcams-iqeye.pl getcams-mobo.pl getcams.service lockfiles Log4perl.conf logfiles Makefile Readme README.md run_cameras t tvpattern.jpg tvpattern-small.jpg updateanimations hpwren8-400.png
RUNFILES=getcams-iqeye.pl getcams-mobo.pl tvpattern-small.jpg run_cameras hpwren8-400.png
CONTROLFILES=cam_access_format cam_params cam_access
SYSLOCAL=/var/local/hpwren
LOCKDIR=$(SYSLOCAL)/lock
LOGDIR=$(SYSLOCAL)/log
DATADIR=/Data
ARCHDIR=/Data/archive
INCOMING=/Data/archive/incoming/cameras/tmp
install:	
	mkdir -p $(LOCALDIR)
	mkdir -p $(DESTDIR)
	mkdir -p $(DATADIR)
	mkdir -p $(ARCHDIR)
	mkdir -p $(SYSLOCAL)
	mkdir -p $(LOCKDIR)
	mkdir -p $(LOGDIR)
	mkdir -p $(INCOMING)
	chown hpwren:hpwren $(DESTDIR) $(SYSLOCAL) $(LOCKDIR) $(LOGDIR) $(DATADIR) $(ARCHDIR) $(INCOMING) $(LOCALDIR)
	chmod g+w $(DESTDIR) $(SYSLOCAL) $(LOCKDIR) $(LOGDIR) $(DATADIR) $(ARCHDIR) $(INCOMING)
	cp $(RUNFILES) $(DESTDIR)
	chown hpwren:hpwren $(DESTDIR)/*

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

all: install $(CONTROLFILES)
	cp $(CONTROLFILES) $(DESTDIR)
	chown hpwren:hpwren $(DESTDIR)/*

