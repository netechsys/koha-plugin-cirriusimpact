#!/usr/bin/perl

=head1 NAME

install_sms_driver.pl - Install SMS::Send::CirriusImpact driver

=head1 SYNOPSIS

    sudo perl install_sms_driver.pl

=head1 DESCRIPTION

This script installs the SMS::Send::CirriusImpact driver to the system
Perl library directory. This driver is required for the CirriusImpact
plugin to integrate with Koha's message queue system.

The script must be run as root or with sudo privileges.

=cut

use strict;
use warnings;
use File::Copy;
use File::Path qw(make_path);
use File::Basename;

# ANSI color codes for output
my $GREEN = "\033[0;32m";
my $RED = "\033[0;31m";
my $YELLOW = "\033[0;33m";
my $BLUE = "\033[0;34m";
my $RESET = "\033[0m";

sub print_success { print "${GREEN}✓${RESET} ", @_, "\n"; }
sub print_error   { print "${RED}✗${RESET} ", @_, "\n"; }
sub print_warning { print "${YELLOW}⚠${RESET} ", @_, "\n"; }
sub print_info    { print "${BLUE}ℹ${RESET} ", @_, "\n"; }

# Check if running as root
sub check_root {
    if ($> != 0) {
        print_error "This script must be run as root or with sudo";
        print_info "Usage: sudo perl install_sms_driver.pl";
        exit 1;
    }
}

# Find the source driver files
sub find_source_files {
    my $script_dir = dirname(__FILE__);
    my $us_source = "$script_dir/sms_driver/SMS/Send/US/CirriusImpact.pm";
    my $intl_source = "$script_dir/sms_driver/SMS/Send/CirriusImpact.pm";
    
    unless (-f $us_source) {
        print_error "US driver source not found: $us_source";
        print_info "Make sure this script is in the CirriusImpact plugin directory";
        exit 1;
    }
    
    unless (-f $intl_source) {
        print_error "International driver source not found: $intl_source";
        print_info "Make sure this script is in the CirriusImpact plugin directory";
        exit 1;
    }
    
    return ($us_source, $intl_source);
}

# Find the system Perl library directory
sub find_perl_lib {
    my @candidates = (
        '/usr/share/perl5',
        '/usr/local/share/perl5',
        '/usr/lib/perl5',
        '/usr/local/lib/perl5',
    );
    
    # Try to find where SMS::Send is installed
    foreach my $dir (@candidates) {
        if (-d "$dir/SMS/Send") {
            return $dir;
        }
    }
    
    # Default to /usr/share/perl5 if SMS::Send not found
    return '/usr/share/perl5';
}

# Create directory if needed
sub ensure_directory {
    my ($dir) = @_;
    
    unless (-d $dir) {
        print_info "Creating directory: $dir";
        eval { make_path($dir, { mode => 0755 }); };
        if ($@) {
            print_error "Failed to create directory: $@";
            exit 1;
        }
    }
}

# Install both drivers
sub install_drivers {
    my ($us_source, $intl_source, $perl_lib) = @_;
    
    print_info "Installing SMS::Send drivers...";
    
    # Install US::CirriusImpact (main driver)
    my $us_dest_dir = "$perl_lib/SMS/Send/US";
    my $us_dest = "$us_dest_dir/CirriusImpact.pm";
    
    print_info "Installing US::CirriusImpact (regional + international)";
    print_info "  Source: $us_source";
    print_info "  Destination: $us_dest";
    
    ensure_directory($us_dest_dir);
    
    unless (copy($us_source, $us_dest)) {
        print_error "Failed to copy US driver: $!";
        exit 1;
    }
    chmod 0644, $us_dest;
    print_success "US::CirriusImpact driver installed";
    
    # Install CirriusImpact (international/legacy compatibility)
    my $intl_dest_dir = "$perl_lib/SMS/Send";
    my $intl_dest = "$intl_dest_dir/CirriusImpact.pm";
    
    print_info "Installing CirriusImpact (international compatibility)";
    print_info "  Source: $intl_source";
    print_info "  Destination: $intl_dest";
    
    ensure_directory($intl_dest_dir);
    
    unless (copy($intl_source, $intl_dest)) {
        print_error "Failed to copy international driver: $!";
        exit 1;
    }
    chmod 0644, $intl_dest;
    print_success "CirriusImpact driver installed";
}

