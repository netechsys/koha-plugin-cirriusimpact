# CirriusImpact Plugin v1.1.8 - Release Notes

**Release Date:** October 12, 2025

## What's New in v1.1.8

This release fixes critical bugs related to multi-document YAML processing and ensures perfect alignment of CSV columns for CHECKOUT messages.

### Critical Bug Fixes

#### 1. Multi-Document YAML Support
- **FIXED**: Koha concatenates multiple notices with `------` (6 dashes), which is invalid YAML
- **Solution**: Plugin now automatically converts `------` to `---` before parsing
- **Impact**: Phone and SMS CHECKOUT messages now parse correctly

#### 2. Phone CHECKOUT Message Population
- **FIXED**: Phone CHECKOUT messages had empty `itemsID`, `title`, and `date` fields
- **Solution**: Backfill logic now runs correctly for all transport types
- **Impact**: All CSV columns now populated with correct data

#### 3. CSV Column Alignment
- **FIXED**: `title` column and `messageText` column showed different titles
- **Solution**: Extracts title from rendered script and matches to correct checkout in database
- **Impact**: Perfect consistency across `itemsID`, `title`, and `messageText` columns

#### 4. YAML Document Tracking
- **Enhancement**: Each YAML document in a multi-document message now tracked separately
- **Solution**: Added `yaml_doc_index` counter to distribute items correctly
- **Impact**: Multiple checkouts correctly mapped to their respective CSV rows

### CSV Export Improvements

**Before v1.1.8:**
```csv
itemsID=721, title="Learning SQL", messageText="...The poems..."  ❌ Mismatch
```

**After v1.1.8:**
```csv
itemsID=413, title="The poems", messageText="...The poems..."     ✅ Perfect match
itemsID=877, title="The bible", messageText="...The bible..."     ✅ Perfect match
itemsID=721, title="Learning SQL", messageText="...Learning SQL..." ✅ Perfect match
```

### Testing Results

All tests passed successfully:

- ✅ **HOLD messages**: 4 holds processed, all columns correct
- ✅ **CHECKOUT messages**: 3 checkouts processed, all columns correct
- ✅ **CSV alignment**: itemsID, title, messageText all match perfectly
- ✅ **Multi-document YAML**: Properly parsed and processed
- ✅ **Phone scripts**: Correctly populated in messageText column

### Technical Details

**YAML Parsing Enhancement:**
```perl
# Fix invalid YAML separators: replace ------ with ---
# Koha sometimes concatenates multiple notices with ------
$content =~ s/------/---/g;
```

**Title Extraction Logic:**
```perl
# Extract title from: "You checked out [TITLE] due..."
if ($section->{script} =~ /You checked out\s+(.+?)\s+due/i) {
    $title_from_message = $1;
    # Match to correct checkout in database
}
```

**YAML Document Tracking:**
```perl
my $yaml_doc_index = 0;
for my $yaml (@yamls) {
    # Track which YAML doc this is (0, 1, 2...)
    $data->{message_type}->{yaml_doc_index} = $yaml_doc_index++;
    # Use index to select correct item from database
}
```

### Upgrade Notes

**From v1.1.7 to v1.1.8:**
- No configuration changes required
- No template changes required
- Existing templates will work immediately
- CSV export format unchanged (columns in same order)

**Compatibility:**
- Koha 24.05 or later
- All existing SMS::Send drivers supported
- All existing notice templates compatible

### Files Changed

**Core Plugin:**
- `CirriusImpact.pm` - YAML parsing, title extraction, document tracking

**Documentation:**
- `CHANGELOG.md` - Added v1.1.8 entry
- `README.md` - Updated version to 1.1.8
- `RELEASE_NOTES_v1.1.8.md` - This file

### Installation

1. Upload `CirriusImpact-v1.1.8.kpz` via Koha's plugin interface
2. Run `sudo perl install_sms_driver.pl` (if not already installed)
3. Run `perl verify_installation.pl` to confirm

**No additional configuration needed!** Your existing templates will work immediately.

### Known Issues

None! All critical bugs from v1.1.7 are fixed.

### Support

For questions or issues, contact Terry Rossio or ByWater Solutions.

---

**Previous Version:** [v1.1.7 Release Notes](RELEASE_NOTES_v1.1.7.md)  
**Changelog:** [CHANGELOG.md](CHANGELOG.md)  
**Documentation:** [README.md](README.md)



