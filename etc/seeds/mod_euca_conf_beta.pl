#!/usr/bin/perl
use strict;
use POSIX qw(ceil floor);

$ENV{'EUCALYPTUS'} = "/opt/eucalyptus";
$ENV{'EUCA_INSTANCES'} = "/disk1/storage/eucalyptus/instances";

my @multi_cluster_test_machines = ( "192.168.7.96", "192.168.7.97", "192.168.7.98", "192.168.7.99" );

$ENV{'EXTRA_OPS'} = "";

# default values
my $DISTRO = "UBUNTU";
my $VERSION = "";
my $ARCH = "";
my $SOURCE = "BZR";
my $ROLL = "NC";

($DISTRO, $VERSION, $ARCH, $SOURCE, $ROLL) = read_arguments(@ARGV);

print "[distro $DISTRO, version $VERSION, arch $ARCH, source $SOURCE, roll [$ROLL]]\n";

if( $SOURCE eq "PACKAGE" || $SOURCE eq "REPO" ){
        $ENV{'EUCALYPTUS'} = "";
};


### get my IP and CLC''s IP
get_my_ip();
get_clc_ip();

### set the default interface devices
$ENV{'PUB_INTERFACE'} = "eth0";
$ENV{'PRIV_INTERFACE'} = "eth0";


### detect the devices on the machine			--- disbled for R210. All pub and prib interfaces are on eth0 -- 121310
#detect_interfaces();

### below is for multi-cluster setup ... no need for 2 devices if on single-cluster mode
if( is_it_multi_clusters() == 0 || $ENV{'MY_IP'} eq $ENV{'CLC_IP'} ){			### CLC and CC cannot coexist in multi-cluster mode
	$ENV{'PRIV_INTERFACE'} = $ENV{'PUB_INTERFACE'};
}else{

	$ENV{'PRIV_INTERFACE'} = $ENV{'PUB_INTERFACE'};			### for R210 ENV

### NOT NEEDED for R210 Environment
#	foreach my $machine ( @multi_cluster_test_machines ){
#		if( $ENV{'MY_IP'} eq $machine ){
#			config_eth1();
#		};
#	};

};

post_ops_mod_euca_conf_add_java_home($DISTRO, $VERSION, $ARCH, $SOURCE, $ROLL);

post_ops_mod_euca_conf_add_nc_path($DISTRO, $VERSION, $ARCH, $SOURCE, $ROLL);

post_ops_mod_euca_conf_debian_special_case($DISTRO, $VERSION, $ARCH, $SOURCE, $ROLL);

post_ops_mod_euca_conf($DISTRO, $VERSION, $ARCH, $SOURCE, $ROLL);

post_ops_mod_euca_init($DISTRO, $VERSION, $ARCH, $SOURCE, $ROLL);

post_ops_setup_euca_conf($DISTRO, $VERSION, $ARCH, $SOURCE, $ROLL);

1;

sub config_eth1{

	my $priv_ip = "10.10.";

	get_my_cc_id();

	if( $ENV{MY_IP} =~ /192\.168\.(\d+)\.(\d+)/ ){
		my $priv_group = 10 + $ENV{'MY_CC_ID'};
		$priv_ip .= $priv_group . "." . $2;
		$ENV{'PRIV_IP'} = $priv_ip;
	};

#	system("ifconfig eth0 down");
	system("ifconfig $ENV{'PRIV_INTERFACE'} down");

	sleep(5);	

#	system("ifconfig eth0 " . $ENV{'MY_IP'} . " up" );
	system("ifconfig $ENV{'PRIV_INTERFACE'} " . $priv_ip . " netmask 255.255.255.0 up");

	print "\nMachine $ENV{'MY_IP'} configured PRIV_INTERFACE $ENV{'PRIV_INTERFACE'} with $priv_ip\n";

	my $result = `ifconfig`;
	print "\n" . $result . "\n";

	return 0;

};

sub detect_interfaces{

	my $scan = `ifconfig`;

	my @lines = split( "\n", $scan );

	my $interface = "";

	print "\n";
	foreach my $line (@lines){
		print $line . "\n";
		if( $line =~ /^(\w+)\s+Link encap/ ){
			$interface = $1;
		}elsif( $line =~ /inet addr:(192\.168\.\d+\.\d+)/) {
#			print $interface . " got IP " . $1 . "\n";
			$ENV{'PUB_INTERFACE'} = $interface;
		};
	};

	if( $ENV{'PUB_INTERFACE'} eq "eth0" || $ENV{'PUB_INTERFACE'} eq "br0" ){
		$ENV{'PRIV_INTERFACE'} = "eth1";
	}else{
		$ENV{'PRIV_INTERFACE'} = "eth0";
	};

	return 0;
};


sub get_my_ip{
        my $scan = `ifconfig | grep "inet addr"`;
        if( $scan =~ /(192\.168\.\d+\.\d+)/ ){
                $ENV{'MY_IP'} = $1;
        };
        return 0;
};

