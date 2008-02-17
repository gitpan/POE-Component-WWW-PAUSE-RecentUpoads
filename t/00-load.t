#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 9;
BEGIN {
    use_ok('Carp');
    use_ok('POE');
    use_ok('POE::Wheel::Run');
    use_ok('POE::Filter::Reference');
    use_ok('POE::Filter::Line');
    use_ok('WWW::PAUSE::RecentUploads');
    use_ok('POE::Component::WWW::PAUSE::RecentUploads');
};

use POE qw(Component::WWW::PAUSE::RecentUploads);

my $poco = POE::Component::WWW::PAUSE::RecentUploads->spawn(
    login => 'fake',
    pass  => 'fake',
);

isa_ok( $poco, 'POE::Component::WWW::PAUSE::RecentUploads' );
can_ok( $poco, qw(shutdown session_id fetch spawn) );

POE::Session->create(
    inline_states => {
        _start => sub { $poco->shutdown },
    },
);

$poe_kernel->run;
