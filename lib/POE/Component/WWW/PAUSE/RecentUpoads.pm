package POE::Component::WWW::PAUSE::RecentUpoads;

use warnings;
use strict;

our $VERSION = '0.03';

use WWW::PAUSE::RecentUploads;
use POE qw( Wheel::Run  Filter::Reference  Filter::Line);
use Carp;

sub spawn {
    my $package = shift;
    
    croak "Even number of arguments must be passed to $package"
        if @_ & 1;

    my %params = @_;
    
    $params{ lc $_ } = delete $params{ $_ } for keys %params;

    delete $params{options}
        unless ref $params{options} eq 'HASH';

    for ( qw(login pass) ) {
        croak "Missing `$_` parameter"
            unless exists $params{ $_ };
    }
    
    my $self = bless \%params, $package;

    $self->{session_id} = POE::Session->create(
        object_states => [
            $self => {
                fetch      => '_fetch',
                shutdown   => '_shutdown',
            },
            $self => [
                qw(
                    _child_error
                    _child_close
                    _child_stderr
                    _child_stdout
                    _sig_chld
                    _start
                )
            ],
        ],
        ( exists $params{options} ? ( options => $params{options} ) : () ),
    )->ID;
    
    return $self;
}

sub _start {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
     $self->{session_id} = $_[SESSION]->ID();
    if  ( $self->{alias} ) {
        $kernel->alias_set( $self->{alias} );
    }
    else {
        $kernel->refcount_increment( $self->{session_id} => __PACKAGE__ );
    }
    
    $self->{wheel} = POE::Wheel::Run->new(
        Program => \&_wheel,
        ErrorEvent => '_child_error',
        CloseEvent => '_child_close',
        StderrEvent => '_child_stderr',
        StdoutEvent => '_child_stdout',
        StdioFilter => POE::Filter::Reference->new,
        StderrFilter => POE::Filter::Line->new,
        ( $^O eq 'MSWin32' ? ( CloseOnCall => 0 ) : ( CloseOnCall => 1 ) ),
    );
    
    $kernel->call('shutdown')
        unless $self->{wheel};
    
    $kernel->sig_child( $self->{wheel}->PID, '_sig_chld' );
}

sub _sig_chld {
    $poe_kernel->sig_handled;
}

sub _child_close {
    my ( $kernel, $self, $wheel_id ) = @_[ KERNEL, OBJECT, ARG0 ];

    warn "_child_close called (@_[ARG0..$#_])\n"
        if $self->{debug};

    delete $self->{wheel};
    $kernel->yield('shutdown')
        unless $self->{shutdown};

    undef;
}

sub _child_error {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    warn "_child_error called (@_[ARG0..$#_])\n"
        if $self->{debug};

    delete $self->{wheel};
    $kernel->yield('shutdown')
        unless $self->{shutdown};

    undef;
}

sub _child_stderr {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    warn "_child_stderr: $_[ARG0]\n"
        if $self->{debug};

    undef;
}

sub _child_stdout {
    my ( $kernel, $self, $input ) = @_[ KERNEL, OBJECT, ARG0 ];
    
    my $session = delete $input->{sender};
    my $event   = delete $input->{event};
    
    delete @$input{ qw(login pass ua_args) };

    $kernel->post( $session, $event, $input );
    $kernel->refcount_decrement( $session => __PACKAGE__ );

    undef;
}

sub shutdown {
    my $self = shift;
    $poe_kernel->post( $self->{session_id} => 'shutdown' );
}

sub _shutdown {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    $kernel->alarm_remove_all;
    $kernel->alias_remove( $_ ) for $kernel->alias_list;
    $kernel->refcount_decrement( $self->{session_id} => __PACKAGE__ )
        unless $self->{alias};

    $self->{shutdown} = 1;
    $self->{wheel}->shutdown_stdin
        if $self->{wheel};
}

sub session_id {
    return $_[0]->{session_id};
}

sub fetch {
    my $self = shift;
    $poe_kernel->post( $self->{session_id} => 'fetch' => @_ );
}

