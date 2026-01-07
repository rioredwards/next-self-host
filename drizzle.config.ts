import dotenv from "dotenv";
import type { Config } from "drizzle-kit";
import { resolve } from "path";

// Load .env.local for local development, fallback to .env
dotenv.config({ path: resolve(process.cwd(), ".env.local") });
dotenv.config({ path: resolve(process.cwd(), ".env") });

export default {
  schema: "./app/db/schema.ts",
  out: "./app/db/migrations",
  dialect: "postgresql",
  dbCredentials: {
    url: process.env.DATABASE_URL_EXTERNAL!,
  },
} satisfies Config;
