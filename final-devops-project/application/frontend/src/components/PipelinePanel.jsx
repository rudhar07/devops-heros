const STAGES = ['Test', 'Scan', 'Build', 'Push', 'Deploy', 'Monitor'];

export default function PipelinePanel({ activity }) {
  return (
    <aside className="panel side-panel">
      <div className="panel-head">
        <div>
          <h2>Recent activity</h2>
          <p className="muted">Changes made in this browser session.</p>
        </div>
      </div>
      {activity.length === 0 && <div className="empty small">Nothing yet.</div>}
      {activity.map((a, i) => (
        <div className="activity-row" key={i}>
          <span className="activity-icon">•</span>
          <div>
            <b>{a.text}</b>
            <small>{a.at.toLocaleTimeString()}</small>
          </div>
        </div>
      ))}
      <div className="pipeline" aria-label="Delivery pipeline">
        {STAGES.map((s, i) => (
          <span key={s}>{i > 0 && <i />}{s}</span>
        ))}
      </div>
    </aside>
  );
}
