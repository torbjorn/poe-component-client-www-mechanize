package t::lib::TestUtils;

use strict;
use warnings;
use POE::Declare::HTTP::Server;
use feature ':all';

sub import {

    my($package,$alias) = (shift,shift);
    my %handlers = @_;

    $_ = "poe:$alias/$_" for values %handlers;

    POEx::HTTP::Server->spawn(
        inet => {
            LocalPort => 8000,
        },
        handlers => [
            %handlers
        ]
    );

}

1;