sub get_clc_ip{
        my $scan = `cat ./2b_tested.lst | grep CLC`;
        if( $scan =~ /(192\.168\.\d+\.\d+)/ ){
                $ENV{'CLC_IP'} = $1;
        };
        return 0;
};

sub get_my_cc_id{
        my $id = -1;
        my $scan = `cat ./2b_tested.lst | grep $ENV{'MY_IP'}`;
        chomp($scan);
        if( $scan =~ /CC(\d+)/ || $scan =~ /NC(\d+)/ ){
                $id = int($1);
		$ENV{'MY_CC_ID'} = $id;
        };
        return $id;
};


sub is_it_multi_clusters{
        open( TESTED, "< ./2b_tested.lst" ) or die $!;
        my $multi = 0;
        my $line;
        while( $line = <TESTED> ){
                chomp($line);
		if( $line =~ /^([\d\.]+)\t(.+)\t(.+)\t(\d+)\t(.+)\t\[(.+)\]/ ){
                        my $compo = $6;
                        while( $compo =~ /(\d+)(.+)/ ){
                                if( int($1) > $multi ){
                                        $multi = int($1);
                                };
                                $compo = $2;
                        };
                };
        };
        close(TESTED);
        return $multi;
};




# does_It_Have( $arg1, $arg2 )
# does the string $arg1 have $arg2 in it ??
sub does_It_Have{
        my ($string, $target) = @_;
        if( $string =~ /$target/ ){
                return 1;
        };
        return 0;
};

sub get_network_mode{
        my $mode = "";
        open( TESTED, "< ./2b_tested.lst" ) or die $!;

        my $line;
        while( $line = <TESTED> ){
                chomp($line);
                if( $line =~ /^NETWORK\s+(.+)/ ){
                        $mode = $1;
			chomp($mode);
                        $mode =~ s/\r//g;
                };
        };
        close( TESTED );
        return $mode;
};


sub get_managed_ips{

        my $is_multi = is_it_multi_clusters();

        my $ips = "";
        open( TESTED, "< ./2b_tested.lst" ) or die $!;

        my $line;
        while( $line = <TESTED> ){
                chomp($line);
                if( $line =~ /^MANAGED_IPS\s+(.+)/ ){
                        $ips = $1;
			chomp($ips);
			$ips =~ s/\r//g;
                };
        };
        close( TESTED );

        if( $is_multi > 0 ){
                my $cc_id = get_my_cc_id();
                if( $cc_id != -1 ){
                        my @ip_array = split( " ", $ips );
                        my $ip_count = @ip_array;
                        foreach my $this_ip ( sort @ip_array ){
#                               print $this_ip . "\n";
                        };

                        my $sub_ip_count = floor($ip_count / ($is_multi+1));
                        my $lower_limit = $sub_ip_count * $cc_id;
                        $ips = "";
                        for( my $i = 0; $i < $ip_count; $i++ ){
                                if( $i >= $lower_limit && $i < $sub_ip_count + $lower_limit){
                                        $ips .= $ip_array[$i] . " ";
                                };
                        };
			chop($ips);
                };

        };
        return $ips;
};


sub get_subnet_ip{
        my $ips = "";
        open( TESTED, "< ./2b_tested.lst" ) or die $!;
                                        
        my $line;
        while( $line = <TESTED> ){
                chomp($line);
                if( $line =~ /^SUBNET_IP\s+(.+)/ ){
                        $ips = $1;
			chomp($ips);
                        $ips =~ s/\r//g;
                };
        };
        close( TESTED );
        return $ips;
};

sub post_ops_mod_euca_init{

	my ($DISTRO, $VERSION, $ARCH, $SOURCE, $ROLL) = @_;

        my $euca_init_dir = "/etc/init.d";

	$euca_init_dir = $ENV{'EUCALYPTUS'} . $euca_init_dir;

	my $euca_init_cloud = $euca_init_dir . "/eucalyptus-cloud";

	if( $ENV{'EXTRA_OPS'} eq "" ){
		my_sed( "local OPTS=\"\"", "local OPTS=\"--log-level=DEBUG\"", $euca_init_cloud );
	}elsif( $ENV{'EXTRA_OPS'} eq "DB-DEBUG" ){
		my_sed( "local OPTS=\"\"", "local OPTS=\"--log-level=DEBUG --exhaustive-db\"", $euca_init_cloud );
	};
	
#	my $euca_init_sc = $euca_init_dir . "/eucalyptus-sc";
#        my_sed( "local OPTS=\"\"", "local OPTS=\"--log-level=DEBUG\"", $euca_init_sc );

#	my $euca_init_walrus = $euca_init_dir . "/eucalyptus-walrus";
#        my_sed( "local OPTS=\"\"", "local OPTS=\"--log-level=DEBUG\"", $euca_init_walrus );

	return 0;

};

