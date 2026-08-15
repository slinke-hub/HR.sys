const fs = require('fs');
const content = fs.readFileSync('css/components.css');
// Convert to buffer to find the start of the garbled text
// The text starts after "    background: var(--color-surface);\r\n}\r\n\r\n" which is around line 914
const text = content.toString('utf8');
const goodPartIndex = text.indexOf('/* Task Forms styling */');
if (goodPartIndex !== -1) {
    const endOfGoodPart = text.indexOf('\n}', goodPartIndex) + 2; // End of .modal-content form .form-control:focus
    let cleanText = text.substring(0, endOfGoodPart);
    
    cleanText += `
/* Slide-out panel for modals (Teamwork style) */
.modal.slide-panel {
    justify-content: flex-end;
    align-items: stretch;
    padding: 0;
}
.modal.slide-panel .modal-content {
    margin: 0;
    width: 500px;
    max-width: 100vw;
    height: 100vh;
    border-radius: 0;
    border-left: 1px solid var(--color-border);
    animation: slideInRight 0.3s cubic-bezier(0.16, 1, 0.3, 1) forwards;
    display: flex;
    flex-direction: column;
    overflow-y: auto;
}
@keyframes slideInRight {
    from { transform: translateX(100%); }
    to { transform: translateX(0); }
}

.modal.active {
    display: flex;
}
`;
    fs.writeFileSync('css/components.css', cleanText, 'utf8');
    console.log('Fixed CSS file');
} else {
    console.log('Could not find marker in CSS file');
}
