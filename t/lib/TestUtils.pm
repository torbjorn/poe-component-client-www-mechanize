package t::lib::TestUtils;

use strict;
use warnings;

use POE;
sub POE::Component::Server::SimpleHTTP::DEBUG () { 0 }
use POE::Component::Server::SimpleHTTP;
use base 'Exporter';

use feature ':all';

use Devel::Dwarn;

my($uri,$html);

sub import {

    my($package) = (shift);

    set_variables($_[0]);

    # my @args = @_;

    # if ( @args == 1 ) {
    #     unshift @args, "", "test";
    # }
    # elsif ( @args == 2 ) {
    #     unshift @args, "";
    # }
    # elsif ( @args and @args != 3 ) {
    #     die "Need 3'ish arguments to import";
    # }

    # my %handler;
    # @handler{qw/DIR SESSION EVENT/} = @args if @args;

    POE::Session->create(
        inline_states => {
            _start => sub { $_[KERNEL]->alias_set("temp") },
            server_handler => \&server_handler,
        }
    );

    my %handler = (
        DIR => "",
        SESSION => "temp",
        EVENT => "server_handler",
    );

    POE::Component::Server::SimpleHTTP->new(
        HOSTNAME => '127.0.0.1',
        ALIAS    => "httpd",
        PORT     => 8000,
        HEADERS  => {},
        HANDLERS => [\%handler],
    );

}

sub _start {
    $_[KERNEL]->alias_set("temp");
}

sub server_handler {

    my($request,$response,$dirmatch) = @_[ARG0,ARG1,ARG2];

    # Webby content generation stuff here
    $response->code( 200 );
    $response->content_type( "text/html" );
    $response->content( $html );

    $_[KERNEL]->post( "httpd", "DONE", $response ) or die $!;

}

sub set_variables {

    $uri = shift;

    $html = <<EOC;
<!doctype html>

<html lang="en">
<head>
  <meta charset="utf-8">

  <title>HTML Title</title>
  <meta name="description" content="HTML5 Sample content">
  <meta name="author" content="PoCo::Mech">

  <link rel="stylesheet" href="css/styles.css?v=1.0">

</head>

<body>
HTML Content

<form name="form1" method="post" action="$uri">
<input name="testinput" value="a default value"/>
<input name="imhidden" value="a hidden value"/>
<input type="submit"/>
</form>

<form id="form2" method="post" action="$uri&fromform=2">
<input name="box2" value="value2" type="checkbox"/>
<input type="submit"/>
</form>

<a href="$uri&step=2">This is a link</a>

<script src="js/a_script_file.js"></script>
</body>
</html>
EOC


}

1;
