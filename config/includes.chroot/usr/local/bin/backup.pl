#!/usr/bin/perl

use strict;
use XML::Simple;
use File::Path;
use File::Spec;
use Date::Calc;

###########################################################
# Initialisation stuff                                    #
###########################################################

my $configFolder = '/etc/backupsystem/';

print `clear`;

print "  _\n";
print " ( -                This is \033[1;34mBackup System\033[0m Version 0.0.1\n";
print " //\\ \n";
print " V_/_\n\n";

sub prompt {
    my ($query) = @_;		# take a prompt string as argument
    local $| = 1;		# activate autoflush to immediately show the prompt
    print $query;
    chomp(my $answer = <STDIN>);
    return $answer;
}

sub prompt_ab {
    my ($query, $a, $b, $default) = @_;

    my $a_test = lc(substr $a, 0, 1);
    my $b_test = lc(substr $b, 0, 1);

    my $quest;
    if(defined($default)) {
	$quest = $default ? "[" . uc($a_test) . "/$b_test]" : "[$a_test/" . uc($b_test) . "]";
    }
    else {
	$quest = "[$a_test/$b_test]";
    }

    my $answer;
    while(1) {
	$answer = lc(substr prompt("$query $quest: "), 0, 1);

	if($answer eq $a_test) {
	    return 1;
	}
	elsif($answer eq $b_test) {
	    return 0;
	} 
	elsif($answer eq "" && defined($default)) {
	    return $default;
	}

	print "Please answer $a ($a_test) or $b ($b_test).\n";
    }
}

sub prompt_yn {
    my ($query, $default) = @_;

    if(defined($default)) {
	return prompt_ab($query, "yes", "no", $default);
    }
    return prompt_ab($query, "yes", "no");
}

###########################################################
# Checking that the script should and can be ran          #
###########################################################

# Make shure you really want to create a backup.
if(!prompt_yn("Do you wish to create a backup?", 1)) {
    my $status = prompt_ab("Power off or return to bash?", "power off", "bash", 1) ? 0 : 2;
    print "Ok bye.\n";
    exit $status;
}

# Check if you are root
if($< != 0) {
    print "This script must be run as root\n";
    exit 1;
}

###########################################################
# Load configuration                                      #
###########################################################

# load global config
my $config = XMLin($configFolder . 'config.xml');

# load backup configuration
# it says, what to backup
my $backups = XMLin($config->{'backup-file'}, ForceArray => ['backup', 
							     'backup-folder', 
							     'target',
							     'logical-volume',
							     'folder'])->{'backup'};

###########################################################
# Decrypt hard-drives                                     #
###########################################################

sub decrypt_hdd {
    my ($uuid, $encryptedName, $infoLabel) = @_;

    $infoLabel = $uuid if(!defined($infoLabel));

    print "Decrypting $infoLabel:\n";

    system("/sbin/cryptsetup luksOpen /dev/disk/by-uuid/$uuid $encryptedName") and err_exit();
}

# find all encrypted devices and assign mount-paths
foreach my $backup (@{$backups}) {
    if($backup->{'luks'} eq 'true') {
	if(defined($backup->{'label'})) {
	    decrypt_hdd($backup->{'uuid'}, $backup->{'uuid'} . '-luks', $backup->{'label'});
	} else {
	    decrypt_hdd($backup->{'uuid'}, $backup->{'uuid'} . '-luks');
	}
	$backup->{'device-path'} = $config->{'luks-device-path'} . '/' . $backup->{'uuid'} . '-luks';
	$backup->{'luks-name'} = $backup->{'uuid'} . '-luks';
    } else {
	$backup->{'device-path'} = '/dev/disk/by-uuid/' . $backup->{'uuid'};
    }

    # Now loop all backup folders
    foreach my $backup_folder (@{$backup->{'backup-folder'}}) {
	# this itself is no harddrive so there is nothing to decrypt

	# Now loop all targets because they contain harddrives
	foreach my $target (@{$backup_folder->{'target'}}) {
	    if($target->{'luks'} eq 'true') {
		if(defined($target->{'label'})) {
		    decrypt_hdd($target->{'uuid'}, $target->{'uuid'} . '-luks', $target->{'label'});
		} else {
		    decrypt_hdd($target->{'uuid'}, $target->{'uuid'} . '-luks');
		}
		$target->{'device-path'} = $config->{'luks-device-path'} . '/' . $target->{'uuid'} . '-luks';
		$target->{'luks-name'} = $target->{'uuid'} . '-luks';
	    } else {
		$target->{'device-path'} = '/dev/disk/by-uuid/' . $target->{'uuid'};
	    }
	}
    }
}

