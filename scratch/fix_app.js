const fs = require('fs');
const content = fs.readFileSync('js/app.js', 'utf8');
const lines = content.split('\n');

let extractedBlock = [];
let newLines = [];
let inExtractedBlock = false;

for (let i = 0; i < lines.length; i++) {
    // Note: lines are 0-indexed, so line 103 is i=102
    
    if (i === 101) { // line 102: "        if (typeof lucide !== 'undefined') "
        newLines.push("        if (typeof lucide !== 'undefined') lucide.createIcons();");
        inExtractedBlock = true;
        continue;
    }
    
    if (inExtractedBlock) {
        if (i === 294) { // line 295: "lucide.createIcons();"
            inExtractedBlock = false;
            // Skip adding this line to either place because we already added it above
            continue;
        }
        extractedBlock.push(lines[i]);
    } else {
        newLines.push(lines[i]);
        
        // At the end of showInstallBanner() which is now at line 327 (i = 326) in original file,
        // but its index in newLines will be different because we removed the block.
        // Let's identify the end of showInstallBanner by looking for the specific pattern.
        // It's the `    }` and `}` before `window.addEventListener('beforeinstallprompt'`.
    }
}

// Now find the place to insert the extracted block in newLines
const insertIndex = newLines.findIndex(line => line.includes("window.addEventListener('beforeinstallprompt'"));

if (insertIndex > -1) {
    newLines.splice(insertIndex, 0, ...extractedBlock);
    fs.writeFileSync('js/app.js', newLines.join('\n'));
    console.log("Fix applied successfully!");
} else {
    console.error("Could not find insertion point.");
}
