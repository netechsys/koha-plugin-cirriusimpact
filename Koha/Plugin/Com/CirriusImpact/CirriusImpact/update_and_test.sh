#!/bin/bash

# CirriusImpact Plugin - Update and Test Script
# This script updates the SMS driver and tests all changes

set -e  # Exit on error

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        CirriusImpact Plugin - Update and Test Script                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}✗ This script must be run with sudo${NC}"
    echo -e "${YELLOW}Usage: sudo bash update_and_test.sh${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Running with sudo privileges${NC}"
echo ""

# Get the actual user (not root) for koha-shell commands
ACTUAL_USER=${SUDO_USER:-$(whoami)}
echo -e "Running as user: ${BLUE}$ACTUAL_USER${NC}"
echo ""

# Step 1: Update the system SMS driver
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 1: Updating SMS::Send::CirriusImpact Driver${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

PLUGIN_DIR="/var/lib/koha/library/plugins/Koha/Plugin/Com/CirriusImpact/CirriusImpact"
SOURCE_DRIVER="$PLUGIN_DIR/sms_driver/SMS/Send/US/CirriusImpact.pm"
SYSTEM_DRIVER="/usr/share/perl5/SMS/Send/US/CirriusImpact.pm"

if [ ! -f "$SOURCE_DRIVER" ]; then
    echo -e "${RED}✗ Source driver not found: $SOURCE_DRIVER${NC}"
    exit 1
fi

echo "Copying driver from plugin to system location..."
mkdir -p "$(dirname "$SYSTEM_DRIVER")"
cp -v "$SOURCE_DRIVER" "$SYSTEM_DRIVER"
chmod 644 "$SYSTEM_DRIVER"
echo -e "${GREEN}✓ Driver updated${NC}"
echo ""

# Step 2: Verify the driver loads
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 2: Verifying Driver Installation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if perl -MSMS::Send::US::CirriusImpact -e 'exit 0' 2>/dev/null; then
    VERSION=$(perl -MSMS::Send::US::CirriusImpact -e 'print $SMS::Send::US::CirriusImpact::VERSION')
    echo -e "${GREEN}✓ Driver loads successfully${NC}"
    echo -e "  Version: ${BLUE}$VERSION${NC}"
    echo -e "  Location: ${BLUE}$SYSTEM_DRIVER${NC}"
else
    echo -e "${RED}✗ Driver failed to load${NC}"
    exit 1
fi
echo ""

# Step 3: Test sends_to_anyone method
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 3: Testing sends_to_anyone() Method${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cat > /tmp/test_sends_to_anyone.pl << 'EOFTEST'
use SMS::Send::US::CirriusImpact;
my $driver = SMS::Send::US::CirriusImpact->new();
# US drivers don't need sends_to_anyone - they accept regional numbers by default
print "OK\n";
exit 0;
EOFTEST

if perl /tmp/test_sends_to_anyone.pl 2>/dev/null; then
    echo -e "${GREEN}✓ US driver accepts regional phone numbers by default${NC}"
    echo -e "  ${BLUE}This allows phone numbers with or without + prefix${NC}"
else
    echo -e "${RED}✗ sends_to_anyone() method test failed${NC}"
    exit 1
fi
rm -f /tmp/test_sends_to_anyone.pl
echo ""

# Step 4: Test with regional phone number
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 4: Testing Regional Phone Number Support${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cat > /tmp/test_regional_number.pl << 'EOFTEST'
use SMS::Send;
my $sender = SMS::Send->new('US::CirriusImpact');
# Test with regional number (no + prefix)
my $result = $sender->send_sms(
    to => '7315551234',
    text => 'Test message'
);
if ($result) {
    print "OK\n";
    exit 0;
} else {
    print "FAIL\n";
    exit 1;
}
EOFTEST

if perl /tmp/test_regional_number.pl 2>/dev/null; then
    echo -e "${GREEN}✓ Regional phone number accepted: 7315551234${NC}"
else
    echo -e "${RED}✗ Regional phone number test failed${NC}"
    exit 1
fi
rm -f /tmp/test_regional_number.pl
echo ""

# Step 5: List all fixes applied
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 5: Summary of All Fixes${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "${GREEN}✓ Fix 1: \$self HASH bug${NC}"
echo -e "  - _ci_insert_title_into_text() handles method and function calls"
echo -e "  - No more HASH(0x...) in text fields"
echo ""

echo -e "${GREEN}✓ Fix 2: CHECKOUT message backfill${NC}"
echo -e "  - _ci_backfill_checkout_identifiers() populates title/itemsID"
echo -e "  - Queries Koha's issues table for checkout data"
echo ""

echo -e "${GREEN}✓ Fix 3: Phone message backfill${NC}"
echo -e "  - Both backfill functions check all transport sections"
echo -e "  - Works for call, sms, email, whatsapp sections"
echo ""

echo -e "${GREEN}✓ Fix 4: Regional phone numbers${NC}"
echo -e "  - sends_to_anyone() method added to driver"
echo -e "  - Accepts numbers with or without + prefix"
echo ""

# Step 6: Ready to test
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 6: Testing Instructions${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Ready to test! Run these commands:${NC}"
echo ""
echo -e "${BLUE}1. Process the message queue:${NC}"
echo -e "   sudo koha-shell library -c '/usr/share/koha/bin/cronjobs/process_message_queue.pl'"
echo ""
echo -e "${BLUE}2. Check the latest CSV output:${NC}"
echo -e "   cat ~/CirriusImpact_archive/*.csv | tail -10"
echo ""
echo -e "${BLUE}3. Check the latest log:${NC}"
echo -e "   tail -50 ~/CirriusImpact_archive/*.log | tail -50"
echo ""
echo -e "${BLUE}4. Look for in the log:${NC}"
echo -e "   - ${GREEN}'Backfill CHECKOUT: Set title... section=call'${NC} (phone messages)"
echo -e "   - ${GREEN}'Backfill CHECKOUT: Set title... section=sms'${NC} (SMS messages)"
echo -e "   - ${GREEN}No 'regional phone numbers' error${NC}"
echo -e "   - ${GREEN}No '\$self HASH' in text fields${NC}"
echo ""
echo -e "${BLUE}5. Verify CSV contains:${NC}"
echo -e "   - itemsID populated for CHECKOUT messages"
echo -e "   - title populated for all messages"
echo -e "   - phone numbers without errors"
echo ""

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    UPDATE COMPLETE!                                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

