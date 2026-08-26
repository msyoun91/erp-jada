import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import type { Database } from "./database.types";

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          );
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const url = request.nextUrl.clone();

  // Desactivar a alguien no le vence el access token: hasta que expire sigue
  // navegando el ERP con la sesión de antes. El corte va acá, antes de las
  // guardas de ruta, y `signOut()` limpia la cookie para que no vuelva.
  if (user) {
    const { data: perfil } = await supabase
      .from("usuarios")
      .select("activo")
      .eq("id", user.id)
      .single();

    if (!perfil?.activo) {
      await supabase.auth.signOut();

      // Ya está en /login: redirigir ahí sería un loop. La respuesta con la
      // cookie limpia alcanza.
      if (request.nextUrl.pathname === "/login") return supabaseResponse;

      url.pathname = "/login";
      url.search = "";
      url.searchParams.set("motivo", "inactivo");
      const redireccion = NextResponse.redirect(url);
      // El redirect es una respuesta nueva: sin copiar esto se pierde el
      // borrado de cookies que acaba de escribir `signOut()`.
      supabaseResponse.cookies
        .getAll()
        .forEach((cookie) => redireccion.cookies.set(cookie));
      return redireccion;
    }
  }

  // Con sesión abierta el formulario de login no tiene nada que ofrecer: sin
  // esta guarda, /login lo renderiza igual y deja re-autenticarse encima.
  if (user && request.nextUrl.pathname === "/login") {
    url.pathname = "/";
    url.search = "";
    return NextResponse.redirect(url);
  }

  if (!user && request.nextUrl.pathname !== "/login") {
    url.pathname = "/login";
    // Solo el pathname, no el search: un deep link a /tareas tiene que volver a
    // /tareas después de loguear, y los prefetch RSC arrastran un `?_rsc=` que
    // no sirve como destino.
    url.search = "";
    url.searchParams.set("next", request.nextUrl.pathname);
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
}