# Verify the installation
sub verify_installation {
    print_info "Verifying installation...";
    
    my $all_ok = 1;
    
    # Verify US::CirriusImpact
    my $us_result = system('perl', '-MSMS::Send::US::CirriusImpact', '-e', 'exit 0');
    if ($us_result == 0) {
        my $version = `perl -MSMS::Send::US::CirriusImpact -e 'print \$SMS::Send::US::CirriusImpact::VERSION'`;
        print_success "US::CirriusImpact driver loaded successfully";
        print_info "Version: $version" if $version;
        my $location = `perl -MSMS::Send::US::CirriusImpact -e 'print \$INC{"SMS/Send/US/CirriusImpact.pm"}'`;
        print_info "Location: $location" if $location;
    } else {
        print_error "US::CirriusImpact driver verification failed";
        $all_ok = 0;
    }
    
    # Verify CirriusImpact (international)
    my $intl_result = system('perl', '-MSMS::Send::CirriusImpact', '-e', 'exit 0');
    if ($intl_result == 0) {
        my $version = `perl -MSMS::Send::CirriusImpact -e 'print \$SMS::Send::CirriusImpact::VERSION'`;
        print_success "CirriusImpact driver loaded successfully";
        print_info "Version: $version" if $version;
        my $location = `perl -MSMS::Send::CirriusImpact -e 'print \$INC{"SMS/Send/CirriusImpact.pm"}'`;
        print_info "Location: $location" if $location;
    } else {
        print_error "CirriusImpact driver verification failed";
        $all_ok = 0;
    }
    
    return $all_ok;
}

# Test the drivers
sub test_drivers {
    print_info "Testing driver functionality...";
    
    my $all_ok = 1;
    
    # Test US::CirriusImpact
    my $us_test = q{
        use SMS::Send;
        my $sender = SMS::Send->new('US::CirriusImpact');
        exit 0 if $sender;
        exit 1;
    };
    
    if (system('perl', '-e', $us_test) == 0) {
        print_success "US::CirriusImpact driver test passed";
    } else {
        print_warning "US::CirriusImpact test failed";
        $all_ok = 0;
    }
    
    # Test CirriusImpact
    my $intl_test = q{
        use SMS::Send;
        my $sender = SMS::Send->new('CirriusImpact');
        exit 0 if $sender;
        exit 1;
    };
    
    if (system('perl', '-e', $intl_test) == 0) {
        print_success "CirriusImpact driver test passed";
    } else {
        print_warning "CirriusImpact test failed";
        $all_ok = 0;
    }
    
    return $all_ok;
}

# Print next steps
sub print_next_steps {
    print "\n";
    print "=" x 70, "\n";
    print "${GREEN}Installation Complete!${RESET}\n";
    print "=" x 70, "\n";
    print "\n";
    print "Next steps:\n";
    print "\n";
    print "1. Configure Koha System Preferences:\n";
    print "   - Recommended: SMSSendDriver = 'US::CirriusImpact' (regional + international)\n";
    print "   - Alternative: SMSSendDriver = 'CirriusImpact' (international only, requires +)\n";
    print "\n";
    print "2. Configure the CirriusImpact plugin:\n";
    print "   - Go to: Tools > Plugins\n";
    print "   - Find CirriusImpact and click Configure\n";
    print "   - Enter your SFTP credentials\n";
    print "\n";
    print "3. Configure your notice templates:\n";
    print "   - Add 'CirriusImpact: yes' to the YAML header\n";
    print "   - See NOTICE_EXAMPLES.md for digest templates\n";
    print "\n";
    print "4. Test the message queue:\n";
    print "   - Run: sudo koha-shell INSTANCE -c '/usr/share/koha/bin/cronjobs/process_message_queue.pl'\n";
    print "\n";
    print "See INSTALL.md for detailed instructions.\n";
    print "\n";
}

# Main execution
sub main {
    print "\n";
    print "=" x 70, "\n";
    print "SMS::Send::CirriusImpact Driver Installation\n";
    print "=" x 70, "\n";
    print "\n";
    
    # Check prerequisites
    check_root();
    
    # Find sources
    my ($us_source, $intl_source) = find_source_files();
    my $perl_lib = find_perl_lib();
    
    # Check if already installed
    my $us_dest = "$perl_lib/SMS/Send/US/CirriusImpact.pm";
    my $intl_dest = "$perl_lib/SMS/Send/CirriusImpact.pm";
    
    if (-f $us_dest || -f $intl_dest) {
        print_warning "Driver(s) already installed";
        if (-f $us_dest) { print_info "  Found: $us_dest"; }
        if (-f $intl_dest) { print_info "  Found: $intl_dest"; }
        print "Overwrite? [y/N]: ";
        my $answer = <STDIN>;
        chomp $answer;
        unless ($answer =~ /^[Yy]/) {
            print_info "Installation cancelled";
            exit 0;
        }
    }
    
    # Install both drivers
    install_drivers($us_source, $intl_source, $perl_lib);
    
    # Verify
    unless (verify_installation()) {
        print_error "Installation completed but verification failed";
        exit 1;
    }
    
    # Test
    test_drivers();
    
    # Done
    print_next_steps();
    
    exit 0;
}

# Run main
main();

__END__

=head1 AUTHOR

ByWater Solutions

=head1 COPYRIGHT

Copyright 2025 ByWater Solutions

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut



