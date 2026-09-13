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
        return '';
    }

    function parseMetadata(text) {
        return {
            ownerName: findOwnerName(text),
            expirationDate: findExpirationDate(text)
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

    globalScope.EmployeeDocumentRecognition = Object.freeze({ extract, parseMetadata });
})();
