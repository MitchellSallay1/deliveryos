/**
 * PostgREST's `.or()` filter syntax uses `,` to separate conditions and
 * `()` to group them. Building an `.or()` string by interpolating raw user
 * search input lets a term containing those characters break out of the
 * intended filter group — e.g. add unrelated conditions or reference
 * unintended columns within the same query. RLS still scopes the result set
 * by tenant regardless, but the query itself should not be malleable by
 * user input. Strip the PostgREST-significant characters before building
 * an ilike search term; `%`/`_` are left intact since they're the intended
 * ilike wildcards.
 */
export function sanitizeIlikeSearchTerm(term: string): string {
  return term.replace(/[,()]/g, ' ').trim()
}
