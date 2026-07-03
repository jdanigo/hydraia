---
name: dotnet-patterns
description: Use when writing C#/.NET backend code — ASP.NET Core APIs (minimal APIs or MVC), workers, EF Core data access. Builder playbook: layout, DI lifetimes, async/cancellation, EF Core discipline, options pattern, error contract, testing shape. Complements csharp-reviewer.
---

# C#/.NET Backend Patterns

## Layout

- Vertical slices (feature folders: endpoint + handler + models per feature) for API-shaped services; full Clean Architecture layering only when the domain genuinely warrants it — record the choice as an ADR either way.
- Minimal APIs for small/medium surfaces; MVC controllers when filters/model-binding complexity earns it.

## DI lifetimes (the classic traps)

- Scoped services must NEVER be captured by singletons (captive dependency — resolve via `IServiceScopeFactory` inside the singleton instead).
- `HttpClient` via `IHttpClientFactory`, never `new HttpClient()` per call (socket exhaustion).
- Register by interface at the boundary you intend to fake in tests; concrete elsewhere is fine.

## Async all the way

- No `.Result`/`.Wait()`/`GetAwaiter().GetResult()` on async paths — deadlock and threadpool starvation fuel.
- `CancellationToken` flows from the endpoint through every service and EF call: `await db.Orders.ToListAsync(ct)`. Endpoints accept it; libraries propagate it.
- `ValueTask` only where profiling justifies it; default is `Task`.

## EF Core discipline

- Reads: `AsNoTracking()` by default; project to DTOs with `Select` — never return entities from queries that don't update.
- No lazy-loading proxies: load explicitly (`Include`) so every query's shape is visible — N+1 becomes impossible to miss.
- Migrations: one migration per change, reviewed like code; destructive column changes follow expand-contract (see db-optimization skill).
- Transactions explicit where multi-write consistency matters (`ExecutionStrategy` + `TransactionScope`-free patterns with `BeginTransactionAsync`).

## Config — options pattern

- `IOptions<T>` with `ValidateDataAnnotations().ValidateOnStart()` — invalid config fails the boot, not the first request.
- Secrets from user-secrets/KeyVault/env — never appsettings committed values.

## Error contract

- `ProblemDetails` (RFC 9457) via `AddProblemDetails()`; exceptions mapped centrally (exception handler middleware), typed domain exceptions → status codes. No try/catch per controller.
- Nullable reference types ON project-wide; warnings as errors for new code.

## Testing shape

- xUnit; unit tests fake at the interface boundary.
- `WebApplicationFactory<Program>` for integration tests over the real pipeline (routing, filters, serialization) with a test database (Testcontainers where Docker exists).
- Snapshot the API surface where the contract matters (Verify/ApiApprovals) so drift is a failing test.
