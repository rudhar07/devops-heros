// Pure helpers (no React, no fetch) so they can be unit-tested with `node --test`.

export const STATUSES = ['TODO', 'IN_PROGRESS', 'DONE'];
export const PRIORITIES = ['LOW', 'MEDIUM', 'HIGH'];

export function nextStatus(status) {
  const i = STATUSES.indexOf(status);
  return STATUSES[(i + 1) % STATUSES.length];
}

export function label(value) {
  return value.replace('_', ' ').toLowerCase().replace(/^\w/, (c) => c.toUpperCase());
}

export function buildQuery({ status = 'ALL', q = '' } = {}) {
  const params = new URLSearchParams();
  if (status && status !== 'ALL') params.set('status', status);
  if (q && q.trim()) params.set('q', q.trim());
  const s = params.toString();
  return s ? `?${s}` : '';
}

export function isOverdue(task, today = new Date().toISOString().slice(0, 10)) {
  return Boolean(task.due_date) && task.status !== 'DONE' && task.due_date < today;
}

// Form values -> API body. Empty due date is sent as null, text is trimmed.
export function toPayload(form) {
  return {
    title: (form.title || '').trim(),
    description: (form.description || '').trim(),
    priority: form.priority || 'MEDIUM',
    status: form.status || 'TODO',
    assignee: (form.assignee || '').trim() || 'Unassigned',
    due_date: form.due_date || null,
  };
}