sub post_ops_mod_euca_conf{
	
	my ($DISTRO, $VERSION, $ARCH, $SOURCE, $ROLL) = @_;

	my $euca_conf = "/etc/eucalyptus/eucalyptus.conf";
	$euca_conf = $ENV{'EUCALYPTUS'} . $euca_conf;

        $ENV{'BUILD_NETWORK'} = get_network_mode();
	if( $ENV{'BUILD_NETWORK'} eq "" ){
		$ENV{'BUILD_NETWORK'} = "MANAGED";
	};

	### little trick for NC in multi-cluster mode
	if( does_It_Have($ROLL, "NC") && is_it_multi_clusters() > 0 ){
		$ENV{'PUB_INTERFACE'} = $ENV{'PRIV_INTERFACE'};
	};

	if( $DISTRO eq "UBUNTU" ){
		
		my_sed( "VNET_PUBINTERFACE=\"eth0\"", "VNET_PUBINTERFACE=\"$ENV{'PUB_INTERFACE'}\"", $euca_conf );
		my_sed( "VNET_PRIVINTERFACE=\"eth0\"", "VNET_PRIVINTERFACE=\"$ENV{'PRIV_INTERFACE'}\"", $euca_conf );

		if( does_It_Have($ROLL, "NC") ){
			if( $ENV{'BUILD_NETWORK'} eq "MANAGED" ){
				my_sed( "VNET_BRIDGE=\"xenbr0\"", "VNET_BRIDGE=\"$ENV{'PUB_INTERFACE'}\"", $euca_conf );
			}elsif( $ENV{'BUILD_NETWORK'} eq "SYSTEM" || $ENV{'BUILD_NETWORK'} eq "MANAGED-NOVLAN" || $ENV{'BUILD_NETWORK'} eq "STATIC"  ){
				my_sed( "VNET_BRIDGE=\"xenbr0\"", "VNET_BRIDGE=\"br0\"", $euca_conf );
			}else{
				# ERROR !!!
			};
		};

		if( does_It_Have($ROLL, "CC") ){
			my_sed( "VNET_DHCPDAEMON=\"\/usr\/sbin\/dhcpd\"", "VNET_DHCPDAEMON=\"\/usr\/sbin\/dhcpd3\"", $euca_conf );
			my_sed( "#VNET_DHCPUSER=\"root\"", "VNET_DHCPUSER=\"dhcpd\"", $euca_conf );
		};

	}elsif( $DISTRO eq "DEBIAN" ){

		my_sed( "VNET_PUBINTERFACE=\"eth0\"", "VNET_PUBINTERFACE=\"$ENV{'PUB_INTERFACE'}\"", $euca_conf );
		my_sed( "VNET_PRIVINTERFACE=\"eth0\"", "VNET_PRIVINTERFACE=\"$ENV{'PRIV_INTERFACE'}\"", $euca_conf );

		if( does_It_Have($ROLL, "NC") ){
			if( $ENV{'BUILD_NETWORK'} eq "MANAGED" ){
				my_sed( "VNET_BRIDGE=\"xenbr0\"", "VNET_BRIDGE=\"$ENV{'PUB_INTERFACE'}\"", $euca_conf );
			}elsif( $ENV{'BUILD_NETWORK'} eq "SYSTEM" || $ENV{'BUILD_NETWORK'} eq "MANAGED-NOVLAN" || $ENV{'BUILD_NETWORK'} eq "STATIC"  ){
				my_sed( "VNET_BRIDGE=\"xenbr0\"", "VNET_BRIDGE=\"br0\"", $euca_conf );
			}else{
				# ERROR !!!
			};
#			my_sed( "VNET_BRIDGE=\"xenbr0\"", "VNET_BRIDGE=\"br0\"", $euca_conf );
		};

		if( does_It_Have($ROLL, "CC") ){
			### changed back ... 091010
			my_sed( "VNET_DHCPDAEMON=\"\/usr\/sbin\/dhcpd3\"", "VNET_DHCPDAEMON=\"\/usr\/sbin\/dhcpd\"", $euca_conf );

			### changed in squeeze
			#my_sed( "VNET_DHCPDAEMON=\"\/usr\/sbin\/dhcpd\"", "VNET_DHCPDAEMON=\"\/usr\/sbin\/dhcpd3\"", $euca_conf );
			#my_sed( "#VNET_DHCPUSER=\"root\"", "VNET_DHCPUSER=\"dhcpd\"", $euca_conf );
		};

	}elsif( $DISTRO eq "OPENSUSE" ){

		if( does_It_Have($ROLL, "NC") ){
			if( $ENV{'BUILD_NETWORK'} eq "MANAGED" ){
				my_sed( "VNET_BRIDGE=\"xenbr0\"", "VNET_BRIDGE=\"$ENV{'PUB_INTERFACE'}\"", $euca_conf );
			};
#			my_sed( "VNET_BRIDGE=\"xenbr0\"", "VNET_BRIDGE=\"eth0\"", $euca_conf );
		};

	}elsif( $DISTRO eq "SLES" ){

                my_sed( "VNET_INTERFACE=\"eth0\"", "VNET_INTERFACE=\"br0\"", $euca_conf );

	}elsif( $DISTRO eq "CENTOS" || $DISTRO eq "RHEL" ){

		my_sed( "VNET_PUBINTERFACE=\"eth0\"", "VNET_PUBINTERFACE=\"$ENV{'PUB_INTERFACE'}\"", $euca_conf );
		my_sed( "VNET_PRIVINTERFACE=\"eth0\"", "VNET_PRIVINTERFACE=\"$ENV{'PRIV_INTERFACE'}\"", $euca_conf );

		if( $DISTRO eq "RHEL" && $VERSION eq "6.0" &&  does_It_Have($ROLL, "NC") ){
			if( $ENV{'BUILD_NETWORK'} eq "MANAGED" ){
				my_sed( "VNET_BRIDGE=\"xenbr0\"", "VNET_BRIDGE=\"$ENV{'PUB_INTERFACE'}\"", $euca_conf );
			}elsif( $ENV{'BUILD_NETWORK'} eq "SYSTEM" || $ENV{'BUILD_NETWORK'} eq "MANAGED-NOVLAN" || $ENV{'BUILD_NETWORK'} eq "STATIC"  ){
				my_sed( "VNET_BRIDGE=\"xenbr0\"", "VNET_BRIDGE=\"br0\"", $euca_conf );
			}else{
				# ERROR !!!
			};
#			my_sed( "VNET_BRIDGE=\"xenbr0\"", "VNET_BRIDGE=\"$ENV{'PUB_INTERFACE'}\"", $euca_conf );

			my_sed( "USE_VIRTIO_DISK=\"0\"", "USE_VIRTIO_DISK=\"1\"", $euca_conf );
			my_sed( "USE_VIRTIO_ROOT=\"0\"", "USE_VIRTIO_ROOT=\"1\"", $euca_conf );
			my_sed( "USE_VIRTIO_NET=\"0\"", "USE_VIRTIO_NET=\"1\"", $euca_conf );
		};

	}elsif( $DISTRO eq "FEDORA" ){

                my_sed( "VNET_PUBINTERFACE=\"eth0\"", "VNET_PUBINTERFACE=\"$ENV{'PUB_INTERFACE'}\"", $euca_conf );
                my_sed( "VNET_PRIVINTERFACE=\"eth0\"", "VNET_PRIVINTERFACE=\"$ENV{'PRIV_INTERFACE'}\"", $euca_conf );

		if( does_It_Have($ROLL, "NC") ){
			if( $ENV{'BUILD_NETWORK'} eq "MANAGED" ){
                                my_sed( "VNET_BRIDGE=\"xenbr0\"", "VNET_BRIDGE=\"$ENV{'PUB_INTERFACE'}\"", $euca_conf );
                        }elsif( $ENV{'BUILD_NETWORK'} eq "SYSTEM" || $ENV{'BUILD_NETWORK'} eq "MANAGED-NOVLAN" || $ENV{'BUILD_NETWORK'} eq "STATIC" ){
                                my_sed( "VNET_BRIDGE=\"xenbr0\"", "VNET_BRIDGE=\"br0\"", $euca_conf );
                        }else{
                                # ERROR !!!
                        };
		};
	}else{
		# error !
	};

	if( does_It_Have($ROLL, "CC") ){
		my_sed( "#VNET_CLOUDIP=.*", "VNET_CLOUDIP=\"$ENV{'CLC_IP'}\"", $euca_conf );
		#my_sed( "#VNET_LOCALIP=\"your-public-interface\'s-ip\"", "VNET_LOCALIP=\"localhost\"", $euca_conf );
		
		if( $ENV{'BUILD_NETWORK'} eq "MANAGED" || $ENV{'BUILD_NETWORK'} eq "MANAGED-NOVLAN" ){
			# MANAGED MODE setup
			my_sed( "#VNET_NETMASK=\"255.255.0.0\"", "VNET_NETMASK=\"255.255.0.0\"", $euca_conf );
			my_sed( "#VNET_DNS=\"your-dns-server-ip\"", "VNET_DNS=\"192.168.7.1\"", $euca_conf );
			my_sed( "#VNET_ADDRSPERNET=\"32\"", "VNET_ADDRSPERNET=\"32\"", $euca_conf );

			my $subnet_ip = get_subnet_ip();
			my_sed( "#VNET_SUBNET=\"192.168.0.0\"", "VNET_SUBNET=\"$subnet_ip\"", $euca_conf );
					
			my $managed_ips = get_managed_ips();
			my_sed( "#VNET_PUBLICIPS=\"your-free-public-ip-1 your-free-public-ip-2 ...\"", "VNET_PUBLICIPS=\"$managed_ips\"", $euca_conf );
					
		}elsif( $ENV{'BUILD_NETWORK'} eq "STATIC" ){
			# STATIC MODE setup
			my $subnet_ip = get_subnet_ip();
			my_sed( "#VNET_SUBNET=\"192.168.1.0\"", "VNET_SUBNET=\"192.168.0.0\"", $euca_conf );
			my_sed( "#VNET_NETMASK=\"255.255.255.0\"", "VNET_NETMASK=\"255.255.192.0\"", $euca_conf );
			my_sed( "#VNET_BROADCAST=\".*\"", "VNET_BROADCAST=\"192.168.63.255\"", $euca_conf );
			my_sed( "#VNET_ROUTER=\".*\"", "VNET_ROUTER=\"192.168.7.1\"", $euca_conf );
			my_sed( "#VNET_DNS=\".*\"", "VNET_DNS=\"192.168.7.1\"", $euca_conf );

			my $managed_ips = get_managed_ips();
			my $macmap =  get_static_macmap($managed_ips);
			my_sed( "#VNET_MACMAP=\".*\"", "VNET_MACMAP=\"$macmap\"", $euca_conf );
		};
	};

	if( $ENV{'BUILD_NETWORK'} eq "SYSTEM" ){
		# do noting..
	}else{
		my_sed( "VNET_MODE=\"SYSTEM\"", "#VNET_MODE=\"SYSTEM\"", $euca_conf );
		if( $ENV{'BUILD_NETWORK'} eq "MANAGED" ){
			my_sed( "#VNET_MODE=\"MANAGED\"", "VNET_MODE=\"MANAGED\"", $euca_conf );
		}elsif( $ENV{'BUILD_NETWORK'} eq "MANAGED-NOVLAN" ){
			my_sed( "#VNET_MODE=\"MANAGED\"", "VNET_MODE=\"MANAGED-NOVLAN\"", $euca_conf );
		}elsif( $ENV{'BUILD_NETWORK'} eq "STATIC" ){
			my_sed( "#VNET_MODE=\"STATIC\"", "VNET_MODE=\"STATIC\"", $euca_conf );
		};
	};

	if( $ENV{'BUILD_NETWORK'} eq "MANAGED-NOVLAN" ){
		system("echo \"VNET_MACPREFIX=\\\"D0:D0\\\"\" >> $euca_conf ");
	};

	####### EXTRA OPS from MEMO #######

	### VNET_NETMASK modification
	if( $ENV{'BUILD_NETWORK'} eq "MANAGED" || $ENV{'BUILD_NETWORK'} eq "MANAGED-NOVLAN" ){
		if( is_set_vnet_netmask_from_memo() ){
			my $new_vnet_netmask = $ENV{'QA_MEMO_SET_VNET_NETMASK'};
			my_sed( "VNET_NETMASK=\".*\"", "VNET_NETMASK=\"" . $new_vnet_netmask . "\"", $euca_conf );
		};
	};

	return 0;
};


