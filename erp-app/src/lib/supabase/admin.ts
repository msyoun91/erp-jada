import { createClient } from "@supabase/supabase-js";
import type { Database } from "./database.types";

// `service_role`: pasa por encima de RLS. Solo servidor, y solo cuando RLS no puede expresar la
// autorización (GUIDE_DB.md).
export function createAdminClient() {
  return createClient<Database>(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!);
}
