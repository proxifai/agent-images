import { defineConfig } from "drizzle-kit";

// DATABASE_URL is set to /workspace/data.db inside the dev pod (sqlite
// file living on the same PVC that backs /workspace). Locally it
// defaults to a sibling data.db so `bun run db:push` works outside the
// container too.
export default defineConfig({
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  dialect: "sqlite",
  dbCredentials: {
    url: process.env.DATABASE_URL ?? "data.db",
  },
});
