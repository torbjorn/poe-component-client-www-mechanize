package POE::Component::Client::WWW::Mechanize;

use warnings;
use strict;
use utf8;

use Carp;

use WWW::Mechanize;
use POE;
use base qw(POE::Component::Syndicator);
use HTTP::Request;
use Try::Tiny;

my $http_backend;
my $backend_default = q(POE::Component::Client::HTTP);

use Module::Runtime qw/use_module/;

sub import {

    my $package = shift;

    my $backend = $_[0] || "POE::Component::Client::HTTP";

    try {
        use_module( $backend );
        $http_backend = $backend;
    } catch {
        carp "Failed loading '$backend', falling back to '$backend_default'";
        use_module( $backend_default );
        $http_backend = $backend_default;
    }

}

use version; our $VERSION = qv('0.0.1');

sub _random_tag {
    unpack "h*", rand;
}

## Public Methods

sub spawn {

    my $package = shift;
    my %args = @_;

    my($alias) = delete $args{Alias};

    ## Give the internal http client a random alias
    my $http_client_alias = "PoCo-" . unpack "h*", rand;
    $args{Alias} = $http_client_alias;

    my $http = $http_backend->spawn(%args);

    my $self = bless {
        mech => WWW::Mechanize->new( agent => $args{Agent} ),
        post_to_http_client => sub {
            $poe_kernel->post( $http_client_alias, @_ );
        },
    }, $package;

    $self->_syndicator_init(
        prefix => 'mech_',
        alias => $alias,
        object_states => [
            $self => [qw/
                            syndicator_started
                            syndicator_shutdown
                            request
                            get
                            _after_request_cleanup
                        /],
        ],

    );

    return bless $self, $package;

}

## Private Methods

sub new_request {

    my $self = shift;

    my $req = HTTP::Request->new( @_ );

    $self->massage_request($req);

}

sub massage_request {

    my ($self,$request) = (shift,shift);

    ## a trick to make mech do all the things we want it to do with
    ## the request before submitting it
    my $mech = $self->{mech};

    $mech->add_handler( "request_send", sub { HTTP::Response->new } );
    $mech->request($request);
    $mech->back;
    $mech->remove_handler( "request_send" );

    $request;

}

## Events

sub syndicator_started {
    return 1;
}

sub syndicator_shutdown {
    $_[HEAP]->{post_to_http_client}->("shutdown");
}

sub request {

    my($self,$kernel,$heap,$sender,
       $response_event,$request,
       $tag,$progress_event,$proxy) =
        @_[OBJECT,KERNEL,HEAP,SENDER,ARG0,ARG1,ARG2,ARG3,ARG4];

    $tag //= _random_tag;

    $heap->{after_request_action}{$tag} //= [$sender->ID,$response_event];

    $heap->{post_to_http_client}->(
        request => "_after_request_cleanup",
        $request,
        $tag,
        $progress_event,
        $proxy
    );

}

sub get {

    my($self,$kernel,$heap,$sender,
       $url,$response_event,$tag,
       $progress_event, $proxy
   ) = @_[OBJECT,KERNEL,HEAP,SENDER,
          ARG0,ARG1,ARG2,ARG3,ARG4];

    $tag //= _random_tag;
    $_[HEAP]->{after_request_response_event}{$tag} //= [$sender,$response_event];

    my $request = $self->new_request( GET => $url );

    $kernel->yield( request => $response_event,
                    $request, $tag,
                );

}

sub _after_request_cleanup {

    my($self,$heap,$kernel,
       $request_packet,$response_packet) =
        @_[OBJECT,HEAP,KERNEL,ARG0,ARG1];

    my $tag = $request_packet->[1];

    my($sender,$action) = @{ delete $heap->{after_request_action}{$tag} };

    my $mech = $self->{mech};

    my $request = $request_packet->[0];
    my $response = $response_packet->[0];

    ## plant the response in the Mech
    if ( $response->is_success ) {
        $mech->add_handler( "request_send", sub { $response } );
        $mech->request($request);
        $mech->remove_handler( "request_send" );
    }

    $kernel->post( $sender, $action, $request_packet, $response_packet ) or die $!;

}

1;
__END__

=encoding utf8

=head1 NAME

POE::Component::Client::WWW::Mechanize - [One line description of module's purpose here]

=head1 VERSION

This document describes POE::Component::Client::WWW::Mechanize version 0.0.1


=head1 SYNOPSIS

    use POE::Component::Client::WWW::Mechanize;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.


=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.


=head1 PUBLIC METHODS

=head2 spawn

Creates the component. Takes the same argument as PoCo::HTTP::Client.

=head1 PRIVATE METHODS

=head2 new_request

Internal method. Creates a new request. Takes same arguments as
HTTP::Request->new.

=head2 massage_request

Internal method. For manually created requests, this function lets
WWW::Mechanize add cookies etc. essentially make it look like W::M
would have make it look like before sending it.

=head1 INTERESTING EVENTS

=head2 request

Argument list: $response, $request, $tag, $progress, $proxy

Works just like the request event in PoCo::Client::HTTP

=head2 get

Performs a get request,

Argument list: $url, $response, $tag, $progress, $proxy

Gets a url. A shortcut for the request event.

=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.

POE::Component::Client::WWW::Mechanize requires no configuration files or environment variables.


=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-poe-component-client-www-mechanize@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.

=head1 SEE ALSO

L<Some::Other::Module>,
L<Also::Anoter::Module>

=head1 AUTHOR

<AUTHOR>  C<< <<EMAIL>> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) <YEAR>, <AUTHOR> C<< <<EMAIL>> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
