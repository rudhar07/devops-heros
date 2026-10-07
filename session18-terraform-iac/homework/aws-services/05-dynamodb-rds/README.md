# DynamoDB and RDS

Both are managed databases, so AWS handles hardware, patching and replication, but they solve different problems.

| | DynamoDB | RDS |
|---|---|---|
| Model | NoSQL key-value / document | Relational (tables, SQL, joins) |
| Schema | Only the key is fixed. Each item can have different attributes | Fixed schema, migrations |
| Scaling | Horizontal, automatic, effectively unlimited | Mostly vertical (bigger instance) + read replicas |
| Servers to pick | None (serverless) | Instance class, storage, engine version |
| Access pattern | Design around known queries by key | Ad-hoc SQL, joins, aggregates |
| Latency | Single-digit ms at any scale | Depends on instance and query |
| Pricing | Per request (on-demand) or provisioned capacity + storage | Per instance-hour + storage + I/O |

---

## DynamoDB

### Concepts

| Term | Meaning | My example |
|---|---|---|
| **Table** | Collection of items. No fixed columns apart from the key | `hw18-orders` |
| **Item** | One record (max 400 KB), like a row | one order |
| **Attribute** | A name + typed value: `S` string, `N` number, `BOOL`, `L` list, `M` map, ... | `Total` (N), `Coupon` (S) |
| **Partition key** (HASH) | Hashed to choose the physical partition. Should have **many distinct values** so load spreads out | `CustomerId` |
| **Sort key** (RANGE), optional | Orders items *within* a partition and enables range queries (`>=`, `begins_with`, `between`) | `OrderDate` |
| **Primary key** | Partition key alone, or partition + sort. **Must be unique** | (`CustomerId`, `OrderDate`) |
| GSI / LSI | Secondary indexes for other access patterns | e.g. GSI on `Status` |

Two ways to read: `Query` (by key, efficient) and `Scan` (reads the whole table, costly; avoid in hot paths). Other features: TTL to auto-expire items, Streams for change events, point-in-time recovery, and global tables for multi-region.

**Use cases:** user sessions, shopping carts, game leaderboards, IoT telemetry, metadata lookups, and the classic Terraform state-lock table (key `LockID`).

### Hands-on against LocalStack

Transcript: [`../../outputs/14-dynamodb.txt`](../../outputs/14-dynamodb.txt).

```text
$ aws ... dynamodb create-table --table-name hw18-orders \
    --attribute-definitions AttributeName=CustomerId,AttributeType=S AttributeName=OrderDate,AttributeType=S \
    --key-schema AttributeName=CustomerId,KeyType=HASH AttributeName=OrderDate,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST ...
{
    "Table": "hw18-orders",
    "Status": "ACTIVE",
    "Keys": [
        { "AttributeName": "CustomerId", "KeyType": "HASH" },
        { "AttributeName": "OrderDate", "KeyType": "RANGE" }
    ],
    "Billing": "PAY_PER_REQUEST"
}
```

(the two key objects are put on one line each)

I put three items. Customer C-001 has two orders, and only one of them has a `Coupon` attribute, which is fine because there's no schema:

```text
$ aws ... dynamodb get-item --table-name hw18-orders --key '{"CustomerId":{"S":"C-001"},"OrderDate":{"S":"2026-10-05"}}'
{ "Item": { "Coupon": {"S": "DIWALI10"}, "CustomerId": {"S": "C-001"}, "OrderDate": {"S": "2026-10-05"}, "Total": {"N": "1299"} } }

$ aws ... dynamodb query --table-name hw18-orders --key-condition-expression 'CustomerId = :c AND OrderDate >= :d' ...  (:d = 2026-10-02)
{ "Count": 1, "Items": [ { "Date": "2026-10-05", "Total": "1299" } ] }

$ aws ... dynamodb query ... 'CustomerId = :c' --no-scan-index-forward --query 'Items[].OrderDate.S'
[ "2026-10-05", "2026-10-01" ]
```

(JSON condensed)

The sort key does the date filtering and ordering (newest first with `--no-scan-index-forward`) inside one customer's partition, so no scan is needed. Writing the same partition key + sort key again **overwrites** the item:

```text
$ aws ... dynamodb put-item ... C-002 / 2026-10-03 / Total 300 --return-values ALL_OLD --query 'Attributes.Total.N'
"250"            <- the old value that was replaced
$ aws ... dynamodb scan ... -> Count 3
```

---

## RDS: Relational Database Service

**Not in LocalStack community.** I checked it ([`15-rds-not-in-community.txt`](../../outputs/15-rds-not-in-community.txt)):

```text
$ aws --endpoint-url http://localhost:4566 rds describe-db-instances
aws: [ERROR]: An error occurred (InternalFailure) when calling the DescribeDBInstances operation:
The API for service rds is either not included in your current license plan or has not yet been emulated by LocalStack.
```

So this section is conceptual only.

### Concepts

| Term | Meaning |
|---|---|
| **Engines** | MySQL, PostgreSQL, MariaDB, Oracle, SQL Server, IBM Db2, plus **Aurora** (AWS's MySQL/PostgreSQL-compatible engine with shared distributed storage) |
| **DB instance** | One managed database server: instance class (e.g. `db.t4g.micro`, `db.r7g.large`) + EBS storage (gp3/io2) + engine version |
| **DB subnet group** | The (private) subnets in ≥ 2 AZs where RDS may place the instance |
| **Parameter group** | Engine settings (`max_connections`, ...) |
| **Endpoint** | DNS name apps connect to, e.g. `mydb.xxxx.ap-south-1.rds.amazonaws.com:5432`. Never use an IP |

### Security

- Put it in **private subnets** with `publicly_accessible = false`.
- Its security group allows the DB port **only from the app's security group**, not from a CIDR.
- Encryption at rest with KMS must be chosen at creation. TLS in transit.
- Keep the master password in **Secrets Manager** (RDS can manage and rotate it), or use IAM database authentication. Never put it in Terraform code or Git.

### Backups

| Kind | How | Retention |
|---|---|---|
| Automated backups | Daily snapshot + transaction logs, so **point-in-time restore** to any second in the window | 0-35 days (0 = off) |
| Manual snapshots | You trigger them, kept until you delete them | Unlimited, can be copied cross-region |

A restore always creates a **new** instance with a new endpoint.

### Multi-AZ vs read replicas

| | Multi-AZ | Read replica |
|---|---|---|
| Purpose | **High availability** | **Read scaling** (and DR if cross-region) |
| Replication | Synchronous to a standby in another AZ | Asynchronous |
| Can you read from it? | No, the standby is passive (except the newer Multi-AZ *cluster* option with 2 readable standbys) | Yes, it has its own endpoint |
| Failover | Automatic, 60-120 s, same endpoint DNS | Manual promote, new endpoint |
| Typical | Every production DB | Reporting/analytics, read-heavy apps |

### Use cases

Anything that needs transactions, joins and constraints: e-commerce orders and payments, ERP/CRM, user accounts, and the backend of most web frameworks (Django, Rails, Spring) without running the DB server yourself.

### Picking between them

If the data has relations, the queries aren't known up front, or you need multi-row ACID transactions with SQL, choose **RDS**. If the access is always "get/put by a key" at very high or spiky scale and you want no servers to manage, choose **DynamoDB**.
