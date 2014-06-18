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

use feature ':all';

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

## Public Methods

sub spawn {

    my $package = shift;
    my %args = @_;

    my($alias) = delete $args{Alias};
    $alias //= "mech";

    ## Give the internal http client a random alias
    my $http_client_alias = "PoCo-" . unpack "h*", rand;
    $args{Alias} = $http_client_alias;

    my $http = $http_backend->spawn(%args);

    my $self = bless {
        mech => WWW::Mechanize->new( agent => $args{Agent} ),
        call_to_http_client => sub {
            $poe_kernel->call( $http_client_alias, @_ );
        },
        ( $args{Streaming} ? (Streaming => 1) : () )
    }, $package;

    my @mech_interface =
        qw/
              forms
              form_number form_name form_id form_with_fields
              field select set_fields set_visible
              tick untick value

              add_header delete_header quiet stack_depth save_content
              dump_headers dump_links dump_images dump_forms dump_text

              clone redirect_ok update_html credentials get_basic_credentials
              clear_credentials
          /;

    my %mech_extra;
    @mech_extra{@mech_interface} = ("mech_interface")x@mech_interface;

    {
        no strict 'refs';
        for (@mech_interface) {
            my $name = __PACKAGE__ . "::" . $_;
            *$name = \&mech_interface;
        }
    }

    $self->_syndicator_init(
        prefix => 'mech_',
        alias => $alias,
        object_states => [
            $self => {
                shutdown => "syndicator_shutdown",

                get => "get_like",
                delete => "get_like",
                head => "get_like",

                post => "post_like",
                put => "post_like",



                %mech_extra,

            },
            $self => [
                qw/
                      request cancel

                      form_number
                      field

                      pending_requests_count

                      _after_request_cleanup
                      syndicator_started
                  /
            ]
        ],

    );

    return bless $self, $package;

}

## Private Methods

sub new_request {

    my($self,$method) = (shift,shift);

    my $mech = $self->{mech};

    my $request;

    $mech->add_handler( "request_send", sub { $request = shift; HTTP::Response->new } );
    $mech->$method(@_);
    $mech->back;
    $mech->remove_handler( "request_send" );

    return $request;

}
sub massage_request {

    my($self,$request) = (shift,shift);

    my $mech = $self->{mech};

    $mech->_modify_request( $request );

    # $mech->add_handler( "request_send", sub { HTTP::Response->new } );
    # $mech->request($request);
    # $mech->back;
    # $mech->remove_handler( "request_send" );

    $request;

}

## Functions for internal use

sub _register_request {

    # my($self,$kernel,$heap,$sender,
    #    $response_event,$request,
    #    $tag,$progress_event,$proxy) =
    #     @_[OBJECT,KERNEL,HEAP,SENDER,ARG0,ARG1,ARG2,ARG3,ARG4];

    $_[HEAP]->{after_request_action} //= {};

    ## assumes sender is the session from which the request started
    if ( not exists $_[HEAP]->{after_request_action}{ $_[ARG1] } ) {

        ## ARG0: response_event name
        ## ARG1: request

        $_[KERNEL]->refcount_increment( $_[SENDER]->ID, "pending-requests" );
        $_[HEAP]->{after_request_action}{ $_[ARG1] } = [ $_[SENDER]->ID, $_[ARG0], $_[ARG1] ];

    }
    else {
       ## Leave it for now
    }

}
sub _unregister_request {

    ## ARG0: [ request, tag ]
    ## ARG1: [ response, content ]

    my $sender_id = $_[HEAP]->{after_request_action}{$_[ARG0]->[0]}[0];
    $_[KERNEL]->refcount_decrement( $sender_id, "pending-requests" );
    delete $_[HEAP]->{after_request_action}{$_[ARG0]->[0]};

}

## Events

sub syndicator_started {}
sub syndicator_shutdown {
    $_[HEAP]->{call_to_http_client}->("shutdown");
    $_[OBJECT]->_syndicator_destroy;
}
sub _after_request_cleanup {

    ## ARG0 is request_packet
    ## ARG1 is response_packet

    my($self,$heap,$kernel,
       $request_packet,$response_packet) =
        @_[OBJECT,HEAP,KERNEL,ARG0,ARG1];

    my $tag = $request_packet->[1];

    my $mech = $self->{mech};

    my $request = $request_packet->[0];
    my $response = $response_packet->[0];

    my($sender_id,$action) = @{ $heap->{after_request_action}{$request} };

    if ( $self->{Streaming} ) {

        ## don't bother with inserting the response into W::M
        if (
            not $response->is_success or
            not $response->content
                and not defined($response_packet->[1])
            ) {

            &_unregister_request;
        }

    }
    else {

        ## plant the response in the Mech
        if ( $response->is_success ) {
            $mech->add_handler( "request_send", sub { $response } );
            $mech->request($request);
            $mech->remove_handler( "request_send" );
        }

        &_unregister_request;
    }

    $kernel->post( $sender_id, $action, $request_packet, $response_packet ) or die $!;

}