sub _fetch {
    my ( $kernel, $self, $args )= @_[ KERNEL, OBJECT, ARG0 ];

    my $sender = $_[SENDER]->ID;

    return
        if $self->{shutdown};

    $args->{ lc $_ } = delete $args->{ $_ }
        for grep { !/^_/ } keys %{ $args };

    
    if ( $args->{session} ) {
        if ( my $ref = $kernel->alias_resolve( $args->{session} ) ) {
            $args->{sender} = $ref->ID;
        }
        else {
            warn "Could not resolve `session` parameter to a "
                    . "valid POE session. Aborting...";
            return;
        }
    }
    else {
        $args->{sender} = $sender;
    }
    
    for ( qw(login pass ua_args) ) {
        $args->{ $_ } = $self->{ $_ };
    }
    
    $kernel->refcount_increment( $args->{sender} => __PACKAGE__ );
    $self->{wheel}->put( $args );

    undef;
}

sub _wheel {
    if ( $^O eq 'MSWin32' ) {
        binmode STDIN;
        binmode STDOUT;
    }
    
    my $raw;
    my $size = 4096;
    my $filter = POE::Filter::Reference->new;

    while ( sysread STDIN, $raw, $size ) {
        my $requests = $filter->get( [ $raw ] );
        foreach my $req_ref ( @$requests ) {

            _retrieve_PAUSE_info( $req_ref );

            my $response = $filter->put( [ $req_ref ] );
            print STDOUT @$response;
        }
    }
}

sub _retrieve_PAUSE_info {
    my $req_ref = shift;

    my $pause = WWW::PAUSE::RecentUploads->new(
        login => $req_ref->{login},
        pass  => $req_ref->{pass},
        (
            exists $req_ref->{ua_args}
            ? ( ua_args => $req_ref->{ua_args} )
            : ()
        ),
    );
    
    my $data_ref = $pause->get_recent;
    
    if ( $data_ref ) {
        $req_ref->{data} = $data_ref;
    }
    else {
        $req_ref->{error} = $pause->error;
    }
    
    undef;
}


1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

POE::Component::WWW::PAUSE::RecentUploads - a non-blocking L<POE> wrapper
around L<WWW::PAUSE::RecentUploads>.

=head1 SYNOPSIS

    use strict;
    use warnings;
    
    use POE qw(Component::WWW::PAUSE::RecentUploads);
    
    my $poco = POE::Component::WWW::PAUSE::RecentUploads->spawn(
        login => 'PAUSE LOGIN',
        pass  => 'PAUSE PASSWORD',
        debug => 1,
    );
    
    POE::Session->create(
        package_states => [
            main => [ qw( _start recent ) ],
        ],
    );
    
    $poe_kernel->run();
    
    sub _start {
        $poco->fetch( { event => 'recent' } );
    }
    
    sub recent {
        my $data = $_[ARG0];
        if ( $data->{error} ) {
            print "Error while fetching recent data: $data->{error}\n";
        }
        else {
            foreach my $dist ( @{ $data->{data} || [] } ) {
                printf "%s by %s (size: %s)\n",
                        @$dist{ qw(dist name size) };
            }
        }
        $poco->shutdown;
    }

Using the event based interface is also possible, of course.

=head1 DESCRIPTION

The module is a non-blocking L<POE> wrapper around
WWW::PAUSE::RecentUploads which fetches the listing of recent uploads
to L<http://pause.perl.org>

=head1 CONSTRUCTOR

    my $poco = POE::Component::WWW::PAUSE::RecentUploads->spawn(
        login => 'PAUSE LOGIN',     # mandatory
        pass  => 'PAUSE PASSWORD',  # mandatory
    );
    
    POE::Component::WWW::PAUSE::RecentUploads->spawn(
        login => 'PAUSE LOGIN',     # mandatory
        pass  => 'PAUSE PASSWORD',  # mandatory
        alias => 'recent',          # all the rest are optional
        debug   => 1,               
        ua_args => {                
            timeout => 10,
            agent   => 'RecentUA',
            # other LWP::UserAgent's constructor arguments can go here
        },
        options => {
            debug => 1, # POE::Session create() may go here.
        },
    );

