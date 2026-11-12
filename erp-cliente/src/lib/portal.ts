// El navegador nunca habla con la base: lo hace este servidor, con la clave publicable y las funciones de `anon`.
export async function rpc<T>(funcion: string, args: Record<string, unknown>): Promise<T> {
  const url = process.env.PORTAL_SUPABASE_URL;
  const clave = process.env.PORTAL_SUPABASE_ANON_KEY;
  if (!url || !clave) throw new Error("Falta configurar el portal");
  const r = await fetch(`${url}/rest/v1/rpc/${funcion}`, {
    method: "POST",
    headers: { apikey: clave, Authorization: `Bearer ${clave}`, "Content-Type": "application/json" },
    body: JSON.stringify(args),
    cache: "no-store",
  });
  if (!r.ok) throw new Error(`${funcion}: ${r.status}`);
  const texto = await r.text();
  return (texto ? JSON.parse(texto) : null) as T;
}
