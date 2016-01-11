#!/usr/bin/perl

use strict;
use warnings;
use 5.010;

use Test::More;
use File::Temp qw(tempfile);
use Digest::SHA qw(hmac_sha1_hex);
use File::Basename;
use File::Slurper qw(read_text);

if ($^O eq 'dos' or $^O eq 'os2' or $^O eq 'MSWin32' ) {
    plan skip_all => 'these tests do not work on dos-ish systems';
} else {
    plan tests => 6;
}

my ($fh1, $tmplog) = tempfile();
my ($fh2, $tmpout) = tempfile();
my $secret = 'bar';
my $json = '{"fnord":"gnarz"}';
my $signature = 'sha1='.hmac_sha1_hex($json, $secret);
my $dir = dirname($0);

$ENV{HTTP_X_HUB_SIGNATURE} = $signature;

is(system("$^X -I$dir/../lib $dir/cgi/basic.pl 'echo foo' $secret $tmplog 'POSTDATA=$json'".
          "> $tmpout 2>&1"),
   0, 'system exited with zero');
is(read_text($tmpout),
   "Content-Type: text/plain; charset=utf-8\r\n\r\nSuccessfully triggered\n",
   "CGI output as expected");
my $log = read_text($tmplog);
$log =~ s/^Date:.*/Date:/;
is($log, "Date:
Remote IP: localhost (127.0.0.1)
\$VAR1 = {
          'fnord' => 'gnarz'
        };
\$VAR2 = 'sha1=f0265993a0e0c508b277666562b3e36ed3d5695d';
\$VAR3 = 'sha1=f0265993a0e0c508b277666562b3e36ed3d5695d';
foo
Successfully triggered
", "CGI log file as expected");

# Reset the log file
($fh1, $tmplog) = tempfile();

isnt(system("$^X -I$dir/../lib $dir/cgi/basic.pl false $secret $tmplog 'POSTDATA=$json'".
            "> $tmpout 2>&1"),
     0, 'system calling false as trigger exited with non-zero');
is(read_text($tmpout),
   "Content-Type: text/plain; charset=utf-8\r\n\r\nTrigger failed\n",
   "CGI output as expected");
$log = read_text($tmplog);
$log =~ s/^Date:.*/Date:/;
is($log, "Date:
Remote IP: localhost (127.0.0.1)
\$VAR1 = {
          'fnord' => 'gnarz'
        };
\$VAR2 = 'sha1=f0265993a0e0c508b277666562b3e36ed3d5695d';
\$VAR3 = 'sha1=f0265993a0e0c508b277666562b3e36ed3d5695d';
false >> $tmplog 2>&1 
Trigger failed
child exited with value 1
", "CGI log file as expected");
