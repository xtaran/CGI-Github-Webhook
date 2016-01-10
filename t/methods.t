#!/usr/bin/perl

use strict;
use warnings;
use 5.010;

use Test::More;
use File::Temp qw(tempfile);
use Digest::SHA qw(hmac_sha1_hex);
use File::Basename;
use File::Slurper qw(read_text);

my ($fh1, $tmplog) = tempfile();
my ($fh2, $tmpout) = tempfile();
my $secret = 'bar';
my $json = '{"fnord":"gnarz"}';
my $signature = 'sha1='.hmac_sha1_hex($json, $secret);
my $dir = dirname($0);

$ENV{HTTP_X_HUB_SIGNATURE} = $signature;
$ENV{QUERY_STRING} = "POSTDATA=$json";
$ENV{GATEWAY_INTERFACE} = 'CGI/1.1';
$ENV{REQUEST_METHOD} = 'GET';

use_ok('CGI::Github::Webhook');

my $ghwh = CGI::Github::Webhook->new(
    trigger => 'echo foo',
    trigger_backgrounded => 0,
    secret => $secret,
    log => $tmplog,
    );

is($ghwh->header(),
   "Content-Type: text/plain; charset=utf-8\r\n\r\n",
   'header method returns expected Content-Type header');
ok($ghwh->authenticated, 'Authentication successful');
ok($ghwh->authenticated,
   'Authentication still considered successful on a second retrieval');

done_testing();
