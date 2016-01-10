#!/usr/bin/perl

use strict;
use warnings;
use 5.010;

use Test::More;
use File::Temp qw(tempfile);
use Digest::SHA qw(hmac_sha1_hex);
use File::Basename;

my ($fh1, $tmplog) = tempfile();
my ($fh2, $tmpout) = tempfile();
my $secret = 'bar';
my $json = '{"fnord":"gnarz"}';
my $signature = 'sha1='.hmac_sha1_hex($json, $secret);
my $dir = dirname($0);

$ENV{HTTP_X_HUB_SIGNATURE} = $signature;

is(system("perl -I$dir/../lib $dir/cgi/basic.pl 'echo foo' $secret $tmplog 'POSTDATA=$json'".
          "> $tmpout 2>&1"),
   0, 'system exited with zero');

system('head', $tmplog, $tmpout);

done_testing();
