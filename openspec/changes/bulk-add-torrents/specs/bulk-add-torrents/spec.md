## ADDED Requirements

### Requirement: Multiple magnet links can be entered in a single session
The system SHALL allow a user to enter one or more magnet links (or torrent URLs) before submitting, using a dynamic list of text fields within the "Magnet / URL" tab.

#### Scenario: Initial state shows one empty field
- **WHEN** the user opens the "Add Torrent" modal on the "Magnet / URL" tab
- **THEN** exactly one empty text field is displayed and a "+" button is shown to its right

#### Scenario: Adding a new link field
- **WHEN** the user clicks the "+" button next to any existing field
- **THEN** a new empty text field is appended below the clicked field, paired with both a "+" button and a "−" button

#### Scenario: First field cannot be removed
- **WHEN** the modal contains only one URL field
- **THEN** no "−" button is shown for that field

#### Scenario: Removing an intermediate field
- **WHEN** the user has N > 1 fields and clicks the "−" button associated with field at position i (where 0 < i < N)
- **THEN** only that field is removed; all other fields and their values are preserved

#### Scenario: Maximum URL fields enforced
- **WHEN** the user attempts to add a URL field and the modal already contains 20 fields
- **THEN** the "+" button is disabled and no new field is created

### Requirement: Multiple torrent files can be uploaded in a single session
The system SHALL allow a user to select or drop up to 20 `.torrent` files simultaneously on the "File upload" tab.

#### Scenario: Multi-file drag and drop
- **WHEN** the user drags and drops multiple `.torrent` files onto the drop zone
- **THEN** all dropped files are listed individually in the upload queue

#### Scenario: Multi-file selection via file picker
- **WHEN** the user opens the file picker and selects multiple `.torrent` files
- **THEN** all selected files appear in the upload queue

#### Scenario: Maximum file entries enforced
- **WHEN** the user attempts to add files and the combined count would exceed 20
- **THEN** entries beyond the limit are rejected with an error message per excess file

### Requirement: A shared label and download directory apply to all items in a batch
The system SHALL apply a single selected label and a single selected download directory to every torrent submitted in a batch operation.

#### Scenario: Label applied to all batch items
- **WHEN** the user selects a label and submits a batch of N torrents
- **THEN** every torrent added in that batch is assigned the selected label

#### Scenario: Download directory applied to all batch items
- **WHEN** the user selects a download directory and submits a batch of N torrents
- **THEN** every torrent added in that batch uses that directory as its download location

### Requirement: Batch submission reports per-item failures
The system SHALL continue attempting to add remaining items after an individual item fails, and SHALL report all failures after the batch completes.

#### Scenario: All items succeed
- **WHEN** the user submits a batch and all items are added successfully
- **THEN** the modal closes and a success notification is shown

#### Scenario: Some items fail
- **WHEN** the user submits a batch and one or more items fail
- **THEN** the modal remains open, a structured error list identifies each failed item and its reason, and successfully added items are removed from the form

#### Scenario: All items fail
- **WHEN** the user submits a batch and every item fails
- **THEN** the modal remains open and all failures are listed; no success notification is shown

### Requirement: Switching tabs resets current batch inputs
The system SHALL discard all current URL fields or queued files when the user switches between the "Magnet / URL" and "File upload" tabs.

#### Scenario: Switching from URL tab to file tab
- **WHEN** the user has entered one or more URLs and then clicks the "File upload" tab
- **THEN** all URL fields are reset to a single empty field

#### Scenario: Switching from file tab to URL tab
- **WHEN** the user has queued one or more files and then clicks the "Magnet / URL" tab
- **THEN** all pending file uploads are cancelled