#eucalyptus configuration initial setup
sub post_ops_setup_euca_conf{
        my ($DISTRO) = shift;
	my ($VERSION) = shift;

        if( $DISTRO eq "UBUNTU" || $DISTRO eq "DEBIAN" || $DISTRO eq "FEDORA" || ($DISTRO eq "RHEL" && $VERSION eq "6.0")  ){
		if( $ENV{'EUCALYPTUS'} eq "" ){
			system("$ENV{'EUCALYPTUS'}/usr/sbin/euca_conf -d / --hypervisor=kvm --instances=$ENV{'EUCA_INSTANCES'} --user=eucalyptus --setup");
		}else{
                	system("$ENV{'EUCALYPTUS'}/usr/sbin/euca_conf -d $ENV{'EUCALYPTUS'} --hypervisor=kvm --instances=$ENV{'EUCA_INSTANCES'} --user=eucalyptus --setup");
		};
        }elsif( $DISTRO eq "OPENSUSE" || $DISTRO eq "CENTOS" || $DISTRO eq "SLES" || ($DISTRO eq "RHEL" && $VERSION eq "5.5") ){
		if( $ENV{'EUCALYPTUS'} eq "" ){
                        system("$ENV{'EUCALYPTUS'}/usr/sbin/euca_conf -d / --hypervisor=xen --instances=$ENV{'EUCA_INSTANCES'} --user=eucalyptus --setup");
                }else{
                	system("$ENV{'EUCALYPTUS'}/usr/sbin/euca_conf -d $ENV{'EUCALYPTUS'} --hypervisor=xen --instances=$ENV{'EUCA_INSTANCES'} --user=eucalyptus --setup");
		};
        }else{
                # error!
        };
};


