"""Business metrics, next to the HTTP metrics from the instrumentator."""
from prometheus_client import Counter

TASK_EVENTS = Counter(
    "taskboard_task_events_total",
    "Task write operations handled by the API",
    ["action"],  # created | updated | deleted
)