###########################################################
# What shall I do when I finish (with success)?           #
###########################################################

my $success_exit = prompt_ab("Power off or return to bash when the backup has finished?", "power off", "bash", 1) ? 0 : 2;

############################################################
# Start of automated process                               #
############################################################

print "\n\033[1;31mStarting the backup process now.\033[0m\nYou can have a cup of tea while this is working.\nThis might take a while...\n\n";

############################################################
# Create folder structure                                  #
############################################################

# Backup folder
if( !-d $config->{'mounts'}->{'backup'}) {
    print "Creating folder for backup-drive\n";
    File::Path::make_path $config->{'mounts'}->{'backup'};
}

# Targets folder
if( !-d $config->{'mounts'}->{'targets'}) {
    print "Creating folder for target-drives\n";
    File::Path::make_path $config->{'mounts'}->{'targets'};
}

sub err_exit {
    if (@_ > 0) {
	print @_[0] . '\n';
    }
    exit 1;
}

sub warning {
    my ($str) = @_;
    print "\033[1;33m$str\033[0m\n";
}

sub deviceName {
    my ($device) = @_;

    return defined($device->{'label'}) ? $device->{'label'} : $device->{'uuid'};
}

sub activateLV {
    my ($lv) = @_;

    system("/sbin/lvchange -ay \"$lv\"") and err_exit();
}

sub deactivateLV {
    my ($lv) = @_;

    system("/sbin/lvchange -an \"$lv\"") and err_exit();
}

sub deactivateVG {
    my ($vg) = @_;

    system("/sbin/vgchange -an \"$vg\" > /dev/null") and err_exit();
}

sub mountDevice {
    my ($device, $target, $options) = @_;

    if(defined($options)) {
	$options = ' -o ' . $options;
    }
    else {
	$options = '';
    }

    system("/bin/mount$options \"$device\" \"$target\"") and err_exit();
}

sub umountDevice {
    my ($device) = @_;

    system("/bin/umount \"$device\"") and err_exit();
}

sub isReadOnlyDevice {
    my ($device) = @_;

    return !system("/sbin/tune2fs -l \"$device\" | /bin/grep \"Filesystem features:\" | /bin/grep read-only > /dev/null");
}

sub setDeviceReadOnly {
    my ($device) = @_;

    system("/sbin/tune2fs -O read-only \"$device\" > /dev/null") and err_exit();
}

sub clearDeviceReadOnly {
    my ($device) = @_;

    system("/sbin/tune2fs -O ^read-only \"$device\" > /dev/null") and err_exit();
}

sub runRsnapshot {
    my ($backup) = @_;

    print "Running the rsnapshot $backup backup.\n";

    system("/usr/bin/rsnapshot $backup") and err_exit();
}

sub collectRsnapshotBackups {
    my ($backups, $folders, $mountPoint) = @_;

    foreach my $folder (@{$folders}) {
	# Check if sequence contains /./ (a wanted entry point for rsync)
	# otherwise we insert one after the mountpoint
	if ($folder->{content} =~ m!/\./!) {
	    push @{$backups}, ({output => $folder->{out}, input => $mountPoint . $folder->{content}});
	} else {
	    push @{$backups}, ({output => $folder->{out}, input => $mountPoint . '/.' . $folder->{content}});
	}
    }
}

# This is the date in ISO 8601
sub dateIsoFormat {
    my (%date) = @_;

    return sprintf "%04d-%02d-%02d", $date{YEAR}, $date{MONTH}, $date{DAY}
}

sub decodeIsoDate {
    my ($dateString) = @_;

    $dateString =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/;
    return (YEAR => $1, MONTH => $2, DAY => $3);
}

# Read the prepared rsnapshot.conf so that the file access occurs only once
my $rsnapshotConfigFileTemplate;
{
    local $/ = undef; 		# Now we can read the entire file easily.
    open FILE, $configFolder . 'rsnapshot.conf' or err_exit();
    $rsnapshotConfigFileTemplate = <FILE>;
    close FILE;
}

