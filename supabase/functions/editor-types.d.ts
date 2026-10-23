// Editor-only type hints so VS Code's TypeScript understands the Deno code in
// supabase/functions/. Supabase runs these functions on Deno, which has
// `Deno` and `npm:` imports built in; it never reads this file, and a file
// here (not in a function's own folder) is never deployed.

declare namespace Deno {
  export const env: { get(key: string): string | undefined };
  export function serve(handler: (req: Request) => Response | Promise<Response>): unknown;
}

declare module "npm:@supabase/supabase-js@2" {
  // The real client is fully typed at runtime; the editor only needs to know
  // the names exist.
  // deno-lint-ignore no-explicit-any
  export type SupabaseClient = any;
  // deno-lint-ignore no-explicit-any
  export function createClient(url: string, key: string, options?: any): SupabaseClient;
}
