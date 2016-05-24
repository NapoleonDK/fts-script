#!/usr/bin/perl -w
use strict;
use warnings;
use VMware::VILib;
use VMware::VIRuntime;
use VMware::VICredStore;
use Email::Stuffer;
use Email::Sender::Transport::SMTP;
#Fix for sketchy certificates
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'}=0;
#Define log location, credstore, and SSH key
my $logfile = '/home/desmall/install_package/output.txt';
my $credstore = '/home/desmall/.vmware/credstore/vicredentials.xml';
my $vmappdir = '/usr/lib/vmware-vcli/apps/';
my $sshkey = '/home/desmall/.ssh/shutdown_script_key';
my $sshopts = "-i $sshkey -oStrictHostKeyChecking=no";

my @phosts = ('orw-factest-lx');
my @esxhosts = ('orw-ftslab-esx-01');
my @storage = ('orw-ftslab-storage-test1','orw-ftslab-storage-test2');
my @notoolsvms;

#print "All output will go to $logfile.\n";
#open my $log, '>', $logfile or die "Can't open logfile! $!";

my $transport = Email::Sender::Transport::SMTP->new({host => 'mail-na.mentorg.com',port => 25});

Email::Stuffer->from('fac_tech-svcs@mentor.com')
	->to('derrick_small@mentor.com')
	->subject('SHUTDOWN SCRIPT ALERT')
#	->cc('jason_gehrman@mentor.com')
	->text_body('Shutdown script in progress...')
	->transport($transport)
	->send;

#Define subroutine to prepend timestamps
sub logmsg{
#        print $log (scalar localtime().": @_");
#	print (scalar localtime().": @_");
	`logger "SHUTDOWN SCRIPT: @_"`;
}

#Define subroutine to get creds from credstore
sub getcred{
        my @user_list=VMware::VICredStore::get_usernames(server => $_[0]);
        my $pass=VMware::VICredStore::get_password(server => $_[0], username => $user_list[0]);
return ($user_list[0],$pass);
}

#Define subroutine to connect to ESX host via vSphere SDK
sub connect_esx{
	Opts::set_option('server', $_[0]);
	Opts::set_option('username', $_[1]);
	Opts::set_option('password', $_[2]);
	logmsg "Logging into: ".$_[0]."...";
	Util::connect();
#	print $log "success!\n";
	return;
}

################################################################################
#####     DESMALL - 2016-01-29 FTS Lab Shutdown Script	                   #####
#####                                                                      #####
#####           ALL VM's Must have VMware Tools Installed!                 #####
################################################################################

logmsg "---FTS Lab shutdown script executed as ".getpwuid($<)."---\n";
VMware::VICredStore::init(filename=>$credstore) or die "Unable to load credentials from VICredStore! $!\n";
logmsg "Credentials have been loaded from VICredStore\n";

###########################################################
###	Shut down physical hosts			###
###########################################################

logmsg "---BEGIN PHYSICAL HOST SHUTDOWN---\n";
for my $phost(@phosts){
	logmsg "Relying on pre-shared RSA keys for SSH to $phost. If you're prompted for a password, keys failed.\n";
#	`ssh $sshopts root\@$phost "shutdown -P now"`;
	logmsg `ssh $sshopts root\@$phost "uptime"`;
	}
logmsg "---END PHYSICAL HOST SHUTDOWN---\n";
`logger "blarg"`;
__END__
################################################################
###     Tell VMControl.pl to shut down all VMs		     ###
################################################################

logmsg "---BEGIN VM SHUTDOWN---\n";
for my $esxhost(@esxhosts){
	logmsg "Sending command to vmcontrol.pl, this will take a moment ...\n";
	my $command = $vmappdir."vm/vmcontrol.pl --server $esxhost --credstore /home/desmall/.vmware/credstore/vicredentials.xml --operation shutdown";
	logmsg `$command`."\n";
	logmsg "Waiting 10 seconds...";
	sleep 10;
	logmsg "done.\n";
}#finish ESX loop
logmsg "---END VM SHUTDOWN---\n";

###########################################################
###	Enter Maintenance Mode				###
###########################################################

logmsg "---BEGIN MAINTENANCE MODE---\n";
for my $esxhost(@esxhosts){
	logmsg "Sending command to hostops.pl, this will take a moment...\n";
	my $command = $vmappdir."host/hostops.pl --server orw-ftslab-esx-01 --credstore /home/desmall/.vmware/credstore/vicredentials.xml --operation enter_maintenance_mode";
	logmsg `$command`."\n";
	logmsg "Waiting 10 seconds...";
	sleep 10;
	logmsg "done.\n";
logmsg "---END MAINTENANCE MODE---\n";

###########################################################
###	Shut down storage			        ###
###########################################################

logmsg "---BEGIN SHUTDOWN STORAGE---\n";
for my $storage(@storage){
#	logmsg "Relying on pre-shared RSA keys for SSH to $storage.\n";
#	`ssh $sshopts root\@$storage "cifs terminate -t 0, cf disable, halt -t 0"`;
#	sleep 30;
#	`ssh $sshopts root\@$storage "cf disable, halt -t 0"`;
}
logmsg "---END SHUTDOWN STORAGE---\n";

###########################################################
###	Finally, poweroff ESXi host!		        ###
###########################################################

logmsg "---BEGIN POWER-OFF ESX HOST---\n";
for my $esxhost(@esxhosts){
	my ($user, $pass) = getcred($esxhost);
	connect_esx($esxhost,$user,$pass);
	my $host_list = Vim::find_entity_views(view_type => 'HostSystem', properties => ['name']);
	for my $host (@$host_list) {
#		$host->ShutdownHost(force => 1);
	}
	Util::disconnect();
	logmsg "Closed connection to $esxhost.\n";
}
logmsg "---END POWER-OFF ESX HOST---\n";

###########################################################
###	Wrap-up and tell everyone all about it!		###
###########################################################

logmsg "Script complete. See results at $logfile\n";
#close $log;
Email::Stuffer->from('fac_tech-svcs@mentor.com')
	->to('derrick_small@mentor.com')
	->subject('SHUTDOWN SCRIPT ALERT')
#	->cc('jason_gehrman@mentor.com')
	->text_body('Shutdown script successfully executed. Logfile attached.')
	->attach_file($logfile)
	->transport($transport)
	->send;
exit;
