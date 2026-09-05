/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
const start = source.indexOf('function handleCrmPipelineWheel');
const end = source.indexOf("\ndocument.addEventListener('wheel', handleCrmPipelineWheel", start);
assert.ok(start >= 0 && end > start, 'CRM pipeline wheel handler was not found');

let textDirection = 'ltr';
const context = { getComputedStyle: () => ({ direction: textDirection }) };
vm.createContext(context);
vm.runInContext(`${source.slice(start, end)}\nglobalThis.testWheelHandler = handleCrmPipelineWheel;`, context);

function createBoard(min = 0, max = 700) {
    let position = 0;
    const board = { clientWidth: 500 };
    Object.defineProperty(board, 'scrollLeft', {
        get: () => position,
        set: value => { position = Math.max(min, Math.min(max, value)); }
    });
    return board;
}

function wheel(board, deltaY, deltaX = 0, deltaMode = 0) {
    let prevented = false;
    context.testWheelHandler({
        target: { closest: selector => selector === '#crmDealPipelineBoard' ? board : null },
        deltaY,
        deltaX,
        deltaMode,
        preventDefault: () => { prevented = true; }
    });
    return prevented;
}

const board = createBoard();
assert.equal(wheel(board, 100), true);
assert.equal(board.scrollLeft, 100);
board.scrollLeft = 700;
assert.equal(wheel(board, 100), false, 'Page scrolling should continue at the right edge');
board.scrollLeft = 0;
assert.equal(wheel(board, -100), false, 'Page scrolling should continue at the left edge');
assert.equal(wheel(board, 20, 40), false, 'Horizontal trackpad gestures should remain native');

textDirection = 'rtl';
const rtlBoard = createBoard(-700, 0);
assert.equal(wheel(rtlBoard, 100), true);
assert.equal(rtlBoard.scrollLeft, -100);

console.log('CRM pipeline wheel-scroll tests passed.');
