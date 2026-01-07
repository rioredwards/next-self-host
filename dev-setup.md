# Local Development Setup Success! ✅

It's all working!

## Summary of what's set up:

- ✅ Postgres database running in Docker container
- ✅ Next.js dev server ready to run locally
- ✅ Drizzle ORM configured and connected
- ✅ Environment variables configured for local development
- ✅ Database schema can be pushed/migrated

Your local development environment is ready. You can now:

1. **Start Postgres**: `docker-compose -f docker-compose.dev.yml up -d`
2. **Push database schema**: `npm run db:push`
3. **Start dev server**: `npm run dev`
4. **View database**: `npm run db:studio` (opens at http://localhost:4983)

Your Next.js app will be available at:
**http://localhost:3000**

---

# What went wrong and how we solved it

Refer to these next time, so that you don't run into the same issues again:

## Issues and Solutions

### 1. Package resolution and updates

**Issue:** Packages needed to be resolved and updated, with some vulnerabilities in deprecated dependencies

- Outdated packages
- Conflicting lock files (both `package-lock.json` and `bun.lockb` present)
- Vulnerabilities in deprecated `@esbuild-kit` packages used by `drizzle-kit`

**Solution:**

- Ran `npm update` to update all packages
- Removed conflicting `bun.lockb` file (project uses npm)
- Updated `drizzle-kit` to latest version
- Note: 4 moderate vulnerabilities remain in deprecated transitive dependencies (dev-only, not production)

### 2. Drizzle Kit not loading `.env.local` file

**Issue:** `drizzle-kit push` couldn't find `DATABASE_URL_EXTERNAL` environment variable

- `drizzle.config.ts` was trying to read `process.env.DATABASE_URL_EXTERNAL`
- Drizzle Kit doesn't automatically load `.env.local` files (only `.env`)

**Solution:**

Updated `drizzle.config.ts` to explicitly load environment files:

```typescript
import dotenv from "dotenv";
import { resolve } from "path";

// Load .env.local for local development, fallback to .env
dotenv.config({ path: resolve(process.cwd(), ".env.local") });
dotenv.config({ path: resolve(process.cwd(), ".env") });
```

This ensures `.env.local` is loaded first (for local dev), then falls back to `.env` if needed.

### 3. Postgres 18+ volume path change

**Issue:** Postgres container was failing to start with error about data directory format

- Postgres 18+ changed the data directory structure
- Old path: `/var/lib/postgresql/data`
- New path: `/var/lib/postgresql` (Postgres stores data in version-specific subdirectories)
- Container was crashing immediately after start

**Solution:**

Updated `docker-compose.dev.yml` to use the new volume path:

```yaml
volumes:
  - postgres_data_dev:/var/lib/postgresql # Changed from /var/lib/postgresql/data
```

Then removed the old volume and restarted:

```bash
docker-compose -f docker-compose.dev.yml down -v
docker-compose -f docker-compose.dev.yml up -d
```

### 4. Connection refused errors

**Issue:** `npm run db:push` was failing with `ECONNREFUSED` on port 5432

- Postgres container wasn't running
- Container was starting but immediately crashing due to volume path issue

**Solution:**

- Fixed the volume path issue (see #3 above)
- Ensured container starts and stays healthy
- Added healthcheck to `docker-compose.dev.yml` to verify Postgres is ready

---

## Prevention Checklist for Next Local Setup

### Before starting development:

- [ ] Verify Docker is installed and running: `docker --version`
- [ ] Check if Postgres container is already running: `docker ps | grep postgres`
- [ ] Create `.env.local` file with database credentials (see below)

### Environment variables setup:

Create `.env.local` in project root with:

```bash
POSTGRES_USER=myuser
POSTGRES_PASSWORD=mypassword
POSTGRES_DB=mydatabase
DATABASE_URL=postgres://myuser:mypassword@localhost:5432/mydatabase
DATABASE_URL_EXTERNAL=postgres://myuser:mypassword@localhost:5432/mydatabase
SECRET_KEY=my-secret
NEXT_PUBLIC_SAFE_KEY=safe-key
```

**Note:** These are placeholder values for local dev only - they don't need to be "real" or secure.

### After starting Postgres:

- [ ] Verify container is running: `docker-compose -f docker-compose.dev.yml ps`
- [ ] Check container is healthy (should show "healthy" status)
- [ ] Wait 3-5 seconds for Postgres to fully initialize before running `db:push`

### After pushing schema:

- [ ] Verify schema was created: `npm run db:studio` (should show tables)
- [ ] Test database connection in Next.js app

### If Postgres container fails to start:

- [ ] Check logs: `docker-compose -f docker-compose.dev.yml logs db`
- [ ] Verify volume path is `/var/lib/postgresql` (not `/var/lib/postgresql/data`)
- [ ] Remove old volumes and restart: `docker-compose -f docker-compose.dev.yml down -v && docker-compose -f docker-compose.dev.yml up -d`

### If Drizzle Kit can't find environment variables:

- [ ] Verify `.env.local` exists in project root
- [ ] Check `drizzle.config.ts` loads `.env.local` (should have `dotenv.config()` calls)
- [ ] Verify `DATABASE_URL_EXTERNAL` is set in `.env.local`
- [ ] Try using `.env` instead if `.env.local` isn't working

---

## Quick Reference Commands

### Start/Stop Postgres:

```bash
# Start
docker-compose -f docker-compose.dev.yml up -d

# Stop
docker-compose -f docker-compose.dev.yml down

# Stop and remove volumes (fresh start)
docker-compose -f docker-compose.dev.yml down -v
```

### Database operations:

```bash
# Push schema to database
npm run db:push

# Generate migrations
npm run db:generate

# Open Drizzle Studio (database GUI)
npm run db:studio
```

### Development:

```bash
# Start Next.js dev server
npm run dev

# Build for production
npm run build

# Start production server
npm run start
```

### Troubleshooting:

```bash
# View Postgres logs
docker-compose -f docker-compose.dev.yml logs db

# Check container status
docker-compose -f docker-compose.dev.yml ps

# Connect to Postgres directly
docker exec -it next-self-host-db-1 psql -U myuser -d mydatabase
```

---

**Note:** The fixes are now in the codebase, so future local setups should avoid these issues. The `drizzle.config.ts` loads `.env.local` automatically, and `docker-compose.dev.yml` uses the correct Postgres 18+ volume path.
