package SMS::Send::US::CirriusImpact;

=head1 NAME

SMS::Send::US::CirriusImpact - SMS::Send driver for CirriusImpact (US/International)

=head1 SYNOPSIS

  use SMS::Send;
  
  my $sender = SMS::Send->new('US::CirriusImpact');
  
  # Accepts US regional format
  my $sent = $sender->send_sms(
      text => 'This is a test message',
      to   => '555 123 4567',
  );
  
  # Also accepts international formats
  $sender->send_sms(
      text => 'International message',
      to   => '+44 20 1234 5678',
  );

=head1 DESCRIPTION

This is an SMS::Send US-regional driver for CirriusImpact. Although named
as a US driver (to allow regional US phone numbers without + prefix), it
actually works internationally and accepts phone numbers in ANY format.

The driver integrates with the Koha CirriusImpact plugin which handles
the actual message delivery via SFTP export to CirriusImpact's service.

As a US-regional driver, it accepts:
- US regional numbers: 7315551234, (731) 555-1234
- International numbers: +44 20 1234 5678, +1 732 586 1275
- Any other format - no validation performed

Messages sent through this driver are intercepted by the CirriusImpact
plugin's before_send_messages hook, exported to CSV format, and uploaded
via SFTP. This driver simply returns success to indicate the message
has been queued.

=cut

use strict;
use warnings;
use SMS::Send::Driver ();

our $VERSION = '1.0.1';
our @ISA = 'SMS::Send::Driver';

=head1 METHODS

=head2 new

  my $sender = SMS::Send::US::CirriusImpact->new();

Creates a new CirriusImpact driver instance. Accepts optional parameters:

  _login    - Username (optional, configured via Koha preferences)
  _password - Password (optional, configured via Koha preferences)

=cut

sub new {
    my $class = shift;
    my %params = @_;
    
    # Create the object
    my $self = bless {
        _login    => $params{_login},
        _password => $params{_password},
    }, $class;
    
    return $self;
}

=head2 send_sms

  my $sent = $sender->send_sms(
      to   => '555 123 4567',
      text => 'This is a test message',
  );

Sends an SMS message. Returns 1 on success, 0 on failure.

Accepts phone numbers in ANY format:
- US regional: 7325861275, (732) 586-1275
- US international: +1 731 555 1234
- Other international: +44 20 1234 5678, +61 2 1234 5678

The message is not actually sent by this driver - it is intercepted by
the CirriusImpact plugin's before_send_messages hook and added to the
export queue.

=cut

sub send_sms {
    my $self = shift;
    my %params = @_;
    
    # Validate required parameters
    unless ( $params{to} && $params{text} ) {
        warn "CirriusImpact driver: Missing required parameters (to and text)";
        return 0;
    }
    
    # The actual sending is handled by the CirriusImpact plugin's
    # before_send_messages hook. We just return success here to indicate
    # the message has been queued.
    
    # Note: We don't validate phone number format - CirriusImpact service
    # handles international numbers, so we accept any format
    
    return 1;
}

1;

=head1 CONFIGURATION

This driver is configured through the Koha CirriusImpact plugin.
To use it, set the following in Koha:

1. System Preferences > SMSSendDriver = "US::CirriusImpact"
2. Configure the CirriusImpact plugin with your SFTP credentials
3. Ensure notices contain the YAML header: CirriusImpact: yes

=head1 INTERNATIONAL SUPPORT

Although this is a US-regional driver (SMS::Send::US::CirriusImpact),
it works with international phone numbers. The "US::" prefix allows
regional US numbers without + prefix, but the driver accepts and passes
through international numbers as well.

Supported formats:
- US regional: 7315551234, (731) 555-1234
- US international: +1 731 555 1234
- UK: +44 20 1234 5678
- Australia: +61 2 1234 5678
- Any other international format

=head1 SUPPORT

For issues with this driver, contact your system administrator or
ByWater Solutions.

=head1 AUTHOR

ByWater Solutions

=head1 COPYRIGHT

Copyright 2025 ByWater Solutions

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut









