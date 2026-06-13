/// <reference types="bun-types" />
import { Database } from "bun:sqlite";
import { drizzle } from "drizzle-orm/bun-sqlite";
import * as schema from "./schema";

/**
 * Server-side database module. Loaded by vite's dev-server middleware
 * and by the ProxiBuild agent's db-introspect helper — never by client
 * code (the browser can't talk to bun:sqlite).
 *
 * The file is at /workspace/data.db inside the dev pod, on the same PVC
 * the workspace lives on; survives the idle reaper's pod teardown.
 */
const dbPath = process.env.DATABASE_URL ?? "data.db";
export const sqlite = new Database(dbPath);
export const db = drizzle(sqlite, { schema });
export { schema };
