#!/usr/bin/python

import getopt
import sys
from subprocess import * 

#process opts
class DRBDConfigurator(object):

    DRBD_CONFIG = '''
global {
  usage-count no;
}
common {
  protocol C;
}

resource r0 {

  on %s {
    device    /dev/drbd1;
    disk      %s;
    address   %s:7789;
    meta-disk internal;
  }

  on %s {
    device    /dev/drbd1;
    disk      %s;
    address   %s:7789;
    meta-disk internal;
  }

  net {
    after-sb-0pri discard-zero-changes;
    after-sb-1pri discard-secondary;
  }
  
  syncer {
    rate 40M;
  }
}
    '''

    def __init__(self):
        self.host1 = None
        self.host2 = None
        self.ip1 = None
        self.ip2 = None
        self.block_device = '/dev/sdb1' #default
        self.qa = False 

    def parse_args(self):
        (opts, args) = getopt.gnu_getopt(sys.argv[1:],
                                         'hD:Q',
                                         ['help',
                                          'host1=',
                                          'host2=',
                                          'ip1=',
                                          'ip2=',
                                          'qa',
                                          'block-device='])
        for (name, value) in opts:
            if name in ('-h', '--help'):
                self.usage()
                sys.exit()
            elif name in ('--host1'):
                self.host1 = value
            elif name in ('--host2'):
                self.host2 = value
            elif name in ('--ip1'):
                self.ip1 = value
            elif name in ('--ip2'):
                self.ip2 = value
            elif name in ('-D', '--block-device'):
                self.block_device = value
            elif name in ('-Q', '--qa'):
                self.qa = True

    def get_walrii_ips(self, filepath):
        ips = []
        data = open(filepath).readlines()
        for line in data:
            if "WS" in line:
                ips.append(line[:line.find("\t")])
        return ips                     
           
    def get_hosts_from_ips(self, ips):
        hosts = []
        for ip in ips:
            cmd = ['ssh', 'root@%s' % ip, 'hostname']
            host_string = Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()
            print host_string
            hosts.append(host_string[0].split('\n')[0])
        return hosts

    def usage(self):
        print "drbdconfigurator"
#create config

drbdconfigurator = DRBDConfigurator()
drbdconfigurator.parse_args()
if drbdconfigurator.qa:
    ips = drbdconfigurator.get_walrii_ips("../input/2b_tested.lst")
    hosts = drbdconfigurator.get_hosts_from_ips(ips)
    #HACK HACK
    drbdconfigurator.host1 = hosts[0]
    drbdconfigurator.host2 = hosts[1]
    drbdconfigurator.ip1 = ips[0]
    drbdconfigurator.ip2 = ips[1]

print drbdconfigurator.DRBD_CONFIG % (drbdconfigurator.host1, drbdconfigurator.block_device, drbdconfigurator.ip1, drbdconfigurator.host2, drbdconfigurator.block_device, drbdconfigurator.ip2)
