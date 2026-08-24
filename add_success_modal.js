const fs = require('fs');

let html = fs.readFileSync('e:/HR.sys/index.html', 'utf8');
const successModalHtml = `
    <!-- Success Modal -->
    <div class="modal" id="successModal" style="z-index: 100000;">
        <div class="modal-content" style="max-width: 400px; text-align: center; background: rgba(30, 41, 59, 0.85); backdrop-filter: blur(16px); -webkit-backdrop-filter: blur(16px); border: 1px solid rgba(255, 255, 255, 0.1); box-shadow: 0 10px 40px rgba(0, 0, 0, 0.4); color: #ffffff;">
            <div style="margin-bottom: 1rem;">
                <i data-lucide="check-circle" style="width: 48px; height: 48px; color: var(--color-success);"></i>
            </div>
            <h2 id="successModalTitle" style="margin-bottom: 0.5rem;">Success</h2>
            <p id="successModalMessage" style="color: var(--color-text-secondary); margin-bottom: 1.5rem;">Action completed successfully.</p>
            <div style="display: flex; gap: 1rem; justify-content: center;">
                <button class="btn btn-primary" style="min-width: 120px;" onclick="document.getElementById('successModal').classList.remove('active', 'show')">OK</button>
            </div>
        </div>
    </div>
`;

if (!html.includes('id="successModal"')) {
    html = html.replace('<!-- Edit Task Modal -->', successModalHtml + '\n    <!-- Edit Task Modal -->');
    fs.writeFileSync('e:/HR.sys/index.html', html, 'utf8');
    console.log("Added successModal to index.html");
} else {
    console.log("successModal already exists");
}
