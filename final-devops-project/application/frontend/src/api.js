// All calls go to the same origin under /api. nginx (Compose) or the
// Ingress (Kubernetes) routes them to the FastAPI backend.
const BASE = '/api';

async function request(path, options = {}) {
  const res = await fetch(`${BASE}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  if (!res.ok) {
    let detail = `${res.status} ${res.statusText}`;
    try {
      const body = await res.json();
      if (body.detail) detail = typeof body.detail === 'string' ? body.detail : JSON.stringify(body.detail);
    } catch { /* not JSON */ }
    throw new Error(detail);
  }
  return res.status === 204 ? null : res.json();
}

export const api = {
  list: (query = '') => request(`/tasks${query}`),
  stats: () => request('/tasks/stats'),
  info: () => request('/info'),
  create: (body) => request('/tasks', { method: 'POST', body: JSON.stringify(body) }),
  update: (id, body) => request(`/tasks/${id}`, { method: 'PUT', body: JSON.stringify(body) }),
  remove: (id) => request(`/tasks/${id}`, { method: 'DELETE' }),
};
