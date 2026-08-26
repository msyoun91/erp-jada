import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

export async function proxy(request: NextRequest) {
  return await updateSession(request);
}

// Las fuentes faltaban en la lista de extensiones: sin sesión, `/fonts/*.woff2`
// se comía el chequeo de auth y devolvía un 307 a `/login`, así que la tipografía
// nunca cargaba y `?next=` se llenaba de destinos basura.
export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico|woff|woff2|ttf|otf)$).*)",
  ],
};
