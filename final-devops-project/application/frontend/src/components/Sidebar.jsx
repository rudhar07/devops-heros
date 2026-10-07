export default function Sidebar({ info }) {
  return (
    <aside className="sidebar">
      <div className="brand">
        <span className="brand-mark">T</span>
        <div>
          <b>TaskBoard</b>
          <small>DevOps final project</small>
        </div>
      </div>
      <nav>
        <a className="active" href="#tasks">Dashboard</a>
        <a href="/api/info">API info</a>
        <a href="/api/tasks">Raw JSON</a>
      </nav>
      <div className="side-bottom">
        <div className="env-card">
          <strong>Environment</strong>
          <p>{info ? `${info.environment} · v${info.version}` : 'backend not reachable'}</p>
          <p className="mono">commit {info ? String(info.commit).slice(0, 7) : '-'}</p>
        </div>
        <div className="profile">
          <div className="avatar">RB</div>
          <div>
            <b>Rudhar Bajaj</b>
            <small>Platform engineer</small>
          </div>
        </div>
      </div>
    </aside>
  );
}
