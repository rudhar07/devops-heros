"""add due_date, updated_at and indexes for the list filters

Revision ID: 0002_due_date_updated_at
Revises: 0001_create_tasks
"""
import sqlalchemy as sa
from alembic import op

revision = "0002_due_date_updated_at"
down_revision = "0001_create_tasks"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("tasks") as batch:
        batch.add_column(sa.Column("due_date", sa.Date(), nullable=True))
        batch.add_column(
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False,
                      server_default=sa.func.now())
        )
    op.create_index("ix_tasks_status", "tasks", ["status"])
    op.create_index("ix_tasks_priority", "tasks", ["priority"])


def downgrade():
    op.drop_index("ix_tasks_priority", table_name="tasks")
    op.drop_index("ix_tasks_status", table_name="tasks")
    with op.batch_alter_table("tasks") as batch:
        batch.drop_column("updated_at")
        batch.drop_column("due_date")
