const puppeteer = require('puppeteer');

(async () => {
    let browser;
    try {
        console.log("Launching Puppeteer...");
        browser = await puppeteer.launch({
            headless: 'new',
            args: ['--no-sandbox', '--disable-setuid-sandbox']
        });
        const page = await browser.newPage();
        
        // Listen to console errors
        const errors = [];
        page.on('console', msg => {
            if (msg.type() === 'error') {
                errors.push(`Console Error: ${msg.text()}`);
                console.log(`[BROWSER ERROR] ${msg.text()}`);
            }
        });
        page.on('pageerror', err => {
            errors.push(`Page Error: ${err.toString()}`);
            console.log(`[PAGE ERROR] ${err.toString()}`);
        });

        console.log("Navigating to http://localhost:3000 ...");
        await page.goto('http://localhost:3000', { waitUntil: 'networkidle0' });
        
        console.log("Page loaded. Testing Login...");
        
        // Try filling login if it exists
        const loginForm = await page.$('#loginForm');
        if (loginForm) {
            console.log("Login form detected. Filling it...");
            await page.type('#email', 'admin@hrsystem.com');
            await page.type('#password', 'admin123'); // Adjust if needed
            await page.click('button[type="submit"]');
            
            console.log("Waiting for network idle after login...");
            await page.waitForNavigation({ waitUntil: 'networkidle0' }).catch(() => {});
        } else {
            console.log("No login form detected. Maybe already logged in?");
        }

        console.log("Clicking through navigation links...");
        const navLinks = await page.$$('.nav-item');
        for (let i = 0; i < navLinks.length; i++) {
            const linkText = await page.evaluate(el => el.textContent.trim(), navLinks[i]);
            if (linkText) {
                console.log(`Navigating to: ${linkText}`);
                await navLinks[i].click();
                await new Promise(r => setTimeout(r, 1000)); // wait for transitions/fetch
            }
        }
        
        console.log("\n--- TEST REPORT ---");
        if (errors.length > 0) {
            console.log(`Found ${errors.length} errors:`);
            errors.forEach(e => console.log(e));
        } else {
            console.log("No Javascript errors found during navigation!");
        }

    } catch (err) {
        console.error("Script Error:", err);
    } finally {
        if (browser) {
            await browser.close();
        }
        console.log("Done.");
    }
})();
