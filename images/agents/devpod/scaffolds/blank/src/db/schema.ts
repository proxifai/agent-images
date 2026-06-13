import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

/**
 * Drizzle schema. Tables here become real sqlite tables after
 *   bun run db:push
 *
 * The ProxiBuild agent edits this file when the user asks for
 * persistence. Keep schemas small and explicit; the agent can always add
 * more tables on request.
 */

export const todos = sqliteTable("todos", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  title: text("title").notNull(),
  completed: integer("completed", { mode: "boolean" }).notNull().default(false),
  createdAt: text("created_at").notNull().default("CURRENT_TIMESTAMP"),
});

export type Todo = typeof todos.$inferSelect;
export type NewTodo = typeof todos.$inferInsert;
