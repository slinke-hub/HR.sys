const pdf2img = require('pdf-img-convert');
const fs = require('fs');

async function convert() {
    try {
        console.log("Converting PDF...");
        const outputImages = await pdf2img.convert('C:\\Users\\ASUS\\.gemini\\antigravity-ide\\brain\\d8304e86-72a0-4d19-8dcb-5709622b5d86\\media__1786538464398.pdf');
        
        fs.writeFileSync('e:\\HR.sys\\images\\letterhead.png', outputImages[0]);
        console.log("Successfully created letterhead.png!");
    } catch (e) {
        console.error("Error converting PDF:", e);
    }
}

convert();
