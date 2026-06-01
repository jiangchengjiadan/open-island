const path = require('path');

function firstNonEmpty(values) {
  return values.find((value) => typeof value === 'string' && value.trim() !== '') || '';
}

function firstWorkspaceRoot(payload) {
  if (Array.isArray(payload.workspace_roots)) {
    return payload.workspace_roots.find((value) => typeof value === 'string' && value.trim() !== '') || '';
  }
  if (Array.isArray(payload.workspaceRoots)) {
    return payload.workspaceRoots.find((value) => typeof value === 'string' && value.trim() !== '') || '';
  }
  return '';
}

function resolvedCwd(payload, fallback) {
  return firstNonEmpty([
    payload.cwd,
    firstWorkspaceRoot(payload),
    fallback,
  ]);
}

function sessionId(source, payload, env, fallback) {
  return firstNonEmpty([
    payload.conversation_id,
    payload.conversationId,
    resolvedCwd(payload, ''),
    fallback,
  ]);
}

function sessionName(source, payload, env, fallback) {
  const workspace = resolvedCwd(payload, '');
  if (workspace) {
    return path.basename(workspace);
  }

  return firstNonEmpty([
    payload.session_name,
    payload.sessionName,
    fallback,
  ]);
}

function permissionOutput() {
  return {
    continue: true,
  };
}

function shouldLogUnhandledPreTool() {
  return false;
}

module.exports = {
  sessionId,
  sessionName,
  permissionOutput,
  shouldLogUnhandledPreTool,
  resolvedCwd,
};
