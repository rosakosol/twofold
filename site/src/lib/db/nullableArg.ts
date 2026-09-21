/**
 * Passes null to a Postgres function argument that accepts it.
 *
 * `supabase gen types typescript` renders every function argument as non-null, whether or not the
 * SQL accepts one — it reads the argument's type but not its nullability. Several of ours take
 * null as a meaningful value rather than as an absence:
 *
 *   * `admin_set_flight_limit(p_monthly_limit => null)` REMOVES the override, which is how support
 *     puts an account back on its tier default.
 *   * `admin_support_requests(p_status => null)` means every status rather than one.
 *   * `submit_support_request(p_name => null)` is a visitor who left the name field blank.
 *
 * So this is working around the generator, not around a contract — each of those behaviours has a
 * pgTAP test behind it. Named rather than inlined so the cast is explained once and is greppable
 * if the generator ever learns about nullability and these can all come out.
 */
export function nullableArg<T>(value: T | null): T {
  return value as unknown as T;
}
