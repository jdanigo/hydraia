---
name: node-patterns
description: Use when writing Node.js/TypeScript backend code — Express, Fastify, or NestJS services, APIs, workers. Builder playbook: project layout, async discipline, typed config, error taxonomy, DI boundaries, testing shape. Complements typescript-reviewer (this prevents, the reviewer catches).
---

# Node/TypeScript Backend Patterns

## Project layout

- Feature folders over layer folders: `src/orders/{orders.router,orders.service,orders.repo,orders.test}.ts` beats `src/{routes,services,repos}/orders.ts` scattered three places.
- One composition root (`src/app.ts`) wires everything; entry (`src/main.ts`) only boots. Handlers stay thin — parse/validate → service call → shape response.

## Async discipline

- No floating promises: every promise is awaited, returned, or explicitly `void`-ed with a comment. Unhandled rejection = crash in modern Node.
- Propagate `AbortSignal` through request-scoped work (fetch, DB timeouts); cancel on client disconnect for expensive handlers.
- No sync I/O (`readFileSync`, `execSync`) on request paths — boot time only.
- Concurrency with intent: `Promise.all` for independent work, `for…of await` when order matters, a limiter (`p-limit`) when fan-out is unbounded.

## Config

- Typed and validated at boot (zod or equivalent): missing/invalid env kills the process at startup with a clear message — never `process.env.X!` scattered through the codebase.
- One `config.ts` exports the parsed object; nothing else reads `process.env`.

## Errors

- Central error taxonomy: `AppError` subtypes with status + code (`NotFound`, `Validation`, `Conflict`, `Upstream`). Handlers throw domain errors; ONE error middleware maps them to responses (problem+json shape).
- Never `catch (e) {}` — swallow nothing; wrap-and-rethrow with context or let it propagate.

## DI boundaries

- NestJS: providers with explicit scopes; beware request-scoped bleeding into singletons.
- Express/Fastify: manual factories — services take dependencies as constructor/args, never import singletons directly. Makes the testing shape below possible.

## ESM/CJS pitfalls

- Pick ONE module system per package and align `"type"`, `tsconfig` `module`, and tooling. Mixed default/named interop errors are config bugs, not code bugs.
- `__dirname` does not exist in ESM — `import.meta.url` + `fileURLToPath`.

## Testing shape

- vitest/jest for units (services with faked repos), supertest against the composed app for HTTP behavior (status, body, headers — not internals).
- Test files co-located with the feature. Integration tests own their fixtures.

## Logging

- Structured (pino), request-correlated (request-id middleware); never `console.log` in request paths. Log the error object, not `err.message` alone (stack + cause matter).
