function firstNonEmpty(values) {
  return values.find((value) => typeof value === 'string' && value.trim() !== '') || '';
}

function sessionId(source, payload, env, fallback) {
  return firstNonEmpty([
    payload.session_id,
    payload.sessionId,
    payload.parent_session_id,
    payload.parentSessionId,
    env.CODEX_SESSION_ID,
    fallback,
  ]);
}

function sessionName(source, payload, env, fallback) {
  return firstNonEmpty([
    payload.session_name,
    payload.sessionName,
    payload.cwd,
    fallback,
  ]);
}

function permissionOutput(eventName, allowed) {
  return {
    continue: Boolean(allowed),
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
};
