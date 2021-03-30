# Makefile for initial install on new system of getcams
# Run as user hpwren
#
# Version 033021
#
#
ALLFILES=cam_access cam_access_format cam_params cleanlogs config_getcams_vars  config_runcam_vars getcams-axis.pl getcams-iqeye.pl getcams-mobo.pl getcams.service lockfiles Log4perl.conf logfiles Makefile Readme README.md run_cameras tvpattern.jpg tvpattern-small.jpg hpwren8-400.png Makefile .s3cfg-xfer 
RUNFILES=getcams-axis.pl getcams-iqeye.pl getcams-mobo.pl tvpattern-small.jpg run_cameras hpwren8-400.png Makefile cleanlogs config_getcams_vars config_runcam_vars
DEVFILES=getcams-axis.pl getcams-iqeye.pl getcams-mobo.pl run_cameras config_getcams_vars config_runcam_vars
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

ALLDIRS=$(CDIR) $(ARCHDIR) $(INCOMING) $(LOCALDIR) $(LOCKDIR) $(LOGDIR) $(RUNDIR) $(SYSLOCAL) 

echo:
	@echo Usage: make [update, install, all, root ...] -- software installation
	@echo Usage: make [test, start, stop, restart ...] -- getcams/runcams process management
	@echo Usage: make [enable, disable, status, sstart, resart, sstop ...] -- system service management
	

update:
	sudo -u hpwren cp $(DEVFILES) $(RUNDIR)

install:	
	mkdir -p $(ALLDIRS)
	-chown hpwren:hpwren $(ALLDIRS)
	chmod g+w $(ALLDIRS)
	#Following chmod may fail if on a ceph mounted file system
	-chmod g+s $(ALLDIRS)
	cp $(RUNFILES) $(RUNDIR)
	-chown hpwren:hpwren $(RUNDIR)/*
	@echo Copy $(CONTROLFILES) manually, or \"make install\" ...

all: install $(CONTROLFILES)
	sudo -u hpwren cp $(CONTROLFILES) $(RUNDIR)
	-chown hpwren:hpwren $(RUNDIR)/*

root:
	sudo mkdir -p $(ARCHDIR)
	sudo chown hpwren:hpwren $(ARCHDIR)
	sudo chmod g+w $(ARCHDIR)
	#Following chmod may fail if on a ceph mounted file system
	sudo chmod g+s $(ARCHDIR)
	sudo cp getcams.service /usr/lib/systemd/system
	sudo systemctl daemon-reload

# Testing section ...
test: 
	sudo -b -u hpwren ~hpwren/bin/getcams/run_cameras -I -D 

start: 
	sudo -b -u hpwren ~hpwren/bin/getcams/run_cameras -I 

restart:
	sudo -b -u hpwren ~hpwren/bin/getcams/run_cameras -R 

stop:
	sudo -b -u hpwren ~hpwren/bin/getcams/run_cameras -X 

# Service management section
sstart:
	sudo  systemctl start getcams.service
 
status: sstatus
sstatus:
	systemctl status getcams.service
 
srestart:
	sudo  systemctl restart getcams.service

sstop:
	sudo  systemctl stop getcams.service

enable: getcams.service 
	sudo  systemctl enable getcams.service

disable: getcams.service 
	sudo  systemctl disable getcams.service

cameras:	# Trigger running run_cameras to adjust active camera list
	sudo -u hpwren cp $(CONTROLFILES) $(RUNDIR)

sync-c52c0: #sync with c0 camacq1 git master --- run on c5 or other remote
	scp  getcams.service config_getcams_vars config_runcam_vars cleanlogs  getcams*.pl run_cameras Makefile c0:getcams/c5

sync-c02c5: #sync with c5 camacq1 git master --- run on c0 or other remote
	scp  getcams.service config_getcams_vars config_runcam_vars cleanlogs  getcams*.pl run_cameras Makefile c5:getcams/c0

