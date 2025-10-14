package SMS::Send::CirriusImpact;

=head1 NAME

SMS::Send::CirriusImpact - SMS::Send driver for CirriusImpact

=head1 SYNOPSIS

  use SMS::Send;
  
  my $sender = SMS::Send->new('CirriusImpact');
  
  # Accepts international format
  my $sent = $sender->send_sms(
      text => 'This is a test message',
      to   => '+1 555 1234',
  );
  
  # Also accepts other international formats
  $sender->send_sms(
      text => 'Hello from the UK',
      to   => '+44 20 1234 5678',
  );
  
  # And regional/local formats
  $sender->send_sms(
      text => 'Local format',
      to   => '(555) 123-4567',
  );

=head1 DESCRIPTION

This is an SMS::Send INTERNATIONAL-class driver for CirriusImpact. It
integrates with the Koha CirriusImpact plugin which handles the actual
message delivery via SFTP export to CirriusImpact's service.

As an international-class driver (SMS::Send::CirriusImpact, not
SMS::Send::US::CirriusImpact), this driver accepts phone numbers in any
format - international (+1, +44, +61, etc.) or regional formats. The
driver does not validate phone number format and passes all numbers
through to the CirriusImpact service.

Messages sent through this driver are intercepted by the CirriusImpact
plugin's before_send_messages hook, exported to CSV format, and uploaded
via SFTP. This driver simply returns success to indicate the message
has been queued.

=cut

use strict;
use warnings;
use SMS::Send::Driver ();

our $VERSION = '1.0.0';
our @ISA = 'SMS::Send::Driver';

=head1 METHODS

=head2 new

  my $sender = SMS::Send::CirriusImpact->new();

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
      to   => '+1 555 1234',
      text => 'This is a test message',
  );

Sends an SMS message. Returns 1 on success, 0 on failure.

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
    
    return 1;
}

=head2 sends_to_anyone

  my $flexible = $driver->sends_to_anyone();

Returns true to indicate this driver accepts phone numbers in any format,
including regional (non-international) formats. This tells SMS::Send to
skip phone number format validation.

The CirriusImpact service handles phone number validation and formatting,
so we accept numbers in any format provided by Koha.

=cut

sub sends_to_anyone {
    return 1;
}

1;

=head1 CONFIGURATION

This driver is configured through the Koha CirriusImpact plugin.
To use it, set the following in Koha:

1. System Preferences > SMSSendDriver = "CirriusImpact"
2. Configure the CirriusImpact plugin with your SFTP credentials
3. Ensure notices contain the YAML header: CirriusImpact: yes

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