foreach my $backup (@{$backups}) {
    ###########################################################
    # Mount backup drive                                      #
    ###########################################################

    # If the backup device is a logical volume
    my $backupFinalDevicePath;
    if(defined($backup->{'lv'})) {
	print "Activating logical volume \"" . $backup->{'lv'} . "\".\n";
	activateLV($backup->{'lv'});
	$backupFinalDevicePath = $config->{'lvm-device-path'} . '/' . $backup->{'lv'};
    }
    else {
	$backupFinalDevicePath = $backup->{'device-path'};
    }

    if(isReadOnlyDevice($backupFinalDevicePath)) {
	# Clear the flag (we need to write onto the backup device)
	print "Clearing read-only flag of backup device (" . deviceName($backup) . ").\n";
	clearDeviceReadOnly($backupFinalDevicePath);

	# Now mount it
	print 'Mounting "' . deviceName($backup) . "\".\n";
	mountDevice($backupFinalDevicePath, $config->{mounts}->{backup});

	# Finally set the read-only flag again because it should be read-only afterwards
	# (It stays writable because it's already mounted)
	print "Setting read-only flag of backup device (" . deviceName($backup) . ").\n";
	setDeviceReadOnly($backupFinalDevicePath);
    } else {
	# Just mount the backup device
	print 'Mounting "' . deviceName($backup) . "\".\n";
	mountDevice($backupFinalDevicePath, $config->{mounts}->{backup});
    }

    foreach my $backupFolder (@{$backup->{'backup-folder'}}) {
	###########################################################
	# Mount target drives and build rsnapshot backup list     #
	###########################################################

	my @rsnapshotBackups = ();
	
	foreach my $target (@{$backupFolder->{'target'}}) {
	    # this partition is a volume group
	    if(defined($target->{'logical-volume'})) {
		foreach my $lv (@{$target->{'logical-volume'}}) {
		    # Mount as logical volume
		    print "Activating logical volume \"" . $lv->{'lv'} . "\".\n";
		    activateLV($lv->{'lv'});
		    $lv->{'device-path'} = $config->{'lvm-device-path'} . '/' . $lv->{'lv'};

		    my $options = 'ro';
		    my $extraText = '';
		    my $mountPointSubvolume = '';

		    # This adds support to btrfs subvolumes which somehow don't mount themselves
		    # if you just mount the entire volume
		    if(defined($lv->{subvolume})) {
			$extraText=" (Subvolume $lv->{subvolume})";
			$options .= ',subvol=' . $lv->{subvolume};
			$mountPointSubvolume = '-' . $lv->{subvolume};
			$mountPointSubvolume =~ s!/!-!g;
		    }

		    my $lvHyphen = $lv->{'lv'};
		    $lvHyphen =~ s!/!-!g;
		    $lv->{'mount-point'} = $config->{mounts}->{targets} . '/' . $target->{uuid} . '-' . $lvHyphen . $mountPointSubvolume;
		    
		    # Create mount-point
		    File::Path::make_path $lv->{'mount-point'};

		    print 'Mounting "' . $lv->{'lv'} . "\"$extraText.\n";
		    mountDevice($config->{'lvm-device-path'} . '/' . $lv->{lv}, $lv->{'mount-point'}, $options);

		    # Now we wan't to collect all specifiet backup folders
		    collectRsnapshotBackups(\@rsnapshotBackups, $lv->{folder}, $lv->{'mount-point'});
		}
	    }
	    else {
		my $options = 'ro';
		my $extraText = '';
		my $mountPointSubvolume = '';

		# This adds support to btrfs subvolumes which somehow don't mount themselves
		# if you just mount the entire volume
		if(defined($target->{subvolume})) {
		    $extraText=" (Subvolume $target->{subvolume})";
		    $options .= ',subvol=' . $target->{subvolume};
		    $mountPointSubvolume = '-' . $target->{subvolume};
		    $mountPointSubvolume =~ s!/!-!g;
		}

		$target->{'mount-point'} = $config->{mounts}->{targets} . '/' . $target->{uuid} . $mountPointSubvolume;
		
		# Create mount-point
		File::Path::make_path $target->{'mount-point'};

		print 'Mounting "' . deviceName($target) . "\"$extraText.\n";
		mountDevice($target->{'device-path'}, $target->{'mount-point'}, $options);

		# Now we wan't to collect all specifiet backup folders
		collectRsnapshotBackups(\@rsnapshotBackups, $target->{folder}, $target->{'mount-point'});
	    }
	}

	############################################################
	# Generate rsnapshot.conf                                  #
	############################################################

	my $rsnapshotConfigFile = $rsnapshotConfigFileTemplate; # Create copy so next time we still have the original
	my $rsnapshotRoot = $config->{mounts}->{backup} . $backupFolder->{path};

	$rsnapshotConfigFile =~ s!\$\$\$SNAPSHOT_ROOT\$\$\$!$rsnapshotRoot!;

	my $rsnapshotLogFile;

	if(defined($backupFolder->{logfile})) {
	    $rsnapshotLogFile = $config->{mounts}->{backup} . $backupFolder->{logfile};
	}
	else {
	    $rsnapshotLogFile = $rsnapshotRoot . 'rsnapshot.log';
	}
	
	$rsnapshotConfigFile =~ s!\$\$\$LOGFILE\$\$\$!$rsnapshotLogFile!;

	# generate backup directives
	foreach my $rsnapshotBackup (@rsnapshotBackups) {
	    $rsnapshotConfigFile .= "backup\t$rsnapshotBackup->{input}\t$rsnapshotBackup->{output}/\n";
	}

	# Write config file to disk
	open(my $rsnapshotFH, '>', $config->{'rsnapshot-config-file'}) or err_exit('Could not create rsnapshot.conf');
	print $rsnapshotFH $rsnapshotConfigFile;
	close $rsnapshotFH;

	############################################################
	# Initialise backup repository                             #
	############################################################

	my %today = ();
	($today{YEAR},$today{MONTH},$today{DAY}) = Date::Calc::Today();

	# Read the last time this script was ran for the current repository
	my %lastRun;
	if( -f $config->{mounts}->{backup} . $backupFolder->{path} . '.DATE') {
	    open my $fh, $rsnapshotRoot . '.DATE' or err_exit('Could not create .DATE file for backup directory.');
	    chomp(my $dateString = <$fh>);
	    %lastRun = decodeIsoDate($dateString);
	} else {
	    %lastRun = %today;
	}

	# Write the new date to drive
	open my $fh, '>', $config->{mounts}->{backup} . $backupFolder->{path} . '.DATE' or err_exit('Could not update .DATE file in the backup directory.');
	print $fh dateIsoFormat(%today);
	close $fh;

	############################################################
	# Run rsnapshot if necessary                               #
	############################################################

        runRsnapshot('daily');

	# If a week has gone since the last weekly update create a weekly update
	my $dateDiff = Date::Calc::Delta_Days($lastRun{YEAR}, $lastRun{MONTH}, $lastRun{DAY},
					      $today{YEAR}, $today{MONTH}, $today{DAY});

	# If the last backup was 7 days ago a week has certainly passed
	if($dateDiff >= 7) {
	    runRsnapshot('weekly');
	}
	# Now the date difference is < 7 days => if the day of week is smaller today
	# A Monday must hav gone by...
	elsif($dateDiff > 0 && Date::Calc::Day_of_Week($lastRun{YEAR},$lastRun{MONTH},$lastRun{DAY}) > Date::Calc::Day_of_Week($today{YEAR},$today{MONTH},$today{DAY})) {
	    runRsnapshot('weekly');
	}

	# If the month-numbers are different, a month must have gone by.
	# Therefore a monthly backup is required.
	if($lastRun{MONTH} != $today{MONTH}) {
	    runRsnapshot('monthly');
	}

	############################################################
	# Create date index                                        #
	############################################################

	my $dateIndexPath;
        if(defined($backupFolder->{'date-dir'})) {
	    $dateIndexPath = $config->{mounts}->{backup} . $backupFolder->{'date-dir'};
	}
	else {
	    $dateIndexPath = $rsnapshotRoot . 'date/';
	}

	if( !-d $dateIndexPath ) {
	    print "Creating date index directory.\n";
	    File::Path::make_path $dateIndexPath;
	}

	# Remove old date index
	print "Clearing old date index.\n";
	File::Path::remove_tree($dateIndexPath, {safe => 1, keep_root => 1, verbose => 1});

	# Set date information for newest backup
	print "Setting date-information for backup daily.0.\n";

	# If there is a date inside the current backup remove it
	# Otherwise it's possible to override dates in other backups
	# as well (hardlink problem).
	if( -f $rsnapshotRoot . 'daily.0/.DATE' ) {
	    unlink $rsnapshotRoot . 'daily.0/.DATE';
	}
	open my $fh, '>', $rsnapshotRoot . 'daily.0/.DATE' or err_exit('Could not set date-information for backup daily.0.');
	print $fh dateIsoFormat(%today);
	close $fh;
	
	print "Generating new date index.\n";

	# this is for duplicated dates
	my @append = qw(a b c d e f g h i j k l m n o p q r s t u v w x y z);

	foreach my $interval ('daily', 'weekly', 'monthly') {
	    my @dirs = glob '"' . $rsnapshotRoot . $interval . '.*"';
	    foreach my $dir (@dirs) {
		# Read date value
		my $res = open my $fh, $dir . '/.DATE';

	        if(!$res) {
		    warning("Could not process backup $dir for date index! (no timestamp)");
		    next;
		}

		chomp(my $dateString = <$fh>);
		close $fh;

		# Find a currently unused name for the link
		my $linkName = $dateIndexPath . '/' . $dateString;
		my $i = 0;
		my $j = 0;
		my $success = 1;
		my $delimiter = '-';
		while( -e $linkName ) {
		    $linkName = $dateIndexPath . '/' . $dateString . $delimiter . $append[$i];
		    $i++;
		    # Did we hit the last element?
		    if($i == scalar @append) {
			if($j == scalar @append) {
			    $success = 0;
			    last;
			}
			$dateString .= $delimiter . $append[$j];
			$delimiter = '';
			$j++;
		    }
		}

		if(!$success) {
		    warning("Could not process backup $dir for date index! (no free link)");
		    next;
		}

		# Create the link
		if(!symlink(File::Spec->abs2rel($dir, $dateIndexPath), $linkName)) {
		    warning("Could not process backup $dir for date index! (link creation)");
		}
	    }
	}

	############################################################
	# Unmount target drives                                    #
	############################################################

	my @volumeGroupsToDeactivate = ();
	
	foreach my $target (@{$backupFolder->{'target'}}) {
	    # this partition is a volume group
	    if(defined($target->{'logical-volume'})) {
		foreach my $lv (@{$target->{'logical-volume'}}) {
		    # Mount as logical volume
		    print 'Unmounting "' . $lv->{'lv'} . "\".\n";
		    umountDevice($lv->{'mount-point'});

		    # Remove mount-point
		    rmdir $lv->{'mount-point'};

		    # Because we now support btrfs subvolumes a logical volume
		    # can appear multiple times. So this will likely produce an
		    # error.
		    # print "Deactivating logical volume \"" . $lv->{'lv'} . "\".\n";
		    # deactivateLV($lv->{'lv'});

		    # they're all activated when decrypted.
		    $lv->{'lv'} =~ m!^([^/]+)/!;
		    push @volumeGroupsToDeactivate, ($1)
		}
	    }
	    else {
		print 'Unmounting "' . deviceName($target) . "\".\n";
		umountDevice($target->{'mount-point'});

		# Remove mount-point
		rmdir $target->{'mount-point'};
	    }
	}

	# We have to deactivate them now, because otherwise there could be
	# Other mount points depending on the same volume group, which
	# lets the deactivation programm crash.
	# We have to deactivate the volume groups, because otherwise we
	# can't close the luks devices.
	#
	# Another reason for this is the support for btrfs subvolumes which
	# create the likelyhood that some logical volumes are mounted multiple
	# times with different mount options (for subvolume). This disables the
	# ability to deactivate the logical volumes directly after they were
	# unmounted.
	foreach my $vg (@volumeGroupsToDeactivate) {
	    print "Deactivating volume group \"" . $vg . "\".\n";
	    deactivateVG($vg);
	}
    }

    ###########################################################
    # Unmount backup drive                                    #
    ###########################################################

    print 'Unmounting "' . deviceName($backup) . "\".\n";
    umountDevice($backupFinalDevicePath);

    if(defined($backup->{'lv'})) {
	print "Deactivating logical volume \"" . $backup->{'lv'} . "\".\n";
	deactivateLV($backup->{'lv'});
	# We need to deactivate all volumes of the device because 
	# they're all activated when decrypted.
	$backup->{'lv'} =~ m!^([^/]+)/!;
	deactivateVG($1);
    }
}

############################################################
# Close encrypted devices                                  #
############################################################

sub closeEncryptedHDD {
    my ($encryptedName, $infoLabel) = @_;

    $infoLabel = $encryptedName if(!defined($infoLabel));

    print "Closing encrypted device $infoLabel:\n";

    system("/sbin/cryptsetup luksClose $encryptedName") and err_exit();
}

# find all encrypted devices
foreach my $backup (@{$backups}) {
    if($backup->{'luks'} eq 'true' && defined($backup->{'luks-name'})) {
        closeEncryptedHDD($backup->{'luks-name'}, deviceName($backup));
    }

    # Now loop all backup folders
    foreach my $backup_folder (@{$backup->{'backup-folder'}}) {
	# this itself is no harddrive so there is nothing to decrypt

	# Now loop all targets because they contain harddrives
	foreach my $target (@{$backup_folder->{'target'}}) {
	    if($target->{'luks'} eq 'true' && defined($target->{'luks-name'})) {
	        closeEncryptedHDD($target->{'luks-name'}, deviceName($target));
	    }
	}
    }
}

exit $success_exit;
