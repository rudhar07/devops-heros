import { useCallback, useEffect, useState } from 'react';
import { api } from './api.js';
import { buildQuery, nextStatus } from './lib/tasks.js';
import Sidebar from './components/Sidebar.jsx';
import StatCards from './components/StatCards.jsx';
import TaskTable from './components/TaskTable.jsx';
import TaskModal from './components/TaskModal.jsx';
import PipelinePanel from './components/PipelinePanel.jsx';

const EMPTY_STATS = { total: 0, todo: 0, inProgress: 0, done: 0, highPriorityOpen: 0, overdue: 0 };

export default function App() {
  const [tasks, setTasks] = useState([]);
  const [stats, setStats] = useState(EMPTY_STATS);
  const [info, setInfo] = useState(null);
  const [filter, setFilter] = useState('ALL');
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [editing, setEditing] = useState(null); // null = closed, {} = new, task = edit
  const [activity, setActivity] = useState([]);

  const log = (text) => setActivity((a) => [{ text, at: new Date() }, ...a].slice(0, 6));

  const load = useCallback(async () => {
    try {
      setError('');
      const [list, s] = await Promise.all([api.list(buildQuery({ status: filter, q: search })), api.stats()]);
      setTasks(list);
      setStats(s);
    } catch (e) {
      setError(e.message || 'Backend unavailable');
    } finally {
      setLoading(false);
    }
  }, [filter, search]);

  useEffect(() => {
    const t = setTimeout(load, 200); // small debounce for the search box
    return () => clearTimeout(t);
  }, [load]);

  useEffect(() => {
    api.info().then(setInfo).catch(() => setInfo(null));
  }, []);

  const run = async (fn, message) => {
    try {
      await fn();
      log(message);
      await load();
    } catch (e) {
      setError(e.message);
    }
  };

  const save = (payload) =>
    run(async () => {
      if (editing && editing.id) await api.update(editing.id, payload);
      else await api.create(payload);
      setEditing(null);
    }, editing && editing.id ? `Updated "${payload.title}"` : `Created "${payload.title}"`);

  const advance = (task) =>
    run(() => api.update(task.id, { status: nextStatus(task.status) }), `Moved "${task.title}" to ${nextStatus(task.status).replace('_', ' ')}`);

  const remove = (task) => {
    if (!window.confirm(`Delete "${task.title}"?`)) return;
    run(() => api.remove(task.id), `Deleted "${task.title}"`);
  };

  return (
    <div className="app">
      <Sidebar info={info} />
      <main className="main">
        <header className="page-head">
          <div>
            <p className="eyebrow">WORKSPACE / OVERVIEW</p>
            <h1>Team TaskBoard</h1>
            <p className="muted">Plan, track and ship the work of the platform team.</p>
          </div>
          <button className="primary" onClick={() => setEditing({})}>+ New task</button>
        </header>

        {error && (
          <div className="alert" role="alert">
            {error}. Check that the backend and PostgreSQL are running, then retry.
            <button className="link" onClick={load}>Retry</button>
          </div>
        )}

        <StatCards stats={stats} />

        <section className="content-grid">
          <TaskTable
            tasks={tasks}
            loading={loading}
            filter={filter}
            onFilter={setFilter}
            search={search}
            onSearch={setSearch}
            onAdvance={advance}
            onEdit={setEditing}
            onDelete={remove}
          />
          <PipelinePanel activity={activity} info={info} />
        </section>
      </main>
      {editing && <TaskModal task={editing} onSave={save} onClose={() => setEditing(null)} />}
    </div>
  );
}
