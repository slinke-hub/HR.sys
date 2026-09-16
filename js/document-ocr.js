/* Local employee-document metadata recognition (PDF text + on-device OCR). */
(() => {
    'use strict';

    const globalScope = window;
    const MAX_PDF_PAGES = 3;
    let pdfJsPromise = null;

    const assetUrl = path => new URL(path, document.baseURI).href;

    function normalizeDigits(value) {
        return String(value || '')
            .replace(/[٠-٩]/g, digit => String('٠١٢٣٤٥٦٧٨٩'.indexOf(digit)))
            .replace(/[۰-۹]/g, digit => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(digit)));
    }

    function validIsoDate(year, month, day) {
        const numericYear = Number(year);
        const numericMonth = Number(month);
        const numericDay = Number(day);
        if (numericYear < 1900 || numericYear > 2200) return '';
        const utc = Date.UTC(numericYear, numericMonth - 1, numericDay);
        const parsed = new Date(utc);
        if (parsed.getUTCFullYear() !== numericYear || parsed.getUTCMonth() !== numericMonth - 1 || parsed.getUTCDate() !== numericDay) return '';
        return `${String(numericYear).padStart(4, '0')}-${String(numericMonth).padStart(2, '0')}-${String(numericDay).padStart(2, '0')}`;
    }

    function parseDateCandidate(value) {
        const normalized = normalizeDigits(value).replace(/[.]/g, '/');
        let match = normalized.match(/\b(20\d{2}|19\d{2}|21\d{2}|22\d{2})\s*[\/-]\s*(\d{1,2})\s*[\/-]\s*(\d{1,2})\b/);
        if (match) return validIsoDate(match[1], match[2], match[3]);

        match = normalized.match(/\b(\d{1,2})\s*[\/-]\s*(\d{1,2})\s*[\/-]\s*(20\d{2}|19\d{2}|21\d{2}|22\d{2})\b/);
        if (match) return validIsoDate(match[3], match[2], match[1]);

        const monthNames = {
            january: 1, jan: 1, february: 2, feb: 2, march: 3, mar: 3, april: 4, apr: 4,
            may: 5, june: 6, jun: 6, july: 7, jul: 7, august: 8, aug: 8,
            september: 9, sep: 9, october: 10, oct: 10, november: 11, nov: 11, december: 12, dec: 12
        };
        match = normalized.match(/\b(\d{1,2})\s+([a-z]{3,9})\s*,?\s*(20\d{2}|19\d{2}|21\d{2}|22\d{2})\b/i);
        if (match && monthNames[match[2].toLowerCase()]) return validIsoDate(match[3], monthNames[match[2].toLowerCase()], match[1]);
        match = normalized.match(/\b([a-z]{3,9})\s+(\d{1,2}),?\s*(20\d{2}|19\d{2}|21\d{2}|22\d{2})\b/i);
        if (match && monthNames[match[1].toLowerCase()]) return validIsoDate(match[3], monthNames[match[1].toLowerCase()], match[2]);
        return '';
    }

    function cleanOwnerName(value) {
        const candidate = String(value || '')
            .replace(/^[\s:|\-–—]+|[\s:|\-–—]+$/g, '')
            .replace(/\s{2,}/g, ' ')
            .trim();
        if (candidate.length < 3 || candidate.length > 120) return '';
        if ((candidate.match(/[A-Za-z\u0600-\u06FF]/g) || []).length < 3) return '';
        if (/^(name|owner|holder|ال|الاسم|اسم المالك|اسم حامل الوثيقة)$/i.test(candidate)) return '';
        return candidate;
    }

    function findOwnerName(text) {
        const lines = String(text || '').split(/\r?\n/).map(line => line.replace(/\s{2,}/g, ' ').trim()).filter(Boolean);
        const labelGroups = [
            [
                /^(?:owner(?:'s)?\s+name|document\s+owner|holder(?:'s)?\s+name)\s*[:|\-–—]?\s*(.*)$/i,
                /^(?:اسم\s+المالك|اسم\s+صاحب\s+الوثيقة|اسم\s+حامل\s+الوثيقة)\s*[:|\-–—]?\s*(.*)$/i
            ],
            [
                /^(?:full\s+name|name)\s*[:|\-–—]?\s*(.*)$/i,
                /^(?:الاسم\s+الكامل|الاسم)\s*[:|\-–—]?\s*(.*)$/i
            ]
        ];
        for (const labels of labelGroups) {
            for (let index = 0; index < lines.length; index += 1) {
                for (const label of labels) {
                    const match = lines[index].match(label);
                    if (!match) continue;
                    const sameLine = cleanOwnerName(match[1]);
                    if (sameLine) return sameLine;
                    const nextLine = cleanOwnerName(lines[index + 1]);
                    if (nextLine) return nextLine;
                }
            }
        }
        return '';
    }

    function findExpirationDate(text) {
        const normalized = normalizeDigits(text);
        const labelledCandidates = [
            /(?:expiry\s+date|expiration\s+date|date\s+of\s+expiry|expires?(?:\s+on)?|valid\s+(?:until|through|thru))\s*[:|\-–—]?\s*([^\n]{0,60})/gi,
            /(?:تاريخ\s*(?:الانتهاء|الإنتهاء)|تاريخ\s*نهاية\s*الصلاحية|ينتهي\s*(?:في)?|صالح\s*حتى)\s*[:|\-–—]?\s*([^\n]{0,60})/g
        ];
        for (const pattern of labelledCandidates) {
            let match;
            while ((match = pattern.exec(normalized))) {
                const parsed = parseDateCandidate(match[1]);
                if (parsed) return parsed;
            }
        }
        
        // Fallback: Find any future date in the entire text
        const unlabelledDates = [];
        const normalizedForFallback = normalized.replace(/[.]/g, '/');
        
        const r1 = /\b(20\d{2}|19\d{2}|21\d{2}|22\d{2})\s*[\/-]\s*(\d{1,2})\s*[\/-]\s*(\d{1,2})\b/g;
        let m1;
        while ((m1 = r1.exec(normalizedForFallback))) unlabelledDates.push(validIsoDate(m1[1], m1[2], m1[3]));
        
        const r2 = /\b(\d{1,2})\s*[\/-]\s*(\d{1,2})\s*[\/-]\s*(20\d{2}|19\d{2}|21\d{2}|22\d{2})\b/g;
        let m2;
        while ((m2 = r2.exec(normalizedForFallback))) unlabelledDates.push(validIsoDate(m2[3], m2[2], m2[1]));

        const monthNames = {
            january: 1, jan: 1, february: 2, feb: 2, march: 3, mar: 3, april: 4, apr: 4,
            may: 5, june: 6, jun: 6, july: 7, jul: 7, august: 8, aug: 8,
            september: 9, sep: 9, october: 10, oct: 10, november: 11, nov: 11, december: 12, dec: 12
        };
        const r3 = /\b(\d{1,2})\s+([a-z]{3,9})\s*,?\s*(20\d{2}|19\d{2}|21\d{2}|22\d{2})\b/gi;
        let m3;
        while ((m3 = r3.exec(normalizedForFallback))) {
            if (monthNames[m3[2].toLowerCase()]) unlabelledDates.push(validIsoDate(m3[3], monthNames[m3[2].toLowerCase()], m3[1]));
        }

        const r4 = /\b([a-z]{3,9})\s+(\d{1,2}),?\s*(20\d{2}|19\d{2}|21\d{2}|22\d{2})\b/gi;
        let m4;
        while ((m4 = r4.exec(normalizedForFallback))) {
            if (monthNames[m4[1].toLowerCase()]) unlabelledDates.push(validIsoDate(m4[3], monthNames[m4[1].toLowerCase()], m4[2]));
        }
        
        const todayStr = new Date().toISOString().split('T')[0];
        const validFutureDates = unlabelledDates.filter(d => d && d >= todayStr);
        if (validFutureDates.length > 0) {
            // Return the furthest future date as it's most likely the expiry date
            return validFutureDates.sort((a, b) => a.localeCompare(b)).pop();
        }

        return '';
    }

    function parseMetadata(text) {
        return {
            ownerName: findOwnerName(text),
            expirationDate: findExpirationDate(text)
        };
    }

    function cleanBusinessCardValue(value) {
        return String(value || '')
            .replace(/^[\s:|\-–—]+|[\s:|\-–—]+$/g, '')
            .replace(/\s{2,}/g, ' ')
            .trim();
    }

    function findLabelledBusinessCardValue(lines, patterns) {
        for (let index = 0; index < lines.length; index += 1) {
            for (const pattern of patterns) {
                const match = lines[index].match(pattern);
                if (!match) continue;
                const sameLine = cleanBusinessCardValue(match[1]);
                if (sameLine) return sameLine;
                const nextLine = cleanBusinessCardValue(lines[index + 1]);
                if (nextLine) return nextLine;
            }
        }
        return '';
    }

    function parseBusinessCard(text, visualLines = []) {
        const normalizedText = normalizeDigits(text);
        const lines = normalizedText
            .split(/\r?\n/)
            .map(line => cleanBusinessCardValue(line))
            .filter(Boolean);
        const normalizedContactText = normalizedText
            .replace(/[\u200E\u200F\u202A-\u202E]/g, '')
            .replace(/\s*@\s*/g, '@')
            .replace(/\s*\.\s*/g, '.');
        const email = (normalizedContactText.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i)?.[0] || '').toLowerCase();
        const phoneCandidates = [];

        lines.forEach((line, lineIndex) => {
            const scrubbed = line.replace(/[A-Z0-9._%+-]+\s*@\s*[A-Z0-9.-]+(?:\s*\.\s*[A-Z]{2,})+/ig, ' ')
                .replace(/(?:https?:\/\/|www\.)\S+/ig, ' ');
            for (const match of scrubbed.matchAll(/(?:\+?\d[\d\s().-]{5,}\d)/g)) {
                const raw = match[0].trim();
                const digits = raw.replace(/\D/g, '');
                if (digits.length < 7 || digits.length > 15) continue;
                const phone = `${raw.startsWith('+') ? '+' : ''}${digits}`;
                let score = 0;
                if (/(?:mobile|phone|tel(?:ephone)?|cell|جوال|هاتف|تلفون)/i.test(line)) score += 5;
                if (/^(?:\+966|00966|966|05)/.test(phone)) score += 3;
                if (digits.length >= 9 && digits.length <= 12) score += 2;
                phoneCandidates.push({ phone, score, lineIndex });
            }
        });
        phoneCandidates.sort((left, right) => right.score - left.score || left.lineIndex - right.lineIndex);

        const labelledName = findLabelledBusinessCardValue(lines, [
            /^(?:full\s+name|name|contact(?:\s+person)?)\s*[:|\-–—]?\s*(.*)$/i,
            /^(?:الاسم\s+الكامل|الاسم|اسم\s+جهة\s+الاتصال)\s*[:|\-–—]?\s*(.*)$/i
        ]);
        const labelledCompany = findLabelledBusinessCardValue(lines, [
            /^(?:company\s+name|company|organization|organisation|business)\s*[:|\-–—]?\s*(.*)$/i,
            /^(?:اسم\s+الشركة|اسم\s+المؤسسة|الشركة|المؤسسة)\s*[:|\-–—]?\s*(.*)$/i
        ]);
        const contactPattern = /(?:@|https?:\/\/|www\.|mobile|phone|tel(?:ephone)?|email|e-mail|website|address|جوال|هاتف|تلفون|بريد|موقع|عنوان)/i;
        const jobPattern = /(?:manager|director|specialist|engineer|consultant|sales|marketing|founder|owner|chief|ceo|cfo|coo|مدير|مهندس|أخصائي|استشاري|مبيعات|تسويق|رئيس|مؤسس)/i;
        const companyPattern = /(?:company|co\.?|llc|ltd\.?|limited|inc\.?|corporation|corp\.?|group|establishment|trading|services|solutions|شركة|مؤسسة|مجموعة|للتجارة|للخدمات|للمقاولات)/i;
        const addressPattern = /(?:street|road|avenue|building|floor|district|riyadh|jeddah|dammam|saudi\s+arabia|شارع|طريق|مبنى|الدور|حي|الرياض|جدة|الدمام|السعودية)/i;
        const textualLines = lines.filter(line => {
            if (contactPattern.test(line) || /\d{4,}/.test(line)) return false;
            const letters = line.match(/[A-Za-z\u0600-\u06FF]/g) || [];
            return letters.length >= 3 && line.length <= 120;
        });

        const measuredVisualLines = visualLines
            .map((line, index) => ({
                text: cleanBusinessCardValue(line?.text),
                height: Math.max(0, Number(line?.height || 0)),
                width: Math.max(0, Number(line?.width || 0)),
                confidence: Number(line?.confidence || 0),
                index
            }));
        const visualName = measuredVisualLines
            .filter(line => {
                if (!line.text || contactPattern.test(line.text) || companyPattern.test(line.text) || jobPattern.test(line.text) || addressPattern.test(line.text)) return false;
                const letters = line.text.match(/[A-Za-z\u0600-\u06FF]/g) || [];
                const words = line.text.split(/\s+/).filter(Boolean);
                return letters.length >= 2 && words.length <= 6 && line.text.length <= 80;
            })
            .sort((left, right) => right.height - left.height
                || (right.height * right.width) - (left.height * left.width)
                || right.confidence - left.confidence
                || left.index - right.index)[0]?.text || '';

        const visualCompany = measuredVisualLines
            .filter(line => {
                if (!line.text || line.text === visualName || contactPattern.test(line.text) || jobPattern.test(line.text) || addressPattern.test(line.text)) return false;
                const letters = line.text.match(/[A-Za-z\u0600-\u06FF]/g) || [];
                const words = line.text.split(/\s+/).filter(Boolean);
                return letters.length >= 2 && words.length <= 8 && line.text.length <= 100;
            })
            .sort((left, right) => Number(companyPattern.test(right.text)) - Number(companyPattern.test(left.text))
                || right.height - left.height
                || (right.height * right.width) - (left.height * left.width)
                || right.confidence - left.confidence
                || left.index - right.index)[0]?.text || '';
        const company = cleanBusinessCardValue(labelledCompany)
            || cleanBusinessCardValue(textualLines.find(line => companyPattern.test(line)))
            || cleanBusinessCardValue(visualCompany);
        const nameCandidate = textualLines.find(line => {
            if (line === company || companyPattern.test(line) || jobPattern.test(line)) return false;
            const words = line.split(/\s+/).filter(Boolean);
            return words.length >= 2 && words.length <= 6 && line.length <= 80;
        });
        const name = cleanBusinessCardValue(visualName)
            || cleanBusinessCardValue(labelledName)
            || cleanBusinessCardValue(nameCandidate);

        return {
            name,
            company,
            email,
            phone: phoneCandidates[0]?.phone || ''
        };
    }

    async function loadPdfJs() {
        if (!pdfJsPromise) {
            pdfJsPromise = import(assetUrl('js/vendor/pdfjs/pdf.min.mjs')).then(pdfjs => {
                pdfjs.GlobalWorkerOptions.workerSrc = assetUrl('js/vendor/pdfjs/pdf.worker.min.mjs');
                return pdfjs;
            });
        }
        return pdfJsPromise;
    }

    async function createOcrWorker(onProgress) {
        if (!globalScope.Tesseract?.createWorker) throw new Error('Local OCR engine is unavailable');
        return globalScope.Tesseract.createWorker(['eng', 'ara'], globalScope.Tesseract.OEM.LSTM_ONLY, {
            workerPath: assetUrl('js/vendor/tesseract/worker.min.js'),
            corePath: assetUrl('js/vendor/tesseract/core/').replace(/\/$/, ''),
            langPath: assetUrl('js/vendor/tesseract/lang/').replace(/\/$/, ''),
            logger: message => {
                if (message?.status === 'recognizing text') onProgress?.({ phase: 'ocr', progress: Number(message.progress || 0) });
            }
        });
    }

    async function recognizeSources(sources, initialText, onProgress) {
        let worker;
        let text = initialText || '';
        try {
            worker = await createOcrWorker(onProgress);
            for (let index = 0; index < sources.length; index += 1) {
                onProgress?.({ phase: 'ocr', progress: index / Math.max(1, sources.length) });
                const result = await worker.recognize(sources[index]);
                text += `\n${result?.data?.text || ''}`;
                const metadata = parseMetadata(text);
                if (metadata.ownerName && metadata.expirationDate) break;
            }
            return text;
        } finally {
            if (worker) await worker.terminate();
        }
    }

    async function extractPdfText(file, onProgress) {
        onProgress?.({ phase: 'pdf', progress: 0 });
        const pdfjs = await loadPdfJs();
        const loadingTask = pdfjs.getDocument({ data: new Uint8Array(await file.arrayBuffer()), isEvalSupported: false });
        const pdf = await loadingTask.promise;
        const canvases = [];
        let text = '';
        try {
            const pageCount = Math.min(pdf.numPages, MAX_PDF_PAGES);
            for (let pageNumber = 1; pageNumber <= pageCount; pageNumber += 1) {
                const page = await pdf.getPage(pageNumber);
                const content = await page.getTextContent();
                text += `\n${content.items.map(item => `${item.str || ''}${item.hasEOL ? '\n' : ' '}`).join('')}`;
                onProgress?.({ phase: 'pdf', progress: pageNumber / pageCount });
            }
            const embeddedMetadata = parseMetadata(text);
            if (embeddedMetadata.ownerName && embeddedMetadata.expirationDate) return text;

            for (let pageNumber = 1; pageNumber <= pageCount; pageNumber += 1) {
                const page = await pdf.getPage(pageNumber);
                const baseViewport = page.getViewport({ scale: 1 });
                const scale = Math.min(2, Math.sqrt(4_000_000 / Math.max(1, baseViewport.width * baseViewport.height)));
                const viewport = page.getViewport({ scale });
                const canvas = document.createElement('canvas');
                canvas.width = Math.ceil(viewport.width);
                canvas.height = Math.ceil(viewport.height);
                await page.render({ canvasContext: canvas.getContext('2d', { alpha: false }), viewport }).promise;
                canvases.push(canvas);
            }
            return recognizeSources(canvases, text, onProgress);
        } finally {
            await pdf.destroy();
        }
    }

    async function extract(file, options = {}) {
        if (!file) return { ownerName: '', expirationDate: '', text: '' };
        const onProgress = options.onProgress;
        let text = '';
        if (file.type === 'application/pdf' || /\.pdf$/i.test(file.name || '')) {
            text = await extractPdfText(file, onProgress);
        } else {
            text = await recognizeSources([file], '', onProgress);
        }
        return { ...parseMetadata(text), text };
    }

    async function extractBusinessCard(file, options = {}) {
        if (!file) return { name: '', company: '', email: '', phone: '', text: '' };
        let worker;
        try {
            worker = await createOcrWorker(options.onProgress);
            await worker.setParameters({
                tessedit_pageseg_mode: globalScope.Tesseract?.PSM?.SPARSE_TEXT || '11',
                preserve_interword_spaces: '1'
            });
            const result = await worker.recognize(file, {}, { text: true, blocks: true });
            const blocks = result?.data?.blocks || result?.data?.layoutBlocks || [];
            const visualLines = blocks.flatMap(block => (block.paragraphs || []).flatMap(paragraph =>
                (paragraph.lines || []).map(line => ({
                    text: line.text || '',
                    height: Math.max(0, Number(line.bbox?.y1 || 0) - Number(line.bbox?.y0 || 0)),
                    width: Math.max(0, Number(line.bbox?.x1 || 0) - Number(line.bbox?.x0 || 0)),
                    confidence: Number(line.confidence || 0)
                }))
            ));
            const text = [result?.data?.text || '', ...visualLines.map(line => line.text)].filter(Boolean).join('\n');
            return { ...parseBusinessCard(text, visualLines), text };
        } finally {
            if (worker) await worker.terminate();
        }
    }

    globalScope.EmployeeDocumentRecognition = Object.freeze({
        extract,
        parseMetadata,
        extractBusinessCard,
        parseBusinessCard
    });
})();