Spawns a new POE::Component::WWW::PAUSE::RecentUploads component and
returns a reference to it, but you don't have to keep it if you set the
optional C<alias> argument. Takes a single argument which is a hashref of
options. Two of them, C<login> and C<password> are mandatory, the rest
is optional. The possible keys/values are as follows:

=head2 login

    { login => 'PAUSE LOGIN' }

B<Mandatory>. Must contain your L<http://pause.perl.org> login.

=head2 pass

    { login => 'PAUSE LOGIN' }

B<Mandatory>. Must contain your L<http://pause.perl.org> password.

=head2 alias

    { alias => 'recent' }

B<Optional>. Specifies the component's L<POE::Session> alias of the
component.

=head2 debug

B<Optional>. 
=head2 ua_args

    { debug   => 1 }

B<Optional>. When set to a true value will make the component emit some
debuging info. Defaults to false.

=head2 options

    {
        options => {
            trace   => 1,
            default => 1,
        }
    }

A hashref of POE Session options to pass to the component's session.

=head1 METHODS

These are the object-oriented methods of the component.

=head2 fetch

    $poco->fetch( { event => 'recent' } );
       
    $poco->fetch(   {
            event   => 'recent', # the only mandatory argument
            login   => 'other_login', # this and below is optional
            pass    => 'other_pass',
            session => 'other_session',
            ua_args => {
                timeout => 10, # default timeout is 30.
                argent  => 'LolFetcher',
            },
            _user1  => 'random',
            _cow    => 'meow',
        }
    );

Instructs the component to fetch information about recent PAUSE uploads.
See C<fetch> event description below for more information.

=head2 session_id

    my $fetcher_id = $poco->session_id;

Takes no arguments. Returns POE Session ID of the component.

=head2 shutdown

    $poco->shutdown;

Takes no arguments. Shuts the component down.

=head1 ACCEPTED EVENTS

The interaction with the component is also possible via event based
interface. The following events are accepted by the component:

=head2 fetch

    $poe_kernel->post( recent => fetch => {
            event   => 'event_where_to_send_output', # mandatory,
            session => 'some_session', # this and everything below is...
                                       # ...optional
            login   => 'some_other_login',
            pass    => 'some_other_password',
            ua_args => {
                timeout => 10, # defaults to 30
                agent   => 'SomeUA',
                # the rest of LWP::UserAgent contructor arguments
            },
            _user_defined => 'foo',
            _cow_said     => 'meow',
        }
    );

Takes one argument which is a hashref with the following keys:

=head3 event

    { event   => 'event_where_to_send_output' }

B<Mandatory>. The name of the event which to send when output is ready.
See OUTPUT section for its format.

=head3 session

    { session => 'other_session_alias' }

    { session => $other_session_ID }
    
    { session => $other_session_ref }

B<Optional>. Specifies an alternative POE Session to send the output to.
Accepts either session alias, session ID or session reference. Defaults
to the current session.

=head3 login

    { login   => 'some_other_login' }

B<Optional>.Using C<login> argument you may override the PAUSE login 
you've specified
in the constructor. Defaults to contructor's C<login> value.

=head3 pass

    { pass    => 'some_other_password' }

B<Optional>. Using C<pass> argument you may override the PAUSE 
password you've specified
in the constructor. Defaults to contructor's C<pass> value.

=head3 ua_args

    {
        ua_args => {
            timeout => 10, # defaults to 30
            agent   => 'SomeUA',
            # the rest of LWP::UserAgent contructor arguments
        },
    }

B<Optional>. The C<ua_args> key takes a hashref as a value which should
contain the arguments which will
be passed to
L<LWP::UserAgent> contructor. I<Note:> all arguments will default to
whatever L<LWP::UserAgent> default contructor arguments are except for
the C<timeout>, which will default to 30 seconds.

=head3 user defined arguments

    {
        _user_var    => 'foos',
        _another_one => 'bars',
        _some_other  => 'beers',
    }

