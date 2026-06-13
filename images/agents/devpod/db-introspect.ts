#!/usr/bin/env bun
/**
 * db-introspect.ts — emits the current sqlite schema as a single JSON
 * line on stdout. Invoked by proxifai's build.Service.IntrospectDB via
 * kubectl exec; the JSON shape is consumed by web/components/build/
 * database-pane.tsx.
 *
 * Output shape:
 *   { "tables": [
 *       { "name": "todos", "rowCount": 3, "columns": [
 *           { "name": "id", "type": "INTEGER", "nullable": false, "pk": true },
 *           ...
 *         ]
 *       }
 *     ]
 *   }
 *
 * Exits 0 on success, 1 on any error. The "all errors are stderr"
 * convention keeps the JSON line clean for the caller's parser.
 */
import { Database } from "bun:sqlite";

const dbPath = process.env.DATABASE_URL ?? "/workspace/data.db";

try {
  const db = new Database(dbPath, { readonly: true });
  const tablesRaw = db
    .query(
      `SELECT name FROM sqlite_master
        WHERE type='table'
          AND name NOT LIKE 'sqlite_%'
          AND name NOT LIKE '__drizzle%'
        ORDER BY name`,
    )
    .all() as Array<{ name: string }>;

  type Col = { name: string; type: string; nullable: boolean; pk: boolean };
  type Table = { name: string; rowCount: number; columns: Col[] };

  const tables: Table[] = tablesRaw.map((t) => {
    const cols = db
      .query(`PRAGMA table_info("${t.name.replace(/"/g, '""')}")`)
      .all() as Array<{
        name: string;
        type: string;
        notnull: number;
        pk: number;
      }>;
    const count = (
      db.query(`SELECT COUNT(*) AS n FROM "${t.name.replace(/"/g, '""')}"`).get() as {
        n: number;
      } | null
    )?.n ?? 0;
    return {
      name: t.name,
      rowCount: count,
      columns: cols.map((c) => ({
        name: c.name,
        type: c.type || "ANY",
        nullable: c.notnull === 0,
        pk: c.pk > 0,
      })),
    };
  });
  process.stdout.write(JSON.stringify({ tables }) + "\n");
  process.exit(0);
} catch (e) {
  process.stderr.write(`db-introspect: ${e instanceof Error ? e.message : String(e)}\n`);
  // Emit empty result so the caller still gets parseable JSON.
  process.stdout.write(JSON.stringify({ tables: [] }) + "\n");
  process.exit(1);
}
