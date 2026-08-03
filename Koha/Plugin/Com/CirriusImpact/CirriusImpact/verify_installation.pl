#!/usr/bin/perl

=head1 NAME

verify_installation.pl - Verify CirriusImpact plugin installation

=head1 SYNOPSIS

    perl verify_installation.pl
    # or
    sudo perl verify_installation.pl

=head1 DESCRIPTION

This script verifies that the CirriusImpact plugin and SMS::Send driver
are properly installed and configured.

=cut

use strict;
use warnings;
use File::Spec;
use File::Basename;
use Cwd qw(abs_path);

# install_sms_driver.pl installs the drivers under <pluginsdir>/SMS/Send.
# Koha puts <pluginsdir> in @INC at runtime, but a standalone run of this
# script does not, so add the plugins root (dir containing Koha/Plugin)
# ourselves before the driver checks.
BEGIN {
    my $dir = dirname( abs_path(__FILE__) );
    for ( 1 .. 6 ) {
        $dir = dirname($dir);
        if ( -d "$dir/Koha/Plugin" ) {
            unshift @INC, $dir;
            last;
        }
    }
}

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
sub print_header  { print "\n${BLUE}", "=" x 70, "${RESET}\n", @_, "\n", "${BLUE}", "=" x 70, "${RESET}\n\n"; }

my $errors = 0;
my $warnings = 0;

# Check if SMS::Send is installed
sub check_sms_send {
    print_info "Checking SMS::Send installation...";
    
    eval { require SMS::Send; };
    if ($@) {
        print_error "SMS::Send is not installed";
        print_info "Install with: cpan SMS::Send";
        $errors++;
        return 0;
    }
    
    print_success "SMS::Send is installed";
    return 1;
}

# Check if CirriusImpact driver is installed
sub check_driver_installed {
    print_info "Checking SMS::Send driver installation...";
    
    # Check for US::CirriusImpact (current/recommended)
    my $us_driver_ok = 0;
    eval { require SMS::Send::US::CirriusImpact; };
    if (!$@) {
        my $version = $SMS::Send::US::CirriusImpact::VERSION || 'unknown';
        my $location = $INC{"SMS/Send/US/CirriusImpact.pm"} || 'unknown';
        print_success "SMS::Send::US::CirriusImpact driver is installed (current)";
        print_info "Version: $version";
        print_info "Location: $location";
        $us_driver_ok = 1;
    }
    
    # Check for CirriusImpact (legacy/international)
    my $intl_driver_ok = 0;
    eval { require SMS::Send::CirriusImpact; };
    if (!$@) {
        my $version = $SMS::Send::CirriusImpact::VERSION || 'unknown';
        my $location = $INC{"SMS/Send/CirriusImpact.pm"} || 'unknown';
        print_success "SMS::Send::CirriusImpact driver is installed (legacy)";
        print_info "Version: $version";
        print_info "Location: $location";
        $intl_driver_ok = 1;
    }
    
    # At least one driver should be installed
    if (!$us_driver_ok && !$intl_driver_ok) {
        print_error "No CirriusImpact driver is installed";
        print_info "Run: sudo perl install_sms_driver.pl";
        $errors++;
        return 0;
    }
    
    if (!$us_driver_ok) {
        print_warning "US::CirriusImpact driver not found (recommended for regional phone numbers)";
        print_info "Run: sudo perl install_sms_driver.pl";
        $warnings++;
    }
    
    return 1;
}

# Test driver functionality
sub test_driver {
    print_info "Testing driver functionality...";
    
    eval {
        require SMS::Send;
        my $sender = SMS::Send->new('CirriusImpact');
        unless ($sender) {
            die "Failed to create SMS::Send object";
        }
        
        # Test send_sms method
        my $result = $sender->send_sms(
            to => '+1 555 1234',
            text => 'Test message'
        );
        
        unless ($result) {
            die "send_sms returned false";
        }
    };
    
    if ($@) {
        print_error "Driver test failed: $@";
        $errors++;
        return 0;
    }
    
    print_success "Driver test passed";
    return 1;
}

# Check required Perl modules
sub check_perl_modules {
    print_info "Checking required Perl modules...";
    
    my @required_modules = (
        'SMS::Send',
        'SMS::Send::Driver',
        'Net::SFTP::Foreign',
        'YAML::XS',
        'Template',
        'Mojo::JSON',
        'File::Slurp',
        'Try::Tiny',
        'Log::Log4perl',
    );
    
    my $all_ok = 1;
    foreach my $module (@required_modules) {
        eval "require $module";
        if ($@) {
            print_error "Missing: $module";
            $all_ok = 0;
            $errors++;
        } else {
            print_success "Found: $module";
        }
    }
    
    return $all_ok;
}

