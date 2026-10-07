import test from 'node:test';
import assert from 'node:assert/strict';
import { buildQuery, isOverdue, label, nextStatus, toPayload } from './tasks.js';

test('nextStatus cycles TODO -> IN_PROGRESS -> DONE -> TODO', () => {
  assert.equal(nextStatus('TODO'), 'IN_PROGRESS');
  assert.equal(nextStatus('IN_PROGRESS'), 'DONE');
  assert.equal(nextStatus('DONE'), 'TODO');
});

test('label makes enum values readable', () => {
  assert.equal(label('IN_PROGRESS'), 'In progress');
  assert.equal(label('HIGH'), 'High');
});

test('buildQuery skips ALL and empty search', () => {
  assert.equal(buildQuery({ status: 'ALL', q: '  ' }), '');
  assert.equal(buildQuery({ status: 'DONE', q: 'helm chart' }), '?status=DONE&q=helm+chart');
});

test('isOverdue ignores done tasks and tasks without a due date', () => {
  const today = '2026-10-08';
  assert.equal(isOverdue({ status: 'TODO', due_date: '2026-10-01' }, today), true);
  assert.equal(isOverdue({ status: 'DONE', due_date: '2026-10-01' }, today), false);
  assert.equal(isOverdue({ status: 'TODO', due_date: null }, today), false);
  assert.equal(isOverdue({ status: 'TODO', due_date: '2026-10-09' }, today), false);
});

test('toPayload trims text and defaults the assignee', () => {
  assert.deepEqual(toPayload({ title: '  Ship it ', assignee: ' ', due_date: '' }), {
    title: 'Ship it', description: '', priority: 'MEDIUM', status: 'TODO', assignee: 'Unassigned', due_date: null,
  });
});
