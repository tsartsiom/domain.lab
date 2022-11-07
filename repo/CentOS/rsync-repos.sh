#!/bin/sh

path='/media/share'

rsync -aHv --delete rsync://mirror.datacenter.by/CentOS/7/os $path/centos/7
rsync -aHv --delete rsync://mirror.datacenter.by/CentOS/7/extras $path/centos/7
rsync -aHv --delete rsync://mirror.datacenter.by/CentOS/7/updates $path/centos/7
rsync -aHv --delete --exclude "debug/" rsync://mirror.datacenter.by/fedora-epel/7/x86_64/ $path/centos/fedora-epel/7/x86_64