# Check Koha environment
sub check_koha {
    print_info "Checking Koha environment...";
    
    # Try to load C4::Context
    eval { require C4::Context; };
    if ($@) {
        print_warning "C4::Context not available (not running in Koha environment)";
        print_info "This is normal if testing outside of Koha shell";
        $warnings++;
        return 0;
    }
    
    print_success "Koha environment detected";
    
    # Check SMSSendDriver preference
    eval {
        my $driver = C4::Context->preference('SMSSendDriver');
        if ($driver) {
            if ($driver eq 'US::CirriusImpact') {
                print_success "SMSSendDriver is set to 'US::CirriusImpact' (recommended)";
            } elsif ($driver eq 'CirriusImpact') {
                print_success "SMSSendDriver is set to 'CirriusImpact' (works, but US::CirriusImpact recommended)";
                print_info "For regional phone numbers, use 'US::CirriusImpact'";
            } else {
                print_warning "SMSSendDriver is set to '$driver' (should be 'US::CirriusImpact' or 'CirriusImpact')";
                $warnings++;
            }
        } else {
            print_warning "SMSSendDriver preference is not set";
            print_info "Set to 'US::CirriusImpact' for regional numbers or 'CirriusImpact' for international only";
            $warnings++;
        }
    };
    
    return 1;
}

# Check plugin files
sub check_plugin_files {
    print_info "Checking plugin files...";
    
    # Get current script directory
    my $script_path = abs_path(__FILE__);
    my $script_dir = dirname($script_path);

    # Walk up from the script dir to find the directory holding the main
    # plugin module (layout may nest resources one or two levels deep).
    my $plugin_dir = dirname($script_dir);
    my $probe = $script_dir;
    for ( 1 .. 5 ) {
        $probe = dirname($probe);
        if ( -f File::Spec->catfile( $probe, 'CirriusImpact.pm' ) ) {
            $plugin_dir = $probe;
            last;
        }
    }
    
    # Files to check with their locations
    my @required_files = (
        { file => 'CirriusImpact.pm', display => 'CirriusImpact.pm', dir => $plugin_dir },
        { file => 'INSTALL.md', display => 'INSTALL.md', dir => $script_dir },
        { file => 'README.md', display => 'README.md', dir => $script_dir },
        { file => 'QUICKSTART.md', display => 'QUICKSTART.md', dir => $script_dir },
        { file => 'install_sms_driver.pl', display => 'install_sms_driver.pl', dir => $script_dir },
        { file => 'verify_installation.pl', display => 'verify_installation.pl', dir => $script_dir },
        { file => 'sms_driver/SMS/Send/CirriusImpact.pm', display => 'sms_driver/SMS/Send/CirriusImpact.pm', dir => $script_dir },
        { file => 'sms_driver/SMS/Send/US/CirriusImpact.pm', display => 'sms_driver/SMS/Send/US/CirriusImpact.pm', dir => $script_dir },
    );
    
    my $all_ok = 1;
    foreach my $item (@required_files) {
        my $path = File::Spec->catfile($item->{dir}, $item->{file});
        
        if (-f $path) {
            print_success "Found: $item->{display}";
        } else {
            print_error "Missing: $item->{display}";
            $all_ok = 0;
            $errors++;
        }
    }
    
    return $all_ok;
}

# Check archive directory
sub check_archive_directory {
    print_info "Checking archive directory...";
    
    # Try to determine instance name
    my $instance;
    eval {
        require C4::Context;
        $instance = C4::Context->config('database');
        $instance =~ s/koha_//;
    };
    
    if ($instance) {
        my $archive_dir = "/var/lib/koha/$instance/CirriusImpact_archive";
        if (-d $archive_dir) {
            print_success "Archive directory exists: $archive_dir";
            
            # Check if writable
            if (-w $archive_dir) {
                print_success "Archive directory is writable";
            } else {
                print_warning "Archive directory is not writable";
                $warnings++;
            }
        } else {
            print_warning "Archive directory does not exist: $archive_dir";
            print_info "It will be created automatically when needed";
            $warnings++;
        }
    } else {
        print_info "Cannot determine instance name (not in Koha environment)";
    }
}

# Print summary
sub print_summary {
    print "\n";
    print "=" x 70, "\n";
    
    if ($errors == 0 && $warnings == 0) {
        print "${GREEN}All checks passed!${RESET}\n";
        print "=" x 70, "\n";
        print "\n";
        print "The CirriusImpact plugin is properly installed and ready to use.\n";
        print "\n";
        print "Next steps:\n";
        print "1. Configure the plugin in Koha (Tools > Plugins > CirriusImpact > Configure)\n";
        print "2. Set up your notice templates with 'CirriusImpact: yes'\n";
        print "3. Test with: sudo koha-shell INSTANCE -c '/usr/share/koha/bin/cronjobs/process_message_queue.pl'\n";
    } elsif ($errors == 0) {
        print "${YELLOW}Checks passed with $warnings warning(s)${RESET}\n";
        print "=" x 70, "\n";
        print "\n";
        print "The installation appears functional but some warnings were noted above.\n";
    } else {
        print "${RED}Checks failed with $errors error(s) and $warnings warning(s)${RESET}\n";
        print "=" x 70, "\n";
        print "\n";
        print "Please address the errors above before using the plugin.\n";
    }
    
    print "\n";
}

# Main execution
sub main {
    print_header("CirriusImpact Plugin Installation Verification");
    
    # Run checks
    print_header("1. SMS::Send Framework");
    check_sms_send();
    
    print_header("2. CirriusImpact Driver");
    check_driver_installed() && test_driver();
    
    print_header("3. Required Perl Modules");
    check_perl_modules();
    
    print_header("4. Plugin Files");
    check_plugin_files();
    
    print_header("5. Koha Environment");
    check_koha();
    
    print_header("6. Archive Directory");
    check_archive_directory();
    
    # Summary
    print_summary();
    
    exit($errors > 0 ? 1 : 0);
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