### misleading function name. This is where the first euca_conf modification takes place... 060111
sub post_ops_mod_euca_conf_add_java_home{

	my ($DISTRO, $VERSION, $ARCH, $SOURCE, $ROLL) = @_;

	my $bzr = $ENV{'QA_BZR_DIR'};

        my $euca_conf = "/etc/eucalyptus/eucalyptus.conf";
        $euca_conf = $ENV{'EUCALYPTUS'} . $euca_conf;

	my $cloud_opts = "";

	set_java_home_env();

	my $ebs_storage_manager = "NO-SAN";

	my $san_provider = "NO-SAN";

	if( is_san_provider_from_memo() == 1){
		$san_provider = $ENV{'QA_MEMO_SAN_PROVIDER'};
	};

	if( is_ebs_storage_manager_from_memo() == 1){
		$ebs_storage_manager = $ENV{'QA_MEMO_EBS_STORAGE_MANAGER'};
	};

	if( $ENV{'EXTRA_OPS'} eq "NO-SAN" || $ebs_storage_manager eq "NO-SAN" ){
		$cloud_opts = "--java-home=" . $ENV{'JAVA_HOME'};
	}else{
		### temp solution 112410 for PUMA
#		if( $VERSION eq "LUCID" && ( $SOURCE eq "PACKAGE" || $SOURCE eq "REPO" ) ){

		### Fix for SAN_PROVIDER option		040511
#		if( $bzr =~ /eee-2\.0/ ){
#			$cloud_opts = "--java-home=/opt/packages/jdk1.6.0_16/ -Debs.storage.manager=SANManager -Debs.san.provider=NetappProvider";
#		}else{
#			$cloud_opts = "--java-home=" . $ENV{'JAVA_HOME'} . " -Debs.storage.manager=SANManager -Debs.san.provider=EquallogicProvider";
#		};

#		$cloud_opts = "--java-home=" . $ENV{'JAVA_HOME'} . " -Debs.storage.manager=SANManager -Debs.san.provider=" . $san_provider;

		$cloud_opts = "--java-home=" . $ENV{'JAVA_HOME'} . " -Debs.storage.manager=" . $ebs_storage_manager;

		if( !($san_provider eq "NO-SAN") )  {
			$cloud_opts = $cloud_opts . " -Debs.san.provider=" . $san_provider;
		};

	};

	if( is_extra_cloud_opts_from_memo() ){
		$cloud_opts .= " " . $ENV{'EXTRA_CLOUD_OPTS'};
	};

	if(is_walrus_backend_from_memo() ) {
		$cloud_opts .= " -Dwalrus.storage.manager=" . $ENV{'WALRUS_BACKEND'};
	}
        
	my_sed( "CLOUD_OPTS=\".*\"", "CLOUD_OPTS=\"" . $cloud_opts . "\"", $euca_conf );


	return 0;
};


