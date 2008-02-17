#!/usr/bin/env perl

use strict;
use warnings;

unless ( @ARGV == 2 ) {
    die "usage: perl get_recent.pl PAUSE_LOGIN PAUSE_PASS\n";
}

use lib '../lib';

use POE qw(Component::WWW::PAUSE::RecentUploads);

my $poco = POE::Component::WWW::PAUSE::RecentUploads->spawn(
    login => shift,
    pass  => shift,
    debug => 1,
);

POE::Session->create(
    package_states => [
        main => [ qw( _start recent ) ],
    ],
);

$poe_kernel->run();

sub _start {
    $poco->fetch( { event => 'recent', _time => time() } );
}

sub recent {
    my $data = $_[ARG0];

    if ( $data->{error} ) {
        print "Error while fetching recent data: $data->{error}\n";
    }
    else {
        foreach my $dist ( @{ $data->{data} } ) {
            printf "%s by %s (size: %s)\n",
                        @$dist{ qw(dist name size) };
        }
    }
    printf "\nRequest was sent at: %s\n", scalar localtime $data->{_time};
    $poco->shutdown;
}


