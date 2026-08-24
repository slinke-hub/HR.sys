const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');

// The duplicate taskSidePanel is around line 1136.
// Let's find the second occurrence of `id="taskSidePanel"`
let firstIndex = html.indexOf('id="taskSidePanel"');
let secondIndex = html.indexOf('id="taskSidePanel"', firstIndex + 1);

if (secondIndex !== -1) {
    // Find the start of the overlay div before the second panel
    let overlayStr = '<div class="side-panel-overlay" id="taskSidePanelOverlay"';
    let overlayIndex = html.lastIndexOf(overlayStr, secondIndex);
    
    // Find the end of the side-panel div. It ends before <div class="modal" id="taskV2Modal">
    let nextElementIndex = html.indexOf('<div class="modal" id="taskV2Modal">', secondIndex);
    
    if (overlayIndex !== -1 && nextElementIndex !== -1) {
        // Remove the duplicate block
        let newHtml = html.slice(0, overlayIndex) + html.slice(nextElementIndex);
        fs.writeFileSync('index.html', newHtml);
        console.log('Removed duplicate taskSidePanel');
    } else {
        console.log('Could not find boundaries for removal');
    }
} else {
    console.log('No duplicate found');
}
