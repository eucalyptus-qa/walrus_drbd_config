#!/usr/bin/perl

open (STDERR, ">&STDOUT");

$ec2timeout = 20;
$mode = shift @ARGV;

if( $mode eq "" ){
        my $this_mode = `cat ../input/2b_tested.lst | grep NETWORK`;
        chomp($this_mode);
        if( $this_mode =~ /^NETWORK\s+(\S+)/ ){
                $mode = lc($1);
        };
};

print "Mode:\t$mode \n\n";

if ($mode eq "managed-novlan" || $mode eq "system" || $mode eq "static") {
    $managed = 0;
} else {
    $managed = 1;
}

# clean up keypairs
$count=0;
system("date");
$cmd = "runat $ec2timeout ec2-describe-keypairs";
open(RFH, "$cmd|");
while(<RFH>) {
    chomp;
    my $line = $_;
    my ($tmp, $kp) = split(/\s+/, $line);
    if ($kp) {
	$kps[$count] = $kp;
	$count++;
    }
}
close(RFH);
if (@kps < 1) {
    print "WARN: could not get any keypairs from ec2-describe-keypairs\n";
} else {
    for ($i=0; $i<@kps; $i++) {
	system("date");
$cmd = "runat $ec2timeout ec2-delete-keypair $kps[$i]";
	$rc = system($cmd);
	if ($rc) {
	    print "ERROR: failed - '$cmd'\n";
	}
	system("rm $kps[$i].priv");
    }
}

# clean up groups
$count=0;
system("date");
$cmd = "runat $ec2timeout ec2-describe-group";
open(RFH, "$cmd|");
while(<RFH>) {
    chomp;
    my $line = $_;
    my ($type, $foo, $group) = split(/\s+/, $line);
    if ($type eq "GROUP") {
	if ($group && $group ne "default") {
	    $groups[$count] = $group;
	    $count++;
	}
    }
}
close(RFH);
if (@groups < 1) {
    print "WARN: could not get any groups from ec2-describe-group\n";
} else {
    for ($i=0; $i<@groups; $i++) {
	system("date");
$cmd = "runat $ec2timeout ec2-revoke $groups[$i] -P icmp -s 0.0.0.0/0 -t -1:-1";
	$rc = system($cmd);
	if ($rc) {
	    print "ERROR: failed - '$cmd'\n";
	}
	system("date");
$cmd = "runat $ec2timeout ec2-revoke $groups[$i] -P tcp -p 22 -s 0.0.0.0/0";
	$rc = system($cmd);
	if ($rc) {
	    print "ERROR: failed - '$cmd'\n";
	}
	system("date");
$cmd = "runat $ec2timeout ec2-delete-group $groups[$i]";
	$rc = system($cmd);
	if ($rc) {
	    print "ERROR: failed - '$cmd'\n";
	}
    }
}

if ($managed) {
# clean up addrs
    $count=0;
    system("date");
$cmd = "runat $ec2timeout ec2-describe-addresses | grep admin";
    open(RFH, "$cmd|");
    while(<RFH>) {
	chomp;
	my $line = $_;
	my ($tmp, $ip) = split(/\s+/, $line);
	if ($ip) {
	    $ips[$count] = $ip;
	    $count++;
	}
    }
    close(RFH);
    if (@ips < 1) {
	print "WARN: could not get any addrs from ec2-describe-addresses\n";
    } else {
	for ($i=0; $i<@ips; $i++) {
	    system("date");
$cmd = "runat $ec2timeout ec2-disassociate-address $ips[$i]";
	    $rc = system($cmd);
	    if ($rc) {
		print "ERROR: failed - '$cmd'\n";
	    }
	    $cmd = "ec2-release-address $ips[$i]";
	    $rc = system($cmd);
	    if ($rc) {
		print "ERROR: failed - '$cmd'\n";
	    }
	}
    }
}

$done=0;
for ($i=0; $i<10 && !$done; $i++) {
# clean up running instances
    chomp($instIds=`runat 15 ec2-describe-instances | grep INST | awk '{print \$2}'`);
    $instIds=~s/\n/ /g;
    print "INSTIDS: $instIds\n";
    if ($instIds) {
	system("date");
	$cmd = "runat $ec2timeout ec2-terminate-instances $instIds";
	$rc = system($cmd);
	if ($rc) {
	    print "ERROR: failed - '$cmd'\n";
	    $done++;
	} else {
	    sleep(5);
	}
    } else {
	$done++;
    }
}

exit(0);
