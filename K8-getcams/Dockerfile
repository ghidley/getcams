FROM centos:7

Run yum clean all ; yum -y update
RUN yum -y install perl ImageMagick netpbm netpbm-progs mlocate perl-App-cpanminus
RUN cpanm Proc::Reliable
WORKDIR /opt/getcams