B<Optional>. Any keys beginning with the C<_> (underscore) will be present
in the output intact. If C<where> option (see below) is specified, any
arguments will also be present in the result of "finished downloading"
event.

=head2 shutdown

    $poe_kernel->post( recent => 'shutdown' );

Takes no arguments, instructs the component to shut itself down.

=head1 OUTPUT

    $VAR1 = {
          'data' => [
                      {
                        'name' => 'CJUKUO',
                        'dist' => 'AIIA-GMT-0.01',
                        'size' => '33428b'
                      },
                      {
                        'name' => 'DOMQ',
                        'dist' => 'Alien-Selenium-0.07',
                        'size' => '1640987b'
                      },
                    # more of these here
            ],
            '_secret' => 'value',
    }

The event handler set up to listen for the event, name of which you've
specified in the C<event> argument of C<fetch> event/method will
recieve the results in C<ARG0> in the form of a hashref with one or
more of the keys presented below. I<Note:> the uploads stick around
for quite some time in the list on PAUSE, thus you are likely to get
several "dists" reported as recent by this component if you are fetching
the list often enough. If your goal is to report any new uploads to 
PAUSE you may want to use L<POE::Component::WWW::PAUSE::RecentUploads::Tail>
instead. The keys of the output hashref are as follows:

=head2 data

    {
        'data' => [
                {
                'name' => 'CJUKUO',
                'dist' => 'AIIA-GMT-0.01',
                'size' => '33428b'
                },
                {
                'name' => 'DOMQ',
                'dist' => 'Alien-Selenium-0.07',
                'size' => '1640987b'
                },
            # more of these here
        ],
    }

Unless an error occured, the C<data> key will be present and the value
of it will be an arrayref of hashrefs representing recent uploads to PAUSE.
The keys of those hashrefs are as follows:

=head3 name

    { 'name' => 'CJUKUO' }

The author ID of the upload. I<Note:> often ID will show up on PAUSE
a bit later than the upload itself. If author's ID is missing the component
will ignore this upload and will report it later.

=head3 dist

    { 'dist' => 'Alien-Selenium-0.07' }

The name of the distro (or file if you prefer) that was uploaded.

=head3 size

    { 'size' => '1640987b' }

The size of the uploaded file. The value will also contain the unit of
measure.

=head2 error

    { 'error' => '401 Authorization Required' }

If an error occured the C<error> key will be present and will contain
the description of the error.

=head2 user defined arguments

    {
        _user_var    => 'foos',
        _another_one => 'bars',
        _some_other  => 'beers',
    }

B<Optional>. Any keys beginning with the C<_> (underscore) will be present
in the output intact.

=head1 SEE ALSO

L<POE>, L<WWW::PAUSE::RecentUploads>,
L<POE::Component::WWW::PAUSE::RecentUploads::Tail>, L<LWP::UserAgent>,
L<http://pause.perl.org>

=head1 PREREQUISITES

This module requires the following modules/version for proper operation:

        Carp                      => 1.04,
        POE                       => 0.9999,
        POE::Wheel::Run           => 1.2179,
        POE::Filter::Reference    => 1.2187,
        POE::Filter::Line         => 1.1920,
        WWW::PAUSE::RecentUploads => 0.01,

Not tested with earlier versions of those modules.

=head1 AUTHOR

Zoffix Znet, C<< <zoffix at cpan.org> >>
(L<http://zoffix.com>, L<http://haslayout.net>)

=head1 BUGS

Please report any bugs or feature requests to C<bug-poe-component-www-pause-recentupoads at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=POE-Component-WWW-PAUSE-RecentUpoads>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc POE::Component::WWW::PAUSE::RecentUpoads

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=POE-Component-WWW-PAUSE-RecentUpoads>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/POE-Component-WWW-PAUSE-RecentUpoads>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/POE-Component-WWW-PAUSE-RecentUpoads>

=item * Search CPAN

L<http://search.cpan.org/dist/POE-Component-WWW-PAUSE-RecentUpoads>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2008 Zoffix Znet, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

