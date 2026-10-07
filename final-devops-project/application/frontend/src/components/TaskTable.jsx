import { isOverdue, label } from '../lib/tasks.js';

const FILTERS = ['ALL', 'TODO', 'IN_PROGRESS', 'DONE'];

export default function TaskTable({ tasks, loading, filter, onFilter, search, onSearch, onAdvance, onEdit, onDelete }) {
  return (
    <div className="panel tasks-panel" id="tasks">
      <div className="panel-head">
        <div>
          <h2>Tasks</h2>
          <p className="muted">{tasks.length} shown</p>
        </div>
        <div className="toolbar">
          <input
            className="search"
            type="search"
            placeholder="Search title, description, assignee"
            value={search}
            onChange={(e) => onSearch(e.target.value)}
            aria-label="Search tasks"
          />
          <div className="filters" role="tablist">
            {FILTERS.map((f) => (
              <button key={f} className={filter === f ? 'selected' : ''} onClick={() => onFilter(f)}>
                {f === 'ALL' ? 'All' : label(f)}
              </button>
            ))}
          </div>
        </div>
      </div>
      {loading ? (
        <div className="empty">Loading tasks...</div>
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Task</th>
                <th>Assignee</th>
                <th>Priority</th>
                <th>Status</th>
                <th>Due</th>
                <th aria-label="actions" />
              </tr>
            </thead>
            <tbody>
              {tasks.map((t) => (
                <tr key={t.id}>
                  <td data-label="Task">
                    <div className="task-title">
                      <span className={`dot ${t.status.toLowerCase()}`} />
                      <div>
                        <b>{t.title}</b>
                        {t.description && <small>{t.description}</small>}
                      </div>
                    </div>
                  </td>
                  <td data-label="Assignee">{t.assignee}</td>
                  <td data-label="Priority"><span className={`badge priority ${t.priority.toLowerCase()}`}>{label(t.priority)}</span></td>
                  <td data-label="Status"><span className={`badge status ${t.status.toLowerCase()}`}>{label(t.status)}</span></td>
                  <td data-label="Due" className={isOverdue(t) ? 'overdue' : ''}>{t.due_date || '-'}</td>
                  <td className="actions">
                    <button className="icon-btn" onClick={() => onAdvance(t)} title="Move to next status">Next</button>
                    <button className="icon-btn" onClick={() => onEdit(t)} title="Edit task">Edit</button>
                    <button className="icon-btn danger" onClick={() => onDelete(t)} title="Delete task">Delete</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {!tasks.length && <div className="empty">No tasks here yet. Create one with "+ New task".</div>}
        </div>
      )}
    </div>
  );
}
