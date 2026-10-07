import { useState } from 'react';
import { PRIORITIES, STATUSES, label, toPayload } from '../lib/tasks.js';

export default function TaskModal({ task, onSave, onClose }) {
  const isEdit = Boolean(task.id);
  const [form, setForm] = useState({
    title: task.title || '',
    description: task.description || '',
    priority: task.priority || 'MEDIUM',
    status: task.status || 'TODO',
    assignee: task.assignee || 'Rudhar Bajaj',
    due_date: task.due_date || '',
  });
  const set = (key) => (e) => setForm({ ...form, [key]: e.target.value });

  const submit = (e) => {
    e.preventDefault();
    onSave(toPayload(form));
  };

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <form className="modal" onSubmit={submit} onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <div>
            <p className="eyebrow">{isEdit ? 'EDIT TASK' : 'CREATE TASK'}</p>
            <h2>{isEdit ? task.title : 'Add a new task'}</h2>
          </div>
          <button type="button" className="close" onClick={onClose} aria-label="Close">x</button>
        </div>
        <label>Title<input value={form.title} onChange={set('title')} required maxLength={200} placeholder="e.g. Configure production ingress" /></label>
        <label>Description<textarea value={form.description} onChange={set('description')} placeholder="What needs to be done?" /></label>
        <div className="form-row">
          <label>Priority
            <select value={form.priority} onChange={set('priority')}>
              {PRIORITIES.map((p) => <option key={p} value={p}>{label(p)}</option>)}
            </select>
          </label>
          <label>Status
            <select value={form.status} onChange={set('status')}>
              {STATUSES.map((s) => <option key={s} value={s}>{label(s)}</option>)}
            </select>
          </label>
        </div>
        <div className="form-row">
          <label>Assignee<input value={form.assignee} onChange={set('assignee')} maxLength={120} /></label>
          <label>Due date<input type="date" value={form.due_date} onChange={set('due_date')} /></label>
        </div>
        <button className="primary full" type="submit">{isEdit ? 'Save changes' : 'Create task'}</button>
      </form>
    </div>
  );
}
