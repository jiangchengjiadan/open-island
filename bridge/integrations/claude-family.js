function firstNonEmpty(values) {
  return values.find((value) => typeof value === 'string' && value.trim() !== '') || '';
}

function sessionId(source, payload, env, fallback) {
  return firstNonEmpty([
    payload.session_id,
    payload.sessionId,
    payload.parent_session_id,
    payload.parentSessionId,
    env.CLAUDE_SESSION_ID,
    env.CLAUDE_SESSION_NAME,
    fallback,
  ]);
}

function sessionName(source, payload, env, fallback) {
  return firstNonEmpty([
    payload.session_name,
    payload.sessionName,
    env.CLAUDE_SESSION_NAME,
    fallback,
  ]);
}

function permissionOutput(eventName, allowed) {
  return {
    continue: true,
    hookSpecificOutput: {
      hookEventName: eventName,
      permissionDecision: allowed ? 'allow' : 'deny',
      permissionDecisionReason: allowed
        ? 'Approved in NotchMonitor'
        : 'Denied in NotchMonitor',
    },
    suppressOutput: true,
  };
}

function shouldLogUnhandledPreTool(source) {
  return source === 'qoder';
}

module.exports = {
  sessionId,
  sessionName,
  permissionOutput,
  shouldLogUnhandledPreTool,
};
