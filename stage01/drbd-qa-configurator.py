#!/usr/bin/python

import getopt
import sys
from subprocess import * 
import time

#process opts
class DRBDQAConfigurator(object):

    def __init__(self):
        self.hosts = []
        self.ips = []
        self.block_device = '/dev/sdb1' #default

    def get_walrii_ips(self, filepath):
        data = open(filepath).readlines()
        for line in data:
            if "WS" in line:
                self.ips.append(line[:line.find("\t")])
           
    def get_hosts_from_ips(self):
        for ip in self.ips:
            cmd = ['ssh', 'root@%s' % ip, 'hostname']
            host_string = Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()
            self.hosts.append(host_string[0].split('\n')[0])
        if (len(self.hosts) != 2):
            print "Not enough configured walrii: skipping test"
            exit(1)

    def load_module(self):
        for ip in self.ips:
            cmd = ['ssh', 'root@%s' % ip, 'modprobe drbd']
            print Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()

    def check_disk(self):
        for ip in self.ips:
            cmd = ['ssh', 'root@%s' % ip, 'stat /dev/sdb']
            print cmd
            out = Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()
            if not out[0]:
                print "Could not find usable disk (sdb)...Aborting"
                exit(1)
            else:
                print out[0]

    def make_part(self):
        for ip in self.ips:
            cmd = ['ssh', 'root@%s' % ip, 'parted -s /dev/sdb unit GB mklabel msdos mkpart primary 0 30']
            print Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()

    def sync_config(self):
        #generate config
        cmd = ['./config-drbd.py', '--ip1=%s' % self.ips[0], '--ip2=%s' % self.ips[1], '--host1=%s' % self.hosts[0], '--host2=%s' % self.hosts[1], '--block-device=/dev/sdb1']
        drbd_config = Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()[0]
        if drbd_config:
            conf = open('drbd-euca.conf', 'w')
            conf.write(drbd_config)
            conf.close()
        #sync config and directory structure
        for ip in self.ips:
            cmd = ['ssh', 'root@%s' % ip, 'mkdir -p /etc/eucalyptus']
            print Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()
            cmd = ['scp', 'drbd.conf', 'root@%s:/etc/' % ip]
            print cmd
            print Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()
            cmd = ['scp', 'drbd-euca.conf', 'root@%s:/etc/eucalyptus/' % ip]
            print Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()

    def create_resource(self):
        for ip in self.ips:
            cmd = ['ssh', 'root@%s' % ip, 'drbdmeta --force /dev/drbd1 v08 /dev/sdb1 internal create-md']
            print Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()

    def connect_resource(self):
        for ip in self.ips:
            cmd = ['ssh', 'root@%s' % ip, 'drbdadm attach r0']
            print Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()
            cmd = ['ssh', 'root@%s' % ip, 'drbdadm connect r0']
            print Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()

    def init_resource(self):
        cmd = ['ssh', 'root@%s' % self.ips[0], 'drbdsetup /dev/drbd1 syncer -r 110M']
        print Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()
        cmd = ['ssh', 'root@%s' % self.ips[0], 'drbdadm -- --overwrite-data-of-peer primary r0']
        print Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()

    def wait_until_ready(self):
        while True:
            cmd = ['ssh', 'root@%s' % self.ips[0], 'drbdadm dstate r0']
            dstate = Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()[0]
            print dstate
            if 'Inconsistent' in dstate:
                time.sleep(5)
                continue
            else:
                break

    def usage(self):
        print "drbdqaconfigurator"

    def make_fs(self):
        cmd = ['ssh', 'root@%s' % self.ips[0], 'mkfs.ext3 /dev/drbd1']
        print Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()

    def cleanup_state(self):
        for ip in self.ips:
            cmd = ['ssh', 'root@%s' % ip, 'dmsetup ls | xargs -i dmsetup remove {}']
            print Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()

#configure this thing
drbdconfigurator = DRBDQAConfigurator()
drbdconfigurator.get_walrii_ips("../input/2b_tested.lst")
drbdconfigurator.get_hosts_from_ips()
#0 is master, 1 is slave

#make sure module is installed
drbdconfigurator.load_module()
drbdconfigurator.check_disk()
drbdconfigurator.make_part()
drbdconfigurator.sync_config()
drbdconfigurator.cleanup_state()
drbdconfigurator.create_resource()
drbdconfigurator.connect_resource()
drbdconfigurator.init_resource()
drbdconfigurator.wait_until_ready()
drbdconfigurator.make_fs()
