#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;

#use CGI;
#my $cgi = CGI->new();

use CGI::Github::Webhook;

my $ghwh = CGI::Github::Webhook->new(
    trigger => 'echo foo',
    trigger_backgrounded => 0,
    secret => 'bar',
    log => '/dev/stdout',
    );
my $rc = $ghwh->run();

if ($rc) {
    exit 0
} else {
    exit 1
}
