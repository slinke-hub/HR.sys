const fs = require('fs');
let css = fs.readFileSync('css/components.css', 'utf8');

// 1. .modal z-index
css = css.replace(
  /\.modal \{\s*display: none;\s*position: fixed;\s*top: 0;\s*left: 0;\s*width: 100%;\s*height: 100%;\s*background: rgba\(0, 0, 0, 0\.5\);\s*z-index: 30000;/,
  '.modal {\n  display: none;\n  position: fixed;\n  top: 0;\n  left: 0;\n  width: 100%;\n  height: 100%;\n  background: rgba(0, 0, 0, 0.5);\n  z-index: 100050;'
);

// 2. .teamwork-task-detail .side-panel-header
css = css.replace(
  /\.teamwork-task-detail \.side-panel-header \{\s*min-height: 66px;\s*padding: \.8rem 1\.5rem;\s*border-bottom: 1px solid var\(--color-border\);\s*\}/,
  '.teamwork-task-detail .side-panel-header {\n  min-height: 66px;\n  padding: .8rem 1.5rem;\n  border-bottom: 1px solid var(--color-border);\n  display: flex;\n  gap: 1rem;\n}'
);

css = css.replace(
  /\.teamwork-task-detail \.side-panel-header h2 \{\s*font-size: 1\.35rem !important;\s*font-weight: 700;\s*\}/,
  '.teamwork-task-detail .side-panel-header h2 {\n  font-size: 1.35rem !important;\n  font-weight: 700;\n  flex: 1;\n  word-break: break-word;\n}'
);

css = css.replace(
  /\.task-detail-actions \{\s*display: flex;\s*align-items: center;\s*gap: \.75rem;\s*\}/,
  '.task-detail-actions {\n  display: flex;\n  align-items: center;\n  gap: .75rem;\n  flex-shrink: 0;\n}'
);

// 3. .task-detail-description
css = css.replace(
  /\.task-detail-description \{\s*min-height: 82px;\s*padding: 1\.25rem 0;\s*color: var\(--color-text\);\s*\}/,
  '.task-detail-description {\n  min-height: 82px;\n  padding: 1.25rem 0;\n  color: var(--color-text);\n  word-break: break-word;\n}'
);

// 4. table-responsive
css = css.replace(
  /\.table-responsive \{\s*max-width: 100%;\s*overscroll-behavior-inline: contain;\s*\}/,
  '.table-responsive {\n  max-width: 100%;\n  overscroll-behavior-inline: contain;\n  overflow-x: auto;\n  -webkit-overflow-scrolling: touch;\n}'
);

// 5. label break-word and glassy modal fixes (if not already there)
if (!css.includes('/* Fix text and icon buttons in hardcoded dark glassy modals for light mode */')) {
  css += `
/* Fix text and icon buttons in hardcoded dark glassy modals for light mode */
.modal-content[style*="rgba(30, 41, 59"] h1,
.modal-content[style*="rgba(30, 41, 59"] h2,
.modal-content[style*="rgba(30, 41, 59"] h3,
.modal-content[style*="rgba(30, 41, 59"] h4,
.modal-content[style*="rgba(30, 41, 59"] h5,
.modal-content[style*="rgba(30, 41, 59"] h6,
.modal-content[style*="rgba(30, 41, 59"] .form-label,
.modal-content[style*="rgba(30, 41, 59"] label,
.modal-content[style*="rgba(30, 41, 59"] p,
.modal-content[style*="rgba(30, 41, 59"] span:not(.lucide) {
    color: #ffffff !important;
}

.modal-content[style*="rgba(30, 41, 59"] .btn-icon {
    background: transparent !important;
    border: none !important;
    box-shadow: none !important;
    color: #ffffff !important;
}

.modal-content[style*="rgba(30, 41, 59"] .btn-icon:hover {
    background: rgba(255, 255, 255, 0.1) !important;
}
`;
}

css = css.replace(
  /h1, h2, h3, h4, h5, h6, p, span, \.nav-item span, td, th, label \{/,
  'h1, h2, h3, h4, h5, h6, p, span, .nav-item span, label {'
);

css = css.replace(
  /\.badge, \.status-badge, \.btn, button \{/,
  '.badge, .status-badge, .btn, button, .user-name, .user-role {'
);

css = css.replace(
  /\.kanban-board, \.task-board, \.task-v2-workspace, \.kanban-columns \{/,
  '.kanban-board, .task-board, .kanban-columns {'
);

fs.writeFileSync('css/components.css', css);
console.log('Patched components.css successfully');
