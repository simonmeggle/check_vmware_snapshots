#!/usr/bin/perl
 $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

# check_vmware_snapshots.pl
# Extra packages required (URL given for vMA suitable RPMs)
# * Date::Parse from http://vault.centos.org/5.2/extras/i386/RPMS/

# 2012 Simon Meggle, <simon.meggle@consol.de>

use strict;
use warnings;
use VMware::VIRuntime;
use Date::Parse;
use Monitoring::Plugin;

my %STATES = (
        0       => "ok",
        1       => "warning",
        2       => "critical",
        3       => "unknown",
);

{
    no warnings 'redefine';
    *Monitoring::Plugin::Functions::get_shortname = sub {
        return undef;
    };
}

my $perfdata_label;
my $perfdata_uom;
my $ok_msg;
my $nok_msg;

my $np = Monitoring::Plugin->new(
    shortname => "",
    usage     => "",
);

my %opts = (
    mode => {
        type     => "=s",
        variable => "mode",
        help     => "count (per VM) | age (per snapshot)",
        required => 1,
    },
    warning => {
        type     => "=i",
        variable => "warning",
        help     => "days after a snapshot is alarmed as warning.",
        required => 1,
    },
    critical => {
        type     => "=i",
        variable => "critical",
        help     => "days after a snapshot is alarmed as critical.",
        required => 1,
    },
    blacklist => {
        type     => "=s",
        variable => "blacklist",
        help     => "regex blacklist",
        required => 0,
    },
    whitelist => {
        type     => "=s",
        variable => "whitelist",
        help     => "regex whitelist",
        required => 0,
    },
    separator => {
        type     => "=s",
        variable => "separator",
        help     => "field separator for VMs/snapshots (default: ', '). ",
        required => 0,
        default => ", "
    },
    match_snapshot_names => {
	  	type => ":i",
        help     => "If set, match also names of snapshots in black/whitelist",
        required => 0,
        default => 0,
    },
);

my $badcount = 0;
my $worststate = 0;
Opts::add_options(%opts);
Opts::parse();
Opts::validate();
Util::connect();

my $warn = Opts::get_option('warning');
my $crit = Opts::get_option('critical');
my $blacklist = Opts::get_option('blacklist');
my $whitelist = Opts::get_option('whitelist');
my $separator = Opts::get_option('separator');
my $match_snapshot_names = Opts::get_option('match_snapshot_names');

$np->set_thresholds(
    warning  => $warn,
    critical => $crit,
);
my $mode = Opts::get_option('mode');

my $sc = Vim::get_service_content();

my $vms = Vim::find_entity_views(
    view_type => 'VirtualMachine',
	filter => {},
	properties => [ 'name', 'snapshot' ],
);

if ( uc($mode) eq "AGE" ) {
	$perfdata_label = "outdated_snapshots";
	$perfdata_uom   = "snapshots";
	$ok_msg         = "No outdated VM snapshots found.";
	$nok_msg         = "outdated VM snapshots found!";
} elsif ( uc($mode) eq "COUNT" ) {
	$perfdata_label = "snapshot_count";
	$perfdata_uom   = "snapshots";
	$ok_msg         = "All VMs have the allowed number of snapshots.";
	$nok_msg         = "VMs with too much snapshots!";
}


foreach my $vm_view ( @{$vms} ) {
    #my $vm_name     = $vm_view->{summary}->{config}->{name};
    my $vm_name     = $vm_view->{name};
    my $vm_snapinfo = $vm_view->{snapshot};



    next unless defined $vm_snapinfo;
    next if (isblacklisted(\$blacklist,$vm_name ));
    next if (isnotwhitelisted(\$whitelist,$vm_name));

    use Data::Dumper; 
    print Dumper $vm_snapinfo->{rootSnapshotList}; 
    exit; 


    if ( uc($mode) eq "AGE" ) {
        check_snapshot_age( $vm_name, $vm_snapinfo->{rootSnapshotList} );
    }
    elsif ( uc($mode) eq "COUNT" ) {
        my %vm_snapshot_count;
        check_snapshot_count( $vm_name, $vm_snapinfo->{rootSnapshotList},
            \%vm_snapshot_count );
        my $status = $np->check_threshold( $vm_snapshot_count{$vm_name} );
        if ($status) {
            $np->add_message(
               $status,
                sprintf(
                    "VM \"%s\" has %d snapshots",
                    $vm_name, $vm_snapshot_count{$vm_name}
                )
            );
            $badcount++;
            $worststate = ($status > $worststate ? $status : $worststate);
        }

    }
#    elsif ( uc($mode) eq "SIZE" ) {
#        $perfdata_label = "snapshot size";
#        $perfdata_uom   = "MB";
#        $ok_msg         = "All snapshots are within allowed size bounds.";
#
#    }
    else {
        $np->nagios_die("Unknown Mode.");
    }
}

$np->add_perfdata(
    label     => $perfdata_label,
    value     => $badcount,
    uom       => $perfdata_uom,
    threshold => $np->threshold(),
);

{
    Util::disconnect();
}

if ($worststate) {
    unshift( @{$np->{messages}->{ $STATES{$worststate} } }, $badcount . " " . $nok_msg);
    $np->nagios_exit(
        $np->check_messages(
            join     => $separator,
            join_all => $separator,
        )
    );
}
else {
    $np->nagios_exit( 0, $ok_msg );
}

sub check_snapshot_age {
    my $vm_name     = shift;
    my $vm_snaplist = shift;

    foreach my $vm_snap ( @{$vm_snaplist} ) {
        if ( $vm_snap->{childSnapshotList} ) {
            check_snapshot_age( $vm_name, $vm_snap->{childSnapshotList} );
        }
		next if (isblacklisted(\$blacklist,$vm_snap->{name}) and $match_snapshot_names );
		next if (isnotwhitelisted(\$whitelist,$vm_snap->{name}) and $match_snapshot_names );

        my $epoch_snap = str2time( $vm_snap->{createTime} );
        my $days_snap  = sprintf("%0.1f", ( time() - $epoch_snap ) / 86400 );
        my $status     = $np->check_threshold($days_snap);
        if ($status) {
            $np->add_message(
                $status,
                sprintf(
                    "Snapshot \"%s\" (VM: '%s') is %d days old",
                    $vm_snap->{name}, $vm_name, $days_snap
                )
            );
            $badcount++;
            $worststate = ($status > $worststate ? $status : $worststate);
        }
    }
}

sub check_snapshot_count {
    my $vm_name      = shift;
    my $vm_snaplist  = shift;
    my $vm_snapcount = shift;

    foreach my $vm_snap ( @{$vm_snaplist} ) {
        if ( $vm_snap->{childSnapshotList} ) {
            check_snapshot_count( $vm_name, $vm_snap->{childSnapshotList},
                $vm_snapcount );
        }
		next if (isblacklisted(\$blacklist,$vm_snap->{name}) and $match_snapshot_names );
		next if (isnotwhitelisted(\$whitelist,$vm_snap->{name}) and $match_snapshot_names );
		$vm_snapcount->{$vm_name}++;
	}
}

sub isblacklisted {
        my ($blacklist_ref,@candidates) = @_;
        return 0 if (!defined $$blacklist_ref);

        my $ret;
        $ret = grep (/$$blacklist_ref/, @candidates);
        return $ret;
}
sub isnotwhitelisted {
        my ($whitelist_ref,@candidates) = @_;
        return 0 if (!defined $$whitelist_ref);

        my $ret;
        $ret = ! grep (/$$whitelist_ref/, @candidates);
        return $ret;
}
