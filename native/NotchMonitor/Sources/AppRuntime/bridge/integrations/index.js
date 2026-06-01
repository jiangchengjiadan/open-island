const claudeFamily = require('./claude-family');
const codex = require('./codex');
const cursor = require('./cursor');
const gemini = require('./gemini');

function getIntegration(source) {
  switch ((source || '').trim().toLowerCase()) {
    case 'claude':
    case 'qoder':
      return claudeFamily;
    case 'codex':
      return codex;
    case 'cursor':
      return cursor;
    case 'gemini':
      return gemini;
    default:
      return claudeFamily;
  }
}

module.exports = {
  getIntegration,
};