sub post_ops_mod_euca_conf_add_nc_path{

	my ($DISTRO, $VERSION, $ARCH, $SOURCE, $ROLL) = @_;

        my $euca_conf = "/etc/eucalyptus/eucalyptus.conf";
        $euca_conf = $ENV{'EUCALYPTUS'} . $euca_conf;

        if( $DISTRO eq "CENTOS" || $DISTRO eq "OPENSUSE" || $DISTRO eq "FEDORA" || $DISTRO eq "RHEL" ){
		my_sed( "# NC_BUNDLE_UPLOAD_PATH=\"not_configured\"", "NC_BUNDLE_UPLOAD_PATH=\"/usr/bin/euca-bundle-upload\"", $euca_conf );
		my_sed( "# NC_CHECK_BUCKET_PATH=\"not_configured\"", "NC_CHECK_BUCKET_PATH=\"/usr/bin/euca-check-bucket\"", $euca_conf );
		my_sed( "# NC_DELETE_BUNDLE_PATH=\"not_configured\"", "NC_DELETE_BUNDLE_PATH=\"/usr/bin/euca-delete-bundle\"", $euca_conf );

        };

        return 0;

};


sub post_ops_mod_euca_conf_debian_special_case{

	my ($DISTRO, $VERSION, $ARCH, $SOURCE, $ROLL) = @_;

        my $euca_conf = "/etc/eucalyptus/eucalyptus.conf";
        $euca_conf = $ENV{'EUCALYPTUS'} . $euca_conf;

        if( $DISTRO eq "DEBIAN" && does_It_Have($ROLL, "NC")  ){
                my_sed( "USE_VIRTIO_DISK=\"0\"", "USE_VIRTIO_DISK=\"1\"", $euca_conf );
        };
        return 0;
};





# Usage :: perl <script.pl> <distro> <source> <roll>
# $distro = which distribution ?
# $source = source of installation package ?
# $roll = Compute Control ? Cloud Control ? or Node Control?
sub read_arguments{

	my @my_ARGV = @_;
	my $distro = "UBUNTU";
	my $version = "";
	my $arch = "";
	my $source = "TARBALL";
	my $roll = "";

	read_input_file();

	$distro = $my_ARGV[0];
	$version = $my_ARGV[1];
	$arch = $my_ARGV[2];
	$source = $my_ARGV[3];

	my $i;
	for( $i = 4; $i < @my_ARGV; $i++){
		if( $my_ARGV[$i] eq "NC" || $my_ARGV[$i] eq "CC" || $my_ARGV[$i] eq "CLC" || $my_ARGV[$i] eq "SC" || $my_ARGV[$i] eq "WS" ){
			$roll = $roll . "$my_ARGV[$i]" . " ";
		}elsif( $my_ARGV[$i] eq "DB-DEBUG" ){
			$ENV{'EXTRA_OPS'} = "DB-DEBUG";
		}elsif( $my_ARGV[$i] eq "NO-SAN" ){
                        $ENV{'EXTRA_OPS'} = "NO-SAN";
		}elsif( $my_ARGV[$i] eq "DEV" ){
                        print "This machine is built for TEST-DEV\n";
                        exit(0);
		}else{
			print "ERROR!!\n";
			print "INVALID ARGUMENT[$i] = $my_ARGV[$i]\n";
			print "<roll> can only be NC, CC, CLC, SC, or WS\n";
			exit(1); 
		};
	};

	chomp($roll);

	return ($distro, $version, $arch, $source, $roll);
};

