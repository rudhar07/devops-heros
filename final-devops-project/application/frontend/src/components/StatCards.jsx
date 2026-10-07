const CARDS = [
  ['Total tasks', 'total'],
  ['To do', 'todo'],
  ['In progress', 'inProgress'],
  ['Completed', 'done'],
  ['High priority open', 'highPriorityOpen'],
  ['Overdue', 'overdue'],
];

export default function StatCards({ stats }) {
  return (
    <section className="stats" aria-label="Task statistics">
      {CARDS.map(([title, key]) => (
        <div className={`stat ${key === 'overdue' && stats[key] > 0 ? 'warn' : ''}`} key={key}>
          <small>{title}</small>
          <strong data-testid={`stat-${key}`}>{stats[key]}</strong>
        </div>
      ))}
    </section>
  );
}
