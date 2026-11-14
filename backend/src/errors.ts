/** Errors that are safe to show to the client. Anything else becomes a generic 500. */
export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export const badRequest = (code: string, msg: string) => new ApiError(400, code, msg);
export const unauthorized = (msg = 'Sign in required') => new ApiError(401, 'UNAUTHENTICATED', msg);
export const forbidden = (code = 'FORBIDDEN', msg = 'Not allowed') => new ApiError(403, code, msg);
export const notFound = (msg = 'Not found') => new ApiError(404, 'NOT_FOUND', msg);
export const conflict = (code: string, msg: string) => new ApiError(409, code, msg);
export const tooMany = (code: string, msg: string) => new ApiError(429, code, msg);

/** Postgres unique-violation code. */
export const PG_UNIQUE_VIOLATION = '23505';

export function isPgError(err: unknown, code: string, constraint?: string): boolean {
  const e = err as { code?: string; constraint?: string };
  return e?.code === code && (constraint === undefined || e.constraint === constraint);
}