# To make 'sed' command human-readable
# my_sed( target_text, new_text, filename);
#   --->
#        sed --in-place 's/ <target_text> / <new_text> /' <filename>
sub my_sed{

        my ($from, $to, $file) = @_;

        $from =~ s/([\'\"\/])/\\$1/g;
        $to =~ s/([\'\"\/])/\\$1/g;

        my $cmd = "sed --in-place 's/" . $from . "/" . $to . "/' " . $file;

        system("$cmd");

        return 0;
};


sub is_extra_cloud_opts_from_memo{
	if( $ENV{'QA_MEMO'} =~ /CLOUD_OPTS=(.+)\n/ ){
		my $cloud_opts = $1;
		$cloud_opts =~ s/\r//g;
		print "FOUND in MEMO\n";
		print "CLOUD_OPTS=$cloud_opts\n";
		$ENV{'EXTRA_CLOUD_OPTS'} = $cloud_opts;
		return 1;
	};
	return 0;
};

sub is_walrus_backend_from_memo{
	if( $ENV{'QA_MEMO'} =~ /WALRUS_BACKEND=(.+)\n/ ){
		my $walrusbackend = $1;
		$walrusbackend =~ s/\r//g;
		print "FOUND in MEMO\n";
		print "WALRUS_BACKEND=$walrusbackend\n";
		$ENV{'WALRUS_BACKEND'} = $walrusbackend;
		return 1;
	};
	return 0;
};



sub is_java_home_from_memo{
	if( $ENV{'QA_MEMO'} =~ /JAVA_HOME=(.+)\n/ ){
		my $extra = $1;
		$extra =~ s/\r//g;
		print "FOUND in MEMO\n";
		print "JAVA_HOME=$extra\n";
		$ENV{'JAVA_HOME'} = $extra;
		return 1;
	};
	return 0;
};


sub is_san_provider_from_memo{
	if( $ENV{'QA_MEMO'} =~ /SAN_PROVIDER=(.+)\n/ ){
		my $extra = $1;
		$extra =~ s/\r//g;
		print "FOUND in MEMO\n";
		print "SAN_PROVIDER=$extra\n";
		$ENV{'QA_MEMO_SAN_PROVIDER'} = $extra;
		return 1;
	};
	return 0;
};


sub is_ebs_storage_manager_from_memo{
	if( $ENV{'QA_MEMO'} =~ /EBS_STORAGE_MANAGER=(.+)\n/ ){
		my $extra = $1;
		$extra =~ s/\r//g;
		print "FOUND in MEMO\n";
		print "EBS_STORAGE_MANAGER=$extra\n";
		$ENV{'QA_MEMO_EBS_STORAGE_MANAGER'} = $extra;
		return 1;
	};
	return 0;
};


sub read_input_file{
	open( LIST, "./2b_tested.lst" ) or return 1;
	my $is_memo;
	my $memo = "";

	my $line;
	while( $line = <LIST> ){
		chomp($line);
		if( $is_memo ){
			if( $line ne "END_MEMO" ){
				$memo .= $line . "\n";
			};
		};
		if( $line =~ /^(.+)\t(.+)\t(.+)\t(\d+)\t(.+)\t\[(.+)\]/ ){
			### below aren't used for now
			$ENV{'QA_DISTRO'} = $2;
			$ENV{'QA_DISTRO_VER'} = $3;
			$ENV{'QA_ARCH'} = $4;
			$ENV{'QA_SOURCE'} = $5;
		}elsif( $line =~ /^BZR_BRANCH\t(.+)/ ){
			my $temp = $1;
			chomp($temp);
                        $temp =~ s/\r//g;
			if( $temp =~ /eucalyptus\/(.+)/ ){
				$ENV{'QA_BZR_DIR'} = $1; 
			};
		}elsif( $line =~ /^MEMO/ ){
			$is_memo = 1;
		}elsif( $line =~ /^END_MEMO/ ){
			$is_memo = 0;
		};		
	};
	close(LIST);

	$ENV{'QA_MEMO'} = $memo;

	return 0;
};


### Set up the ENV variable for 'JAVA_HOME'
sub set_java_home_env{

	my $distro = $ENV{'QA_DISTRO'};
	my $distro_ver = $ENV{'QA_DISTRO_VER'};
	my $arch = $ENV{'QA_ARCH'};
	my $source = $ENV{'QA_SOURCE'};
	my $bzr = $ENV{'QA_BZR_DIR'};

	if( is_use_default_java_home_from_memo() == 1 ){
		$ENV{'JAVA_HOME'} = get_java_home_path_on_conf();
		print "\nUsing the configuration's default JAVA_HOME = $ENV{'JAVA_HOME'}\n";
		return 0;
	}; 

	if( is_java_home_from_memo() == 1 ){
		return 0;
	};

	if( $bzr =~ /eee/ ){

		my $prefix_dir = "/opt/eucalyptus";

		if( $arch eq "64" ){
			$ENV{'JAVA_HOME'}="$prefix_dir/packages/java/jdk1.6.0_16";
		}else{
			$ENV{'JAVA_HOME'}="$prefix_dir/packages/java/jdk1.6.0_18";
		};
	}else{
		if( $distro eq "UBUNTU" ){
			$ENV{'JAVA_HOME'}='/usr/lib/jvm/java-6-openjdk';	
		}elsif( $distro eq "DEBIAN" ){
			$ENV{'JAVA_HOME'}='/usr/lib/jvm/java-6-openjdk';
		}elsif( $distro eq "CENTOS" ){
			if( $arch eq "64" ){
				$ENV{'JAVA_HOME'}='/usr/lib/jvm/java-1.6.0-openjdk.x86_64';
			}else{
				$ENV{'JAVA_HOME'}='/usr/lib/jvm/java-1.6.0-openjdk';
			};
		}elsif( $distro eq "OPENSUSE" ){
			if( $arch eq "64" ){
				$ENV{'JAVA_HOME'}='/usr/lib64/jvm/java-1.6.0-openjdk';
			}else{
				$ENV{'JAVA_HOME'}='/usr/lib/jvm/java-1.6.0-openjdk';
			};
		}elsif( $distro eq "FEDORA" ){
			if( $arch eq "64" ){
				$ENV{'JAVA_HOME'}='/usr/lib/jvm/java-1.6.0-openjdk-1.6.0.0.x86_64';
			}else{
				$ENV{'JAVA_HOME'}='/usr/lib/jvm/java-1.6.0-openjdk-1.6.0.0';
			};
		}elsif( $distro eq "RHEL" ){
			if( $arch eq "64" ){
				$ENV{'JAVA_HOME'}='/usr/lib/jvm/java-1.6.0-openjdk.x86_64';
			}else{
				$ENV{'JAVA_HOME'}='/usr/lib/jvm/java-1.6.0-openjdk';
			};
		}else{
			# error !
		};
	};

	print "\nSetting JAVA_HOME to $ENV{'JAVA_HOME'}\n";

	return 0;
};


sub get_static_macmap{

	my $input_str = shift;

	my @inputs = split(" ", $input_str);

	my $final_line = "";

	foreach my $input (@inputs){

	my $mac = macmap_for_static_ip($input);

	$final_line .= $mac . "=" . $input . " ";

	};

	chop($final_line);

	return $final_line;
};


sub macmap_for_static_ip{

	my $this_ip = shift;
	my $this_mac = "D0:D0:";

	if( $this_ip =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/ ){
		my $hex1;
		my $hex2;
		my $hex3;
		my $hex4;
		$hex1 = sprintf("%02x", $1);
		$hex2 = sprintf("%02x", $2);
		$hex3 = sprintf("%02x", $3);
		$hex4 = sprintf("%02x", $4);
		$this_mac .= uc($hex1) . ":" . uc($hex2) . ":";
		$this_mac .= uc($hex3) . ":" . uc($hex4);
	}else{
		return "ERROR";
	};

	return $this_mac;
};


sub is_set_vnet_netmask_from_memo{
	if( $ENV{'QA_MEMO'} =~ /SET_VNET_NETMASK=(.+)\n/ ){
		my $extra = $1;
		$extra =~ s/\r//g;
		print "FOUND in MEMO\n";
		print "SET_VNET_NETMASK=$extra\n";
		$ENV{'QA_MEMO_SET_VNET_NETMASK'} = $extra;
		return 1;
	};
	return 0;
};


sub is_use_default_java_home_from_memo{
	if( $ENV{'QA_MEMO'} =~ /USE_DEFAULT_JAVA_HOME=YES/ ){
		print "FOUND in MEMO\n";
		print "USE_DEFAULT_JAVA_HOME=YES\n";
		$ENV{'QA_MEMO_USE_DEFAULT_JAVA_HOME'} = "YES";
		return 1;
	};
	return 0;
};


sub get_java_home_path_on_conf{

	my $temptemp = `cat $ENV{'EUCALYPTUS'}/etc/eucalyptus/eucalyptus.conf | grep "java\-home"`;

	chomp($temptemp);

	if( $temptemp =~ /\-\-java\-home=(.+)[\s|"]/){
		return $1;
	};

	return "NULL";

};


1;

