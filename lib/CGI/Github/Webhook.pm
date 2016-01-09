package CGI::Github::Webhook;

# ABSTRACT: Easily create CGI based GitHub webhooks

use strict;
use warnings;
use 5.010;

# VERSION

use Moo;
use CGI;
#use Data::Dumper;
use JSON;
use Try::Tiny;
use Digest::SHA qw(hmac_sha1_hex);

=head1 SYNOPSIS

CGI::Github::Webhook allows one to easily create simple, CGI-based
GitHub webhooks.

    #!/usr/bin/perl

    use CGI::Github::Webhook;

    my $ghwh = CGI::Github::Webhook->new(
        mime_type => 'text/plain',
        trigger => '/srv/some-github-project/bin/deploy.pl',
        trigger_backgrounded => 1,
        secret => 'use a generated password here, nothing valuable',
        log => '/srv/some-github-project/log/trigger.log',
        text_on_success => 'Successfully triggered',
        text_on_auth_fail => 'Authentication failed',
        text_on_trigger_fail => 'Trigger failed',
        ...
    );
    $ghwh->run();

    ...



=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 CONSTRUCTOR

=head2 new

Constructor. Takes a configuration hash (or array) as parameters.

=head3 List of parameters for new() constructor.

=head4 cgi

The CGI.pm object internally used.

=cut

has cgi => (
    is => 'ro',
    default => sub { CGI->new() },
    );

=head4 log

Where to send the trigger's output to. Defaults to '/dev/stderr',
i.e. goes to the web server's error log. Use '/dev/null' to disable.

For now it needs to be a path on the file system. Passing file handles
objects doesn't work (yet).

=cut

has log => (
    is => 'ro',
    default => '/dev/stderr',
    isa => sub { die "$_[0] doesn't exist!" unless -e $_[0]; },
    );

=head4 mime_type

The mime-type used to return the contents. Defaults to 'text/plain;
charset=utf-8' for now.

=cut

has mime_type => (
    is => 'ro',
    default => 'text/plain; charset=utf-8',
    );

=head4 secret

The shared secret you entered on GitHub as secret for this
trigger. Currently required. I recommend to use the output of
L<makepasswd(1)>, L<apg(1)>, L<pwgen(1)> or using
L<Crypt::GeneratePassword> to generate a randon and secure shared
password.

=cut

has secret => (
    is => 'ro',
    required => 1,
    );

=head4 text_on_success

Text to be returned to GitHub as body if the trigger was successfully
(or at least has been spawned successfully). Defaults to "Successfully
triggered".

=cut

has text_on_success => (
    is => 'rw',
    default => 'Successfully triggered',
    );

=head4 text_on_auth_fail

Text to be returned to GitHub as body if the authentication
failed. Defaults to "Authentication failed".

=cut

has text_on_auth_fail => (
    is => 'rw',
    default => 'Authentication failed',
    );

=head4 text_on_trigger_fail

Text to be returned to GitHub as body if spawning the trigger
failed. Defaults to "Trigger failed".

=cut

has text_on_trigger_fail => (
    is => 'rw',
    default => 'Trigger failed',
    );


=head4 trigger

The script or command which should be called when the webhook is
called. Required.

=cut

has trigger => (
    is => 'rw',
    required => 1,
);

=head4 trigger_backgrounded

Boolean attribute controlling if the script or command passed as
trigger needs to be started backgrounded (i.e. if it takes longer than
a few seconds) or not. Defaults to 1 (i.e. that the trigger script is
backgrounded).

=cut

has trigger_backgrounded => (
    is => 'rw',
    default => 1,
);

=head1 SUBROUTINES/METHODS

=head2 run

Start the authentication verification and run the trigger if the
authentication succeeds.

Returns true on success, false on error. More precisely it returns a
defined false on error launching the trigger and undef on
authentication error.

=cut

sub run {
    my $self = shift;

    #TODO my $basedir = '/srv/dpmb';
    my $logfile = $self->log;
    my $q       = $self->cgi;
    my $secret  = $self->secret;

    print $q->header($self->mime_type);

    open(my $logfh, '>>', $logfile);
    say $logfh "Date: ".localtime;
    say $logfh "Remote IP: ".$q->remote_host()." (".$q->remote_addr().")";

    my $payload = '';
    try {
        $payload = decode_json($q->param('POSTDATA'));
    } catch {
        $payload = $_;
    };
    $payload ||= '<no payload>';

    my $x_hub_signature =
        $q->http('X-Hub-Signature') || '<no-x-hub-signature>';
    my $calculated_signature = 'sha1='.
        hmac_sha1_hex(''.($q->param('POSTDATA') || '<no payload>'), $secret);

    print $logfh Dumper($payload, $x_hub_signature, $calculated_signature);

    if ($x_hub_signature eq $calculated_signature) {
        say $self->text_on_success;
        say $logfh $self->text_on_success;
        close $logfh;

        my $rc = system($self->trigger.' >> '.$logfile.' 2>&1 '.
                        ($self->trigger_backgrounded ? '&' : ''));
        if ($rc == 0) {
            say $self->text_on_trigger_fail;
            say $logfh $self->text_on_trigger_fail;
            if ($? == -1) {
                say $logfh "Trigger failed to execute: $!";
            } elsif ($? & 127) {
                printf $logfh "child died with signal %d, %s coredump\n",
                ($? & 127),  ($? & 128) ? 'with' : 'without';
            } else {
                printf $logfh "child exited with value %d\n", $? >> 8;
            }
            return 0;
        } else {
            return 1;
        }
    } else {
        say $self->text_on_auth_fail;
        say $logfh $self->text_on_auth_fail;
        close $logfh;
        return; # undef or empty list, i.e. false
    }
}

=head1 AUTHOR

Axel Beckert, C<< <abe@deuxchevaux.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-cgi-github-webhook
at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CGI-Github-Webhook>.
I will be notified, and then you'll automatically be notified of
progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CGI::Github::Webhook

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=CGI-Github-Webhook>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/CGI-Github-Webhook>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/CGI-Github-Webhook>

=item * Search CPAN

L<https://metacpan.org/release/CGI-Github-Webhook>

=back


=head1 LICENSE AND COPYRIGHT

Copyright 2016 Axel Beckert.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.


=cut

1; # End of CGI::Github::Webhook