## From PoCo::C::H

sub request {

    my($self,$kernel,$heap,$sender,
       $response_event,$request,
       $tag,$progress_event,$proxy) =
        @_[OBJECT,KERNEL,HEAP,SENDER,ARG0,ARG1,ARG2,ARG3,ARG4];

    $self->massage_request($request);

    &_register_request;

    $heap->{call_to_http_client}->(
        request => "_after_request_cleanup",
        $request,
        $tag,
        defined $progress_event ? $sender->postback( $progress_event ) : undef,
        $proxy
    );

}
sub cancel {
    $_[OBJECT]->{call_to_http_client}->("cancel",$_[ARG0]);
}
sub pending_requests_count {
    $_[OBJECT]->{call_to_http_client}->("pending_requests_count");
}

## Made to match W::M's interface

sub get_like {

    my($self,$kernel,$heap,$sender,
       $url,$response_event,$tag,
       $progress_event, $proxy
   ) = @_[OBJECT,KERNEL,HEAP,SENDER,
          ARG0,ARG1,ARG2,ARG3,ARG4];

    my @rest_of_args = grep defined, @_[ARG5 .. $#_ ];

    my $request = $self->new_request( get => $url, @rest_of_args );

    {
        ## This was a bit unfortunate, but can live with it
        local @_[ARG0,ARG1] = ($response_event,$request);
        &_register_request;
    }

    $kernel->yield( request => "_after_request_cleanup",
                    $request, $tag,
                );

}
sub post_like {

    my($self, $kernel, $heap, $sender,
       $url, $content, $response_event, $tag, $progress_event, $proxy ) =
           @_[OBJECT,KERNEL,HEAP,SENDER,
              ARG0,ARG1,ARG2,ARG3,ARG4,ARG5];

    $content //= {};

    my @rest_of_args = grep defined, @_[ARG6 .. $#_ ];

    my $request = $self->new_request( $_[STATE] => $url, $content, @rest_of_args );

    {
        ## @_ will be a mess after this, but only need 0 and 1 anyway
        local @_[ARG0,ARG1] = ($response_event,$request);
        &_register_request;
    }

    $kernel->yield( request => "_after_request_cleanup",
                    $request, $tag,
                );

}

## form selectors
sub mech_interface {
    ## make sure event is named as mech method
    my $method = $_[STATE];
    return $_[HEAP]->{mech}->$method( @_[ ARG0..$#_ ] );
}

1;
__END__

=encoding utf8

=head1 NAME

POE::Component::Client::WWW::Mechanize - Have WWW::Mechanize use
PoCo::Client::HTTP for http requests, essentially making W::M
asynchronously.

=head1 VERSION

This document describes POE::Component::Client::WWW::Mechanize version 0.0.1

=head1 SYNOPSIS

    use POE qw(Component::Client::WWW::Mechanize);

    ## spawn takes exact same arguments as PoCo::Client::HTTP
    POE::Component::Client::WWW::Mechanize->spawn( Alias => "mech" );

    POE::Session->create(
        inline_states => {
            _start => sub {
                $_[KERNEL]->post( "mech", get => "http://metacpan.org", "got_response" )
            }
        }
    );

    ## Gets the same argument list as the response handler of PoCo::HTTP::Client
    sub got_response {
        print "Jay, got a response!\n";
        print "Headers:\n"
        print $_[ARG1]->[0]->headers->as_string;
        print "-"x80, "\n";
        print "Request looked like this:";
        print $_[ARG0]->[0]->as_string;
    }

=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.


=head1 PUBLIC METHODS

=head2 spawn

Creates the component. Takes the same argument as PoCo::HTTP::Client.

=head1 PRIVATE METHODS

=head2 new_request

Internal method. Creates a new request from various input. First
argument is method, following arguments is what would have been used
for the corresponding method in LWP::UserAgent.

Example: my $request = $self->new_request( "get", "http://uri" )

It brings with it all the things that W::M would have brought. Ie
cookies etc.

=head2 massage_request

Internal method. For manually created requests, this function lets
WWW::Mechanize add cookies etc. essentially make it look like W::M
would have make it look like before sending it.

=head1 INTERESTING EVENTS

=head2 request

Argument list: $response, $request, $tag, $progress, $proxy

Works just like the request event in PoCo::Client::HTTP.

=head2 get

Performs a GET request,

Argument list: $url, $response, $tag, $progress, $proxy, @additional

Gets a url. A shortcut for the request event.

=head2 post

Performs a POST request,

Argument list: $url, $response, $content, $tag, $progress, $proxy, @additional

=head2 cancel

Cancels the current ongoing request.

Works the same way as cancel for PCHC.

=head2 field

Changes the value of a field in the current form.

=head2 form_number

Sets which form number to use, as in W::M.

=head2 pending_requests_count

Is mirrored to PCHC.

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